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
        uint256 ethAmount;
        uint256 tokenAmount;
        uint256 poolAccWin;
    }
    uint256 private counter;
    address public swapAddress;
    address public owner;

    constructor() ERC721("FondueLPNFT", "FLPNFT") {
        owner = msg.sender;
    }
    function mint(address to, address _tokenAddress, uint256 _ethAmount, uint256 _tokenAmount, uint256 _poolAccWin) external returns (uint256) {
        require(msg.sender == swapAddress);
        uint256 nftId = ((uint256(uint160(_tokenAddress)) << 96) | counter);
        _mint(to, nftId);
        _lpInfos[nftId]= LPInfo(_ethAmount, _tokenAmount, _poolAccWin);
        counter++;
        return nftId;
    }
    function lpInfos(uint256 nftId) external view returns (uint256 ethAmount, uint256 tokenAmount, uint256 poolAccWin) {
        LPInfo memory lp = _lpInfos[nftId];
        return (lp.ethAmount, lp.tokenAmount, lp.poolAccWin);
    }
    function setSwapAddress(address newSwapAddress) external {
        require(msg.sender == owner);
        swapAddress = newSwapAddress;
    }
    function burn(uint256 nftId) external {
        require(msg.sender == swapAddress);
        _burn(nftId);
    }
    function updateLP(uint256 nftId, uint256 _ethAmount, uint256 _tokenAmount, uint256 _poolAccWin) external {
        require(msg.sender == swapAddress);
        _lpInfos[nftId]= LPInfo(_ethAmount, _tokenAmount, _poolAccWin);
    }

    //not needed, but hardhat cannot for unknown reasons do a safeTransferFrom
    function removeLiquidity(address a, uint256 nftId) public {
        require(msg.sender == owner);
        FondueSwap(swapAddress).onTokenTransfer(a, nftId, "");
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
        uint256 ethTotal;
        uint256 tokenTotal;
        uint256 accGain;
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
            tokenAmount = (msg.value * p.token) / p.eth;
            require(_maxTokenAmount >= tokenAmount, "max token reached");
        }
        require(msg.value > 0 && tokenAmount > 0, "no liquidity provided");

        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), tokenAmount);
        p.token += tokenAmount;
        p.eth += msg.value;
        p.ethTotal += msg.value;
        p.tokenTotal += tokenAmount;
        //hand out LP tokens
        uint256 nftId = FondueLPNFT(lpAddress).mint(msg.sender, _tokenAddress, msg.value, tokenAmount, p.accGain);
        emit AddLiquidity(_tokenAddress, tokenAmount, msg.value, nftId);
    }

    //remove liquidity
    function onTokenTransfer(address sender, uint256 nftId, bytes calldata) external {
        /*require(msg.sender == lpAddress, "not the LP NFT");
        (uint256 liquidity, uint256 accGain) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool storage p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 ethAmount, uint256 ethAmountFee, uint256 tokenAmount, uint256 tokenAmountFee) = balanceOf(p, liquidity, accGain);
        p.eth -= (ethAmount + ethAmountFee);
        p.token -= (tokenAmount + tokenAmountFee);
        p.liquidity -= liquidity;
        payable(sender).transfer(ethAmount + ethAmountFee);
        SafeERC20.safeTransfer(IERC20(address(uint160(nftId >> 96))), sender, tokenAmount + tokenAmountFee);
        FondueLPNFT(lpAddress).burn(nftId);*/
    }

    function harvest(uint256 nftId) external {
        /*address nftOwner = FondueLPNFT(lpAddress).ownerOf(nftId);
        require(nftOwner != address(0), "owner not found");
        (uint256 liquidity, uint256 accGain) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool storage p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (,uint256 ethAmountFee,, uint256 tokenAmountFee) = balanceOf(p, liquidity, accGain);
        p.eth -= ethAmountFee;
        p.token -= tokenAmountFee;
        payable(nftOwner).transfer(ethAmountFee);
        SafeERC20.safeTransfer(IERC20(address(uint160(nftId >> 96))), nftOwner, tokenAmountFee);
        FondueLPNFT(lpAddress).updateLP(nftId, liquidity, p.accGain);*/
    }

    function balanceOf(uint256 nftId) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        (uint256 ethAmount, uint256 tokenAmount, uint256 accGain) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool memory p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 _ethAmount, uint256 _ethAmountFee, uint256 _tokenAmount, uint256 _tokenAmountFee) = balanceOf(p, ethAmount, tokenAmount, accGain);
        return (_ethAmount + _ethAmountFee, _tokenAmount + _tokenAmountFee);
    }

    function balanceOf(Pool memory p, uint256 _ethAmount, uint256 _tokenAmount, uint256 accGain) internal view returns (uint256 ethAmount, uint256 ethAmountFee, uint256 tokenAmount, uint256 tokenAmountFee) {

        uint256 price = (_ethAmount * p.token / p.eth) + _tokenAmount;
        //ethAmount = sqrt(liquidity * p.eth / p.token);
        //tokenAmount = sqrt(liquidity * p.token / p.eth);

        ethAmount = price / (2*(p.token / p.eth));
        tokenAmount = ethAmount * p.token / p.eth;

        console.log("ethAmount",ethAmount);
        console.log("tokenAmount",tokenAmount);

        //uint256 liquidityGain = (price * (p.accGain - accGain)) / PRECISION;
        //ethAmountFee = sqrt(liquidityGain * p.eth / p.token);
        //tokenAmountFee = sqrt(liquidityGain * p.token / p.eth);

        //console.log("ethAmountFee",ethAmountFee);
        //console.log("tokenAmountFee",tokenAmountFee);

        return (ethAmount, 0, tokenAmount, 0);
    }

    function poolInfo(address poolTokenAddress) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        Pool memory p = _pools[poolTokenAddress];
        return (p.eth, p.token);
    }

    //calculates how much tokens is needed to get _ethAmount out of this pool
    function priceOfEth(address _tokenAddress, uint256 _ethAmount) external view returns (uint256 tokenAmount, uint256 tokenFee, uint256 ethFee) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return (0, 0, 0);
        }
        require(p.eth > (2 * _ethAmount) + 1, "eth amount too high");
        tokenAmount = ((_ethAmount * p.token) - 1) / (p.eth - (2 * _ethAmount)) + 1;

        uint256 peth = p.eth - _ethAmount;
        uint256 ptoken = p.token + tokenAmount;

        uint256 origPrice = p.ethTotal * ptoken / peth + p.tokenTotal;
        uint256 currPrice = 2 * ptoken;
        console.log("11 origPrice", origPrice);
        console.log("11 currPrice", currPrice);

        uint256 loss = origPrice - currPrice;
        uint256 ethFee = loss / (2*(p.token / p.eth));
        uint256 tokenFee = ethFee * p.token / p.eth;
        console.log("11 loss", loss);
        console.log("11 TtokenFee", tokenFee);
        console.log("11 EEthFee", ethFee);
        console.log("11 TOK", tokenAmount + tokenFee);
        return (tokenAmount, tokenFee, ethFee);
    }

    function swapToEth(address _tokenAddress, uint256 _tokenAmount, uint256 _minEthAmount, uint96 _deadline) public payable {
        //deadline of 0, means no deadline
        require(_deadline == 0 || _deadline > block.timestamp, "tx too old");
        require(_tokenAmount > 0, "tokenAmount must be positive");
        require(IERC20(_tokenAddress).allowance(msg.sender, address(this)) >= _tokenAmount, "token no allowance");
        Pool storage p = _pools[_tokenAddress];
        require(p.token > 0 && p.eth > 0, "pool cannot be empty");

        uint256 ethAmount = (_tokenAmount * p.eth) / (p.token + (2 * _tokenAmount));
        require(ethAmount > 0, "eth must be positive");
        require(_minEthAmount <= ethAmount, "min eth not reached");

        uint256 previousLiquidity = p.eth * p.token;
        p.eth -= ethAmount;
        p.token += _tokenAmount;

        //now we need to "donate" liquidity to not have any impermanent loss
        uint256 origPrice = p.ethTotal * p.token / p.eth + p.tokenTotal;
        uint256 currPrice = p.eth * p.token / p.eth + p.token;

        console.log("origPrice", origPrice);
        console.log("currPrice", currPrice);

        uint256 ethFee = 0;
        uint256 tokenFee = 0;
        uint256 loss = 0;

        loss = origPrice - currPrice;
        ethFee = loss / (2*(p.token / p.eth));
        tokenFee = ethFee * p.token / p.eth;
        console.log("loss", loss);
        console.log("TtokenFee", tokenFee);
        console.log("EEthFee", ethFee);

        p.eth += ethFee;
        p.token += tokenFee;

        //p.accGain += loss * PRECISION / origPrice;

        //do the transfer
        payable(msg.sender).transfer(ethAmount - ethFee);
        console.log("transfer", _tokenAmount + tokenFee);
        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), _tokenAmount + tokenFee);
        emit SwapToEth(_tokenAddress, _tokenAmount, ethAmount);
    }

    function priceOfToken(address _tokenAddress, uint256 _tokenAmount) external view returns (uint256 ethAmount, uint256 tokenFee, uint256 ethFee) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return (0, 0, 0);
        }
        require(p.token > (2 * _tokenAmount) + 1, "token amount too high");
        ethAmount = ((_tokenAmount * p.eth) - 1) / (p.token - (2 * _tokenAmount)) + 1;

        console.log("_tokenAmount", _tokenAmount);
        console.log("p.token", p.token);
        console.log("ee", (((p.token * p.ethTotal) - p.tokenTotal) / (2 * p.eth)));
        uint256 R = p.token - _tokenAmount - (((p.token * p.ethTotal) - p.tokenTotal) / (2 * p.eth));
        console.log("R", R);

        uint256 ee = (R*p.eth)/((p.token*p.ethTotal*2*p.eth)-(R*2));

        console.log("ee", ee);

        uint256 peth = p.eth + ethAmount;
        uint256 ptoken = p.token - _tokenAmount;

        console.log("new price", ptoken/peth);

        console.log("22 peth", peth);
        console.log("22 ptoken", ptoken);

        uint256 origPrice = (p.ethTotal * ptoken / peth) + p.tokenTotal;
        uint256 currPrice = 2 * ptoken;
        console.log("22 origPrice", origPrice);
        console.log("22 currPrice", currPrice);

        uint256 gain = currPrice - origPrice;
        tokenFee = gain / 2;
        ethFee = peth * tokenFee / ptoken;
        //uint256 ethFee = gain * p.eth / (2*(p.token));
        //uint256 tokenFee = ethFee * p.token / p.eth;
        console.log("22 loss", gain);
        console.log("22 TtokenFee", tokenFee);
        console.log("22 EEthFee", ethFee);
        console.log("22 TOK", _tokenAmount + tokenFee);
        return (ethAmount, tokenFee, ethFee);

    }

    function swapToToken(address _tokenAddress, uint256 _minTokenAmount, uint96 _deadline) public payable {
        //deadline of 0, means no deadline
        require(_deadline == 0 || _deadline > block.timestamp, "tx too old");
        require(msg.value > 0, "eth must be positive");
        Pool storage p = _pools[_tokenAddress];
        require(p.token > 0 && p.eth > 0, "pool cannot be empty");

        uint256 tokenAmount = (msg.value * p.token) / (p.eth + (2 * msg.value));
        require(tokenAmount > 0, "tokenAmount must be positive");
        require(_minTokenAmount <= tokenAmount, "min token not reached");

        //now we need to withdraw liquidity to not have any impermanent gain
        //uint256 tokenFee = (p.token - tokenAmount) - (p.ethTotal * (p.token - tokenAmount) / (2 * (p.eth + msg.value))) + (p.tokenTotal / 2);

        uint256 tokenFee = (p.token - ((msg.value * p.token) / (p.eth + (2 * msg.value)))) - (p.ethTotal * (p.token - ((msg.value * p.token) / (p.eth + (2 * msg.value)))) / (2 * (p.eth + msg.value))) + (p.tokenTotal / 2);
        uint256 ethFee = (p.eth + msg.value) * tokenFee / (p.token - tokenAmount);

        //uint256 origPrice = (p.ethTotal * p.token / p.eth) + p.tokenTotal;
        //uint256 currPrice = 2 * p.token;

        //console.log("origPrice", origPrice);
        //console.log("currPrice", currPrice);



        p.eth += msg.value;
        p.token -= tokenAmount;

        p.eth -= ethFee;
        p.token -= tokenFee;

        ////do the transfer, ETH transfer already happened
        SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, tokenAmount + tokenFee);
        emit SwapToToken(_tokenAddress, tokenAmount, msg.value);
    }

    /*function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }*/
}

