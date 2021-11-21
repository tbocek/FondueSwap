// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

interface LPMint {
    function mint(address to, address _poolToken, uint256 _poolShare, uint256 _poolShareAtEth, uint256 _poolAccEthFee, uint256 _poolAccTokenFees) external returns (uint256);
}

interface IERC677Receiver {
    function onTokenTransfer(address sender, uint nftId, bytes calldata data) external;
}

contract FondueLPNFT is ERC721Burnable, LPMint {

    mapping(uint256 => LPInfo) public _lpInfos;
    struct LPInfo {
        uint256 poolShares;
        uint256 poolShareAtEth;
        uint256 poolAccEthFee;
        uint256 poolAccTokenFee;
    }
    uint256 private counter;
    address public swapAddress;
    address public owner;

    constructor() ERC721("FondueLPNFT", "FLPNFT") {
        owner = msg.sender;
    }
    function mint(address to, address _tokenAddress, uint256 _poolShare, uint256 _poolShareAtEth, uint256 _poolAccEthFee, uint256 _poolAccTokenFee) external returns (uint256) {
        require(msg.sender == swapAddress);
        uint256 nftId = ((uint256(uint160(_tokenAddress)) << 96) | counter);
        _mint(to, nftId);
        _lpInfos[nftId]= LPInfo(_poolShare, _poolShareAtEth, _poolAccEthFee, _poolAccTokenFee);
        counter++;
        return nftId;
    }
    function lpInfos(uint256 nftId) external view returns (uint256 poolShares, uint256 _poolShareAtEth, uint256 poolAccEthFee, uint256 poolAccTokenFee){
        LPInfo memory lp = _lpInfos[nftId];
        return (lp.poolShares, lp.poolShareAtEth, lp.poolAccEthFee, lp.poolAccTokenFee);
    }
    function setSwapAddress(address newSwapAddress) public {
        require(msg.sender == owner);
        swapAddress = newSwapAddress;
    }

}

