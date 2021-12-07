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
    }
    uint256 private counter;
    address public swapAddress;
    address public owner;

    constructor() ERC721("FondueLPNFT", "FLPNFT") {
        owner = msg.sender;
    }
    function mint(address to, address _tokenAddress, uint256 _ethAmount, uint256 _tokenAmount) external returns (uint256) {
        require(msg.sender == swapAddress);
        uint256 nftId = ((uint256(uint160(_tokenAddress)) << 96) | counter);
        _mint(to, nftId);
        _lpInfos[nftId]= LPInfo(_ethAmount, _tokenAmount);
        counter++;
        return nftId;
    }
    function lpInfos(uint256 nftId) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        LPInfo memory lp = _lpInfos[nftId];
        return (lp.ethAmount, lp.tokenAmount);
    }
    function setSwapAddress(address newSwapAddress) external {
        require(msg.sender == owner);
        swapAddress = newSwapAddress;
    }
    function burn(uint256 nftId) external {
        require(msg.sender == swapAddress);
        _burn(nftId);
    }
    function updateLP(uint256 nftId, uint256 _ethAmount, uint256 _tokenAmount) external {
        require(msg.sender == swapAddress);
        _lpInfos[nftId]= LPInfo(_ethAmount, _tokenAmount);
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
        uint256 ethSafety;
        uint256 tokenSafety;
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
        uint256 nftId = FondueLPNFT(lpAddress).mint(msg.sender, _tokenAddress, msg.value, tokenAmount);
        emit AddLiquidity(_tokenAddress, tokenAmount, msg.value, nftId);
    }

    //remove liquidity
    function onTokenTransfer(address sender, uint256 nftId, bytes calldata) external {
        require(msg.sender == lpAddress, "not the LP NFT");
        (uint256 ethAmount, uint256 tokenAmount) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool storage p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 _ethAmount, uint256 _tokenAmount) = balanceOf(p, ethAmount, tokenAmount);
        p.eth -= _ethAmount;
        p.token -= _tokenAmount;
        p.ethTotal -= ethAmount;
        p.tokenTotal -= tokenAmount;
        payable(sender).transfer(ethAmount);
        SafeERC20.safeTransfer(IERC20(address(uint160(nftId >> 96))), sender, tokenAmount);
        FondueLPNFT(lpAddress).burn(nftId);
    }

    function harvest(uint256 nftId) external {
        //no harvest yet
    }

    function balanceOf(uint256 nftId) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        (uint256 ethAmount, uint256 tokenAmount) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool memory p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 _ethAmount, uint256 _tokenAmount) = balanceOf(p, ethAmount, tokenAmount);
        return (_ethAmount, _tokenAmount);
    }

    function balanceOf(Pool memory p, uint256 _ethAmount, uint256 _tokenAmount) internal view returns (uint256 ethAmount, uint256 tokenAmount) {
        uint256 price = (_ethAmount * p.token / p.eth) + _tokenAmount;
        ethAmount = price / (2*(p.token / p.eth));
        tokenAmount = ethAmount * p.token / p.eth;
        return (ethAmount, tokenAmount);
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

        uint256 origPrice = (p.ethTotal * (p.token + tokenAmount) / (p.eth - _ethAmount)) + p.tokenTotal;
        uint256 currPrice = 2 * (p.token + tokenAmount);
        uint256 loss = origPrice - currPrice;
        tokenFee = (origPrice - currPrice) / 2;
        ethFee = (p.eth - _ethAmount) * tokenFee / (p.token + tokenAmount);

        if(p.ethSafety >= ethFee) {
            ethFee = 0; //covered by the safety net
        } else {
            ethFee -= p.ethSafety;
        }

        if(p.tokenSafety >= tokenFee) {
            tokenFee = 0; //covered by the safety net
        } else {
            tokenFee -= p.tokenSafety;
        }

        //if we decrease the price of the token, we need to pay 1% of the difference into the safety net
        uint256 eF = (_ethAmount * (tokenAmount / _ethAmount) / (p.token/p.eth)) / 100;
        uint256 tF = (tokenAmount *(p.token/p.eth)  / (tokenAmount / _ethAmount)) / 100;
        //console.log(" (p.token/p.eth)",  (p.token/p.eth));
        //console.log(" (tokenAmount / _ethAmount)",  (tokenAmount / _ethAmount));
        //console.log(" (tokenAmount / _ethAmount) / (p.token/p.eth)",  (tokenAmount / _ethAmount) / (p.token/p.eth));
        //console.log("tF", tF);
        //console.log("eF", eF);

        return (tokenAmount, tF + tokenFee, eF + ethFee);
    }

    function sellToken(address _tokenAddress, uint256 _tokenAmount, uint256 _tokenFee, uint256 _minEthAmount, uint96 _deadline) public payable {
        //deadline of 0, means no deadline
        require(_deadline == 0 || _deadline > block.timestamp, "tx too old");
        require(_tokenAmount > 0, "tokenAmount must be positive");
        require(IERC20(_tokenAddress).allowance(msg.sender, address(this)) >= _tokenAmount, "token no allowance");
        Pool storage p = _pools[_tokenAddress];
        require(p.token > 0 && p.eth > 0, "pool cannot be empty");

        uint256 ethAmount = (_tokenAmount * p.eth) / (p.token + (2 * _tokenAmount));
        require(ethAmount > 0, "eth must be positive");
        require(_minEthAmount <= ethAmount, "min eth not reached");

        //now we need to "donate" liquidity to not have any impermanent loss
        //uint256 origPrice = (p.ethTotal * (p.token + _tokenAmount) / (p.eth - ethAmount)) + p.tokenTotal;
        //uint256 currPrice = 2 * (p.token + _tokenAmount);
        //console.log("origPrice", origPrice);
        //console.log("currPrice", currPrice);
        //uint256 loss = origPrice - currPrice;

        uint256 tokenFee = (((p.ethTotal * (p.token + _tokenAmount) / (p.eth - ethAmount)) + p.tokenTotal) - (2 * (p.token + _tokenAmount))) / 2;
        uint256 ethFee = (p.eth - ethAmount) * tokenFee / (p.token + _tokenAmount);
        uint256 eF = (ethAmount * (_tokenAmount / ethAmount) / (p.token/p.eth)) / 100;
        uint256 tF = (_tokenAmount * (p.token/p.eth) / (_tokenAmount / ethAmount)) / 100;
        p.tokenSafety += tF;
        p.ethSafety += eF;

        p.eth -= ethAmount;
        p.token += _tokenAmount;

        p.eth += ethFee;
        if(p.ethSafety >= ethFee) {
            p.ethSafety -= ethFee;
            ethFee = 0; //covered by the safety net
        }
        else {
            ethFee -= p.ethSafety; //partially covered by the safety net
            p.ethSafety = 0;
        }

        p.token += tokenFee;
        if(p.tokenSafety >= tokenFee) {
            p.tokenSafety -= tokenFee;
            tokenFee = 0; //covered by the safety net
        } else {
            tokenFee -= p.tokenSafety; //partially covered by the safety net
            p.tokenSafety = 0;
        }

        //do the transfer
        require(_minEthAmount <= ethAmount - (ethFee + eF), "min eth not reached");
        payable(msg.sender).transfer(ethAmount - (ethFee + eF));
        require(tokenFee + tF <= _tokenFee);
        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), _tokenAmount + tokenFee + tF);
        emit SwapToEth(_tokenAddress, _tokenAmount, ethAmount);
    }

    function priceOfToken(address _tokenAddress, uint256 _tokenAmount) external view returns (uint256 ethAmount) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return 0;
        }
        require(p.token > (2 * _tokenAmount) + 1, "token amount too high");
        ethAmount = ((_tokenAmount * p.eth) - 1) / (p.token - (2 * _tokenAmount)) + 1;
        return ethAmount;
    }

    function buyToken(address _tokenAddress, uint256 _minTokenAmount, uint96 _deadline) public payable {
        //deadline of 0, means no deadline
        require(_deadline == 0 || _deadline > block.timestamp, "tx too old");
        require(msg.value > 0, "eth must be positive");
        Pool storage p = _pools[_tokenAddress];
        require(p.token > 0 && p.eth > 0, "pool cannot be empty");

        uint256 tokenAmount = (msg.value * p.token) / (p.eth + (2 * msg.value));
        require(tokenAmount > 0, "tokenAmount must be positive");
        require(_minTokenAmount <= tokenAmount, "min token not reached");

        //now we need to withdraw liquidity to not have any impermanent gain
        //the liquidity will be added to the safety net, which can be used
        //in case of impermanent loss.

        uint256 origPrice = (p.ethTotal * (p.token - tokenAmount) / (p.eth + msg.value)) + p.tokenTotal;
        uint256 currPrice = 2 * (p.token - tokenAmount);
        uint256 gain = currPrice - origPrice;
        uint256 tokenFee = gain / 2;
        uint256 ethFee = (p.eth + msg.value) * tokenFee / (p.token - tokenAmount);

        //alternative ethFee calculation
        //uint256 ethFee = p.eth + msg.value - p.ethTotal/2 - (p.tokenTotal * p.eth)/(p.token*2) - (p.tokenTotal* msg.value)/p.token;
        //uint256 tokenFee = ((2 * (p.token - ((msg.value * p.token) / (p.eth + (2 * msg.value))))) - ((p.ethTotal * (p.token - ((msg.value * p.token) / (p.eth + (2 * msg.value)))) / (p.eth + msg.value)) + p.tokenTotal)) / 2;
        //uint256 tokenFee = (p.token - tokenAmount) * ethFee /  (p.eth + msg.value);

        p.eth += msg.value;
        p.token -= tokenAmount;

        p.eth -= ethFee;
        p.token -= tokenFee;

        //add to the safety net
        p.ethSafety += ethFee;
        p.tokenSafety += tokenFee;

        ////do the transfer, ETH transfer already happened
        SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, tokenAmount);
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

