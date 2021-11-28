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
        uint256 liquidity;
        uint256 poolAccWin;
    }
    uint256 private counter;
    address public swapAddress;
    address public owner;

    constructor() ERC721("FondueLPNFT", "FLPNFT") {
        owner = msg.sender;
    }
    function mint(address to, address _tokenAddress, uint256 _liquidity, uint256 _poolAccWin) external returns (uint256) {
        require(msg.sender == swapAddress);
        uint256 nftId = ((uint256(uint160(_tokenAddress)) << 96) | counter);
        _mint(to, nftId);
        _lpInfos[nftId]= LPInfo(_liquidity, _poolAccWin);
        counter++;
        return nftId;
    }
    function lpInfos(uint256 nftId) external view returns (uint256 liquidity, uint256 poolAccWin) {
        LPInfo memory lp = _lpInfos[nftId];
        return (lp.liquidity, lp.poolAccWin);
    }
    function setSwapAddress(address newSwapAddress) external {
        require(msg.sender == owner);
        swapAddress = newSwapAddress;
    }
    function burn(uint256 nftId) external {
        require(msg.sender == swapAddress);
        _burn(nftId);
    }
    function updateLP(uint256 nftId, uint256 _liquidity, uint256 _poolAccWin) external {
        require(msg.sender == swapAddress);
        _lpInfos[nftId]= LPInfo(_liquidity, _poolAccWin);
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
        uint256 liquidity;
        uint256 liquidityGain;
        uint256 accWin;
        uint256 roundingSwap;
    }

    address private lpAddress;
    uint256 private constant PRECISION = 1e12;

    constructor(address _lpAddress) {
        lpAddress = _lpAddress;
    }

    function flashLoan(address _tokenAddress, uint256 _maxTokenAmount) public payable {

    }

    function addLiquidity(address _tokenAddress, uint256 _maxTokenAmount) public payable {
        Pool storage p = _pools[_tokenAddress];

        uint256 tokenAmount = _maxTokenAmount;
        if (p.token > 0 || p.eth > 0) {
            tokenAmount = (msg.value * p.token) / p.eth;
            require(_maxTokenAmount >= tokenAmount, "max token reached");
        }
        require(msg.value > 0 || tokenAmount > 0, "no liquidity provided");

        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), tokenAmount);
        p.token += tokenAmount;
        p.eth += msg.value;
        p.liquidity += msg.value * tokenAmount;
        //hand out LP tokens
        uint256 nftId = FondueLPNFT(lpAddress).mint(msg.sender, _tokenAddress, msg.value * tokenAmount, p.accWin);
        emit AddLiquidity(_tokenAddress, tokenAmount, msg.value, nftId);
    }

    //remove liquidity
    function onTokenTransfer(address sender, uint256 nftId, bytes calldata) external {
        require(msg.sender == lpAddress, "not the LP NFT");
        (uint256 liquidity, uint256 poolAccWin) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool storage p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 ethAmount, uint256 ethAmountFee, uint256 tokenAmount, uint256 tokenAmountFee, uint256 liquidityGain) = balanceOf(p, liquidity, poolAccWin);
        p.eth -= (ethAmount + ethAmountFee);
        p.token -= (tokenAmount + tokenAmountFee);
        p.liquidityGain -= liquidityGain;
        p.liquidity -= liquidity;
        payable(sender).transfer(ethAmount + ethAmountFee);
        SafeERC20.safeTransfer(IERC20(address(uint160(nftId >> 96))), sender, tokenAmount + tokenAmountFee);
        FondueLPNFT(lpAddress).burn(nftId);
    }

    function harvest(uint256 nftId) external {
        address nftOwner = FondueLPNFT(lpAddress).ownerOf(nftId);
        require(nftOwner != address(0), "owner not found");
        (uint256 liquidity, uint256 poolAccWin) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool storage p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 ethAmount, uint256 ethAmountFee, uint256 tokenAmount, uint256 tokenAmountFee, uint256 liquidityGain) = balanceOf(p, liquidity, poolAccWin);
        p.eth -= ethAmountFee;
        p.token -= tokenAmountFee;
        p.liquidityGain -= liquidityGain;
        payable(nftOwner).transfer(ethAmountFee);
        SafeERC20.safeTransfer(IERC20(address(uint160(nftId >> 96))), nftOwner, tokenAmountFee);
        FondueLPNFT(lpAddress).updateLP(nftId, ethAmount * tokenAmount, p.accWin);
    }

    function balanceOf(uint256 nftId) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        (uint256 liquidity, uint256 poolAccWin) = FondueLPNFT(lpAddress).lpInfos(nftId);
        Pool memory p = _pools[address(uint160(nftId >> 96))]; // nftId >> 96 calculates the poolTokenAddress
        (uint256 _ethAmount, uint256 _ethAmountFee, uint256 _tokenAmount, uint256 _tokenAmountFee,) = balanceOf(p, liquidity, poolAccWin);
        return (_ethAmount + _ethAmountFee, _tokenAmount + _tokenAmountFee);
    }

    function balanceOf(Pool memory p, uint256 liquidity, uint256 poolAccWin) internal view returns (uint256 ethAmount, uint256 ethAmountFee, uint256 tokenAmount, uint256 tokenAmountFee, uint256 liquidityGain) {
        uint256 totalLiquidity = p.liquidity + p.liquidityGain;
        //rounding, pool will have more than 0 eth/token when all LP withdraw
        ethAmount = sqrt(liquidity) * p.eth / sqrt(totalLiquidity);
        tokenAmount = sqrt(liquidity) * p.token / sqrt(totalLiquidity);

        console.log("liquidity", liquidity);
        console.log("p.eth", p.eth);
        console.log("totalLiquidity", totalLiquidity);
        console.log("ethAmount", ethAmount);

        uint256 totalLiquidityGain = liquidity * (p.accWin - poolAccWin);
        //rounding, pool will have more than 0 eth/token when all LP withdraw
        liquidityGain = totalLiquidityGain / PRECISION;
        if(totalLiquidityGain > 0) {
            //rounding, pool will have more than 0 eth/token when all LP withdraw
            ethAmountFee = (sqrt(liquidityGain) * p.eth) / sqrt(totalLiquidity);
            tokenAmountFee = (sqrt(liquidityGain) * p.token) / sqrt(totalLiquidity);
        }
        return (ethAmount, ethAmountFee, tokenAmount, tokenAmountFee, liquidityGain);
    }

    function poolInfo(address poolTokenAddress) external view returns (uint256 ethAmount, uint256 tokenAmount) {
        Pool memory p = _pools[poolTokenAddress];
        return (p.eth, p.token);
    }

    //calculates how much tokens is needed to get _ethAmount out of this pool
    function priceOfEth(address _tokenAddress, uint256 _ethAmount) external view returns (uint256) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return 0;
        }
        require(p.eth > (2 * _ethAmount) + 1, "eth amount too high");
        return ((_ethAmount * p.token) - 1) / (p.eth - (2 * _ethAmount)) + 1;
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

        uint256 gain = (p.eth * p.token) - previousLiquidity;
        uint256 gainR = ((gain * PRECISION) + p.roundingSwap);
        p.roundingSwap = gainR % p.liquidity; //rounding goes to the next
        p.accWin += gainR / p.liquidity;
        p.liquidityGain += gain;

        //do the transfer
        payable(msg.sender).transfer(ethAmount);
        SafeERC20.safeTransferFrom(IERC20(_tokenAddress), msg.sender, address(this), _tokenAmount);
        emit SwapToEth(_tokenAddress, _tokenAmount, ethAmount);
    }

    function priceOfToken(address _tokenAddress, uint256 _tokenAmount) external view returns (uint256) {
        Pool memory p = _pools[_tokenAddress];
        if(p.token == 0 || p.eth == 0) {
            return 0;
        }
        require(p.token > (2 * _tokenAmount) + 1, "token amount too high");
        return ((_tokenAmount * p.eth) - 1) / (p.token - (2 * _tokenAmount)) + 1;
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

        uint256 previousLiquidity = p.eth * p.token;
        p.eth += msg.value;
        p.token -= tokenAmount;

        uint256 gain = (p.eth * p.token) - previousLiquidity;
        uint256 gainR = ((gain * PRECISION) + p.roundingSwap);
        p.roundingSwap = gainR % p.liquidity; //rounding goes to the next
        p.accWin += gainR / p.liquidity;
        p.liquidityGain += gain;

        ////do the transfer, ETH transfer already happened
        SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, tokenAmount);
        emit SwapToToken(_tokenAddress, tokenAmount, msg.value);
    }

    function sqrt(uint y) internal pure returns (uint z) {
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
    }
}