contract FondueSwap is IERC677Receiver {

    event SwapToToken(address tokenAddress, uint256 tokenAmount, uint256 ethAmount);
    event SwapToEth(address tokenAddress, uint256 tokenAmount, uint256 ethAmount);
    event AddLiquidity(address tokenAddress, uint256 tokenAmount, uint256 ethAmount, uint256 poolShare, uint256 poolShareAtEth, uint256 nftId);

    mapping(address => Pool) private _pools;

    struct Pool {
        uint256 eth;
        uint256 token;
        uint256 ethFee;
        uint256 tokenFee;
        uint256 accEthFee;
        uint256 accTokenFee;
        uint256 startBlockNr;
    }

    address private lpAddress;
    uint256 private constant PRECISION = 10 ** 12;

    constructor(address _lpAddress) {
        lpAddress = _lpAddress;
    }

    function addLiquidity(address _tokenAddress, uint256 _maxTokenAmount) public payable {
        Pool storage p = _pools[_tokenAddress];

        uint256 tokenAmount = _maxTokenAmount;
        if (p.token == 0 || p.eth == 0) {
            require(msg.value > 0 && _maxTokenAmount > 0);

            SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), _maxTokenAmount);
            p.token += _maxTokenAmount;
            p.eth += msg.value;
            p.startBlockNr = block.number;
        }
        else {
            //Y = p.token, X=p.eth, y=_tokenAmount, x=msg.value - ROUND DOWN
            tokenAmount = (msg.value * (p.token + p.tokenFee)) / ((p.eth + p.ethFee) + (2 * msg.value));
            require(_maxTokenAmount >= tokenAmount, "max token reached");

            SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), tokenAmount);
            p.token += tokenAmount;
            p.eth += msg.value;
        }
        //hand out LP tokens
        uint256 poolShare = (PRECISION * msg.value) / (p.eth + p.ethFee);
        uint256 nftId = LPMint(lpAddress).mint(msg.sender, _tokenAddress, poolShare, p.eth + p.ethFee, p.accEthFee, p.accTokenFee);
        emit AddLiquidity(_tokenAddress, tokenAmount, msg.value, poolShare, p.eth + p.ethFee, nftId);
    }

    //remove liquidity
    function onTokenTransfer(address sender, uint256 nftId, bytes calldata) external {
        require(msg.sender == lpAddress, "not the LP NFT");
        //calculate the payout, first without the fees
        address poolTokenAddress = address(uint160(nftId >> 96));
        (uint256 poolShare, uint256 poolSharedAtEth, uint256 accEthFee, uint256 accTokenFee) = FondueLPNFT(msg.sender).lpInfos(nftId);
        Pool storage p = _pools[poolTokenAddress];

        uint256 adjustedPoolShare = poolShare * poolSharedAtEth / p.eth;
        uint256 ethAmount = adjustedPoolShare * p.eth / PRECISION;
        uint256 tokenAmount = adjustedPoolShare * p.token / PRECISION;
        p.eth -= ethAmount;
        p.token -= tokenAmount;

        //calculate share of the fee earnings
        uint256 ethFeeAmount = adjustedPoolShare * (p.accEthFee - accEthFee) / PRECISION;
        uint256 tokenFeeAmount = adjustedPoolShare * (p.accTokenFee - accTokenFee) / PRECISION;
        p.ethFee -= ethFeeAmount;
        p.tokenFee -= tokenFeeAmount;

        payable(sender).transfer(ethAmount + ethFeeAmount);
        //SafeERC20.safeTransferFrom(IERC20(poolTokenAddress), address(this), sender, tokenAmount + tokenFeeAmount);
        ERC721Burnable(msg.sender).burn(nftId);
    }

    function harvest() external {

    }

    function balanceOf(uint256 nftId) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        address tokenAddress = address(uint160(nftId >> 96));
        (uint256 poolShare, uint256 poolSharedAtEth, uint256 accEthFee, uint256 accTokenFee) = FondueLPNFT(lpAddress).lpInfos(nftId);

        Pool memory p = _pools[tokenAddress];
        uint256 adjustedPoolShare = poolShare * poolSharedAtEth / p.eth;
        uint256 _ethAmount = adjustedPoolShare * p.eth / PRECISION;
        uint256 _tokenAmount = adjustedPoolShare * p.token / PRECISION;
        //calculate share of the fee earnings
        uint256 ethFeeAmount = adjustedPoolShare * (p.accEthFee - accEthFee) / PRECISION;
        uint256 tokenFeeAmount = adjustedPoolShare * (p.accTokenFee - accTokenFee) / PRECISION;
        return (_ethAmount + ethFeeAmount, _tokenAmount + tokenFeeAmount);
    }

    function poolBalanceOf(address poolTokenAddress) external view returns (uint256 ethAmount, uint256 tokenAmount, uint256 priceRatio) {
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
        uint256 tokenFee = ethFee * (p.token - p.tokenFee) / (p.eth + p.ethFee);
        require(_minEthAmount <= ethAmount - ethFee, "min eth not reached");

        p.token -= tokenFee;
        p.tokenFee += tokenFee;
        p.accTokenFee += tokenFee;
        p.eth -= ethFee;
        p.ethFee += ethFee;
        p.accEthFee += ethFee;

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
        uint256 tokenFee = ((2 * tokenAmount) + 999) / 1000;
        uint256 ethFee = tokenFee *  (p.eth + p.ethFee) / (p.token - p.tokenFee);
        require(_minTokenAmount <= tokenAmount - tokenFee, "min token not reached");

        p.token -= tokenFee;
        p.tokenFee += tokenFee;
        p.accTokenFee += tokenFee;
        p.eth -= ethFee;
        p.ethFee += ethFee;
        p.accEthFee += ethFee;

        ////do the transfer, ETH transfer already happend
        SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, tokenAmount - tokenFee);
        emit SwapToToken(_tokenAddress, tokenAmount, msg.value);
    }
}
