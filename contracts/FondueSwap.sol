// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

interface IERC677Receiver {
    function onTokenTransfer(address sender, uint nftId, bytes calldata data) external;
}

contract FondueLPNFT is ERC721 {

    mapping(uint256 => LPInfo) public _lpInfos;
    struct LPInfo {
        uint256 poolShare;
        uint256 poolAccRatioEth;
        uint256 poolAccRatioToken;
    }
    uint256 private counter;
    address public swapAddress;
    address public owner;

    constructor() ERC721("FondueLPNFT", "FLPNFT") {
        owner = msg.sender;
    }
    function mint(address to, address _tokenAddress, uint256 _poolShare, uint256 _poolAccRatioEth, uint256 _poolAccRatioToken) external returns (uint256) {
        require(msg.sender == swapAddress);
        uint256 nftId = ((uint256(uint160(_tokenAddress)) << 96) | counter);
        _mint(to, nftId);
        _lpInfos[nftId]= LPInfo(_poolShare, _poolAccRatioEth, _poolAccRatioToken);
        counter++;
        return nftId;
    }
    function lpInfos(uint256 nftId) external view returns (uint256 poolShare, uint256 poolAccRatioEth, uint256 poolAccRatioToken) {
        LPInfo memory lp = _lpInfos[nftId];
        return (lp.poolShare, lp.poolAccRatioEth, lp.poolAccRatioToken);
    }
    function setSwapAddress(address newSwapAddress) external {
        require(msg.sender == owner);
        swapAddress = newSwapAddress;
    }
    function burn(uint256 nftId) external {
        require(msg.sender == swapAddress);
        _burn(nftId);
    }
    function updateLP(uint256 nftId, uint256 _poolShare, uint256 _poolAccRatioEth, uint256 _poolAccRatioToken) external {
        require(msg.sender == swapAddress);
        _lpInfos[nftId]= LPInfo(_poolShare, _poolAccRatioEth, _poolAccRatioToken);
    }
}

contract FondueSwap is IERC677Receiver {

    event SwapToToken(address tokenAddress, uint256 tokenAmount, uint256 ethAmount);
    event SwapToEth(address tokenAddress, uint256 tokenAmount, uint256 ethAmount);
    event AddLiquidity(address tokenAddress, uint256 tokenAmount, uint256 ethAmount, uint256 nftId);

    mapping(address => Pool) private _pools;

    struct Pool {
        uint256 eth;
        uint256 token;
        uint256 ethFee;
        uint256 tokenFee;
        uint256 accRatioEth;
        uint256 accRatioToken;
        uint256 liquidity;
    }

    address private lpAddress;
    uint256 private constant PRECISION = 1e12;

    constructor(address _lpAddress) {
        lpAddress = _lpAddress;
    }

    function addLiquidity(address _tokenAddress, uint256 _maxTokenAmount) public payable {
        Pool storage p = _pools[_tokenAddress];

        uint256 tokenAmount = _maxTokenAmount;
        if (p.token > 0 && p.eth > 0) {
            //Y = p.token, X=p.eth, y=_tokenAmount, x=msg.value - ROUND DOWN
            tokenAmount = (msg.value * (p.token + p.tokenFee)) / ((p.eth + p.ethFee) + (2 * msg.value));
            require(_maxTokenAmount >= tokenAmount, "max token reached");
        }
        require(msg.value > 0 && tokenAmount > 0, "no liquidity provided");

        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), tokenAmount);
        p.token += tokenAmount;
        p.eth += msg.value;
        p.liquidity += msg.value + tokenAmount;

        //hand out LP tokens
        uint256 poolShare = (PRECISION * msg.value * tokenAmount) / ((p.eth + p.ethFee) * (p.token + p.tokenFee));
        uint256 nftId = FondueLPNFT(lpAddress).mint(msg.sender, _tokenAddress, msg.value + tokenAmount, p.accRatioEth, p.accRatioToken);
        emit AddLiquidity(_tokenAddress, tokenAmount, msg.value, nftId);
    }

    //remove liquidity
    function onTokenTransfer(address sender, uint256 nftId, bytes calldata) external {
        require(msg.sender == lpAddress, "not the LP NFT");
        (uint256 totalEthAmount, uint256 totalTokenAmount) = harvestInternal(nftId);
        payable(sender).transfer(totalEthAmount);
        address poolTokenAddress = address(uint160(nftId >> 96));
        SafeERC20.safeTransferFrom(IERC20(poolTokenAddress), address(this), sender, totalTokenAmount);
        FondueLPNFT(sender).burn(nftId);
    }
    function harvest(uint256 nftId) external {
        // TODO: this call harvestInternal(), similar to onTokenTransfer, but instead burning it, we addLiquidity(), and update the NFT via updateLP
    }

    function balanceOf(uint256 nftId) external view returns (uint256 totalEthAmount, uint256 totalTokenAmount) {
        (uint256 poolShare, uint256 poolAccRatio, uint256 poolAccRatioAtNr) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool memory p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress

        uint256 adjustedPoolShare = p.liquidity * PRECISION / poolShare;

        console.log("PRECISION:         ", PRECISION);
        console.log("poolShare:         ", poolShare);
        console.log("totalNow:          ", p.eth * p.token);
        console.log("p.eth:             ", p.eth);
        console.log("p.eth + p.ethFee:  ", p.eth + p.ethFee);
        console.log("adjustedPoolShare: ", adjustedPoolShare);
        console.log("p.token:           ", p.token);
        console.log("p.token+p.tokenFee:", p.token+p.tokenFee);
        console.log("price ratio:       ", ((p.token+p.tokenFee) * PRECISION) / (p.eth + p.ethFee));
        //uint256 adjustedPoolShare = poolShare * poolSharedAtEth / (p.eth * p.token);
        uint256 ethAmount = (adjustedPoolShare * (p.eth)) / PRECISION;
        uint256 tokenAmount = (adjustedPoolShare * (p.token)) / PRECISION;

        console.log("I have raw eth:", ethAmount);
        console.log("I have raw tok:", tokenAmount);

        //if(p.accNr - poolAccRatioAtNr > 0) {
            console.log("poolAccRatioAtNr:", poolAccRatioAtNr);
            uint256 ethFeeAmount = ((p.accRatioEth - poolAccRatio) * poolShare) / PRECISION;
            uint256 tokenFeeAmount = ((p.accRatioToken - poolAccRatio) * poolShare) / PRECISION;
            console.log("ethFeeAmount is:", ethFeeAmount);
            console.log("ethFeeAmount sh:", ((adjustedPoolShare * (p.eth + p.ethFee)) / PRECISION)-ethAmount);
            console.log("ethFeeAmount sh:", (((adjustedPoolShare * (p.eth + p.ethFee)) / PRECISION)-ethAmount) - ethFeeAmount);
            console.log("tokenFeeAmount is:", tokenFeeAmount);
            console.log("tokenFeeAmount sh:", ((adjustedPoolShare * (p.token + p.tokenFee)) / PRECISION) - tokenAmount);
            console.log("tokenFeeAmount sh:", (((adjustedPoolShare * (p.token + p.tokenFee)) / PRECISION) - tokenAmount) - tokenFeeAmount);

            console.log("p.eth + p.ethFee:  ", p.eth + p.ethFee);
            console.log("MY eth          :  ", ethAmount + ethFeeAmount);
            console.log("p.token+p.tokenFee:", p.token+p.tokenFee);
            console.log("MY tok            :", tokenAmount + tokenFeeAmount);

            return (ethAmount + ethFeeAmount, tokenAmount + tokenFeeAmount);
        //}
        return (ethAmount, tokenAmount);
    }

    function harvestInternal(uint256 nftId) internal returns (uint256 totalEthAmount, uint256 totalTokenAmount) {
        (uint256 poolShare, uint256 poolAccRatio, uint256 poolAccRatioAtNr) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool storage p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress

        /*uint256 adjustedPoolShare = poolShare * poolSharedAtEth / (p.eth * p.token);
        uint256 ethAmount = adjustedPoolShare * p.eth / PRECISION;
        uint256 tokenAmount = adjustedPoolShare * p.token / PRECISION;
        p.eth -= ethAmount;
        p.token -= tokenAmount;

        if(block.number - poolAccRatioAtNr > 0) {
            uint256 ethFeeAmount = ethAmount * (p.accRatio - poolAccRatio) / ((block.number - poolAccRatioAtNr) * PRECISION);
            uint256 tokenFeeAmount = tokenAmount * (p.accRatio - poolAccRatio) / ((block.number - poolAccRatioAtNr) * PRECISION);
            p.ethFee -= ethFeeAmount;
            p.tokenFee -= tokenFeeAmount;
            return (ethAmount + ethFeeAmount, tokenAmount + tokenFeeAmount);
        }
        return (ethAmount, tokenAmount);*/
        return (poolShare, poolAccRatio);
    }

    function poolInfo(address poolTokenAddress) external view returns (uint256 totalEthAmount, uint256 totalTokenAmount, uint256 priceRatio) {
        Pool memory p = _pools[poolTokenAddress];
        return (p.eth + p.ethFee, p.token + p.tokenFee, ((p.token+p.tokenFee) * PRECISION) / (p.eth + p.ethFee));
    }

    //calculates how much tokens is needed to get _ethAmount out of this pool
    function priceOfEth(address _tokenAddress, uint256 _ethAmount) external view returns (uint256) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return 0;
        }
        uint256 ethToSwap = ((((_ethAmount * 1000) + 999) + 997) / 998); //round up
        require(p.eth + p.ethFee > (2 * ethToSwap), "cannot get more ETHs than available in the pool");
        uint256 tokenAmount = (ethToSwap * (p.token + p.tokenFee)) / ((p.eth + p.ethFee) - (2 * ethToSwap));

        return tokenAmount;
    }

    function swapToEth(address _tokenAddress, uint256 _tokenAmount, uint256 _minEthAmount, uint96 _deadline) public payable {
        //deadline of 0, means no deadline
        require(_deadline == 0 || _deadline > block.timestamp, "tx too old");
        require(IERC20(_tokenAddress).allowance(msg.sender, address(this)) > 0, "token no allowance");
        Pool storage p = _pools[_tokenAddress];
        require(p.token > 0 && p.eth > 0, "pool cannot be empty");

        uint256 ethAmount = (_tokenAmount * (p.eth + p.ethFee)) / ((p.token + p.tokenFee) + (2 * _tokenAmount));
        require(ethAmount > 0, "eth must be positive");

        p.token += _tokenAmount;
        p.eth -= ethAmount;

        //fees, don't change the ratio
        uint256 ethFee = ((2 * ethAmount) + 999) / 1000;
        uint256 tokenFee = (ethFee * (p.token + p.tokenFee)) / (p.eth + p.ethFee);
        console.log("min", _minEthAmount);
        console.log("dif", ethAmount - ethFee);
        require(_minEthAmount <= ethAmount - ethFee, "min eth not reached");

        p.token -= tokenFee;
        p.tokenFee += tokenFee;
        p.eth -= ethFee;
        p.ethFee += ethFee;
        //use eth here, since eth is based on token and may including rounding
        p.accRatioEth += (ethFee * PRECISION) / (p.liquidity);
        p.accRatioToken += (tokenFee * PRECISION) / (p.liquidity);

        //do the transfer
        payable(msg.sender).transfer(ethAmount - ethFee);
        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), _tokenAmount);
        emit SwapToEth(_tokenAddress, _tokenAmount, ethAmount);
    }

    function priceOfToken(address _tokenAddress, uint256 _tokenAmount) external view returns (uint256) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return 0;
        }
        uint256 tokenToSwap = ((((_tokenAmount * 1000) + 999) + 997) / 998); //round up
        require(p.token + p.tokenFee > (2 * tokenToSwap), "cannot get more tokens than available in the pool");
        uint256 ethAmount = (tokenToSwap * (p.eth + p.ethFee)) / ((p.token + p.tokenFee) - (2 * tokenToSwap));

        return ethAmount;
    }

    function swapToToken(address _tokenAddress, uint256 _minTokenAmount, uint96 _deadline) public payable {
        //deadline of 0, means no deadline
        require(_deadline == 0 || _deadline > block.timestamp, "tx too old");
        require(msg.value > 0, "eth must be positive");
        Pool storage p = _pools[_tokenAddress];
        require(p.token > 0 && p.eth > 0, "pool cannot be empty");

        uint256 tokenAmount = (msg.value * (p.token + p.tokenFee)) / ((p.eth + p.ethFee) + (2 * msg.value));
        require(tokenAmount > 0, "tokenAmount must be positive");

        p.eth += msg.value;
        p.token -= tokenAmount;

        //fees, don't change the ratio
        uint256 tokenFee = ((2 * tokenAmount) + 999) / 1000; //round up
        uint256 ethFee = (tokenFee *  (p.eth + p.ethFee)) / (p.token + p.tokenFee);
        require(_minTokenAmount <= tokenAmount - tokenFee, "min token not reached");

        p.token -= tokenFee;
        p.tokenFee += tokenFee;
        //use token here, since eth is based on token and may including rounding
        console.log("before accRatioEth  :", p.accRatioEth);
        console.log("before accRatioToken  :", p.accRatioToken);
        console.log("before tokenFee  :", tokenFee);
        console.log("before p.liquidity:", p.liquidity);
        p.accRatioToken += (tokenFee * PRECISION) / (p.liquidity);
        p.accRatioEth += (ethFee * PRECISION) / (p.liquidity);
        console.log("after accRatioEth  :", p.accRatioEth);
        console.log("after accRatioToken  :", p.accRatioToken);
        p.eth -= ethFee;
        p.ethFee += ethFee;

        ////do the transfer, ETH transfer already happened
        SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, tokenAmount - tokenFee);
        emit SwapToToken(_tokenAddress, tokenAmount, msg.value);
    }
}
