const hre = require("hardhat");
const {expect} = require("chai");
const {expectRevert, BN} = require("@openzeppelin/test-helpers");
const {web3} = require("@openzeppelin/test-helpers/src/setup");
const bnChai = require('bn-chai');
const chai = require('chai');
chai.use(bnChai(BN));

let SE20 = undefined;
let LP = undefined;
let SWAP = undefined;

let token = undefined;
let lp = undefined;
let swap = undefined;
let accounts = undefined;

const ONE_E18 = new BN("1000000000000000000");
const OFI_E18 = new BN("1500000000000000000");
const TWO_E18 = new BN("2000000000000000000");
const FIV_E17 = new BN("500000000000000000");
const SEV_E17 = new BN("700000000000000000");


//const ONE_E18 = new BN("1000");
//const OFI_E18 = new BN("1500");
//const TWO_E18 = new BN("2000");
//const SEV_E17 = new BN("700");
//const FIV_E17 = new BN("500");
//const TWO_E17 = new BN("200");

const FIV_E18 = new BN("5000000000000000000");
const FIV_E19 = new BN("50000000000000000000");
const ONE_E12 = new BN("1000000000000");
const FIV_E02 = new BN("500");
let nftNr = 0;

async function addLiquidity(tokenAmount, ethAmount, fromAccount) {
    //all our accounts have weis/eth, but only the first account has tokens
    if(fromAccount.address.toString() != accounts[0].address.toString()) {
        await token.connect(accounts[0]).transfer(fromAccount.address, tokenAmount.toString());
        await token.connect(fromAccount).approve(swap.address, tokenAmount.toString());
    }
    //we need to approve that the swap contract can transferFrom tokens
    await token.connect(fromAccount).approve(swap.address, tokenAmount.toString())
    await swap.connect(fromAccount).addLiquidity(token.address, tokenAmount.toString(), {value: ethAmount.toString()});

    const addr = new BN(web3.utils.hexToNumberString(token.address.toString()));
    const nftId = addr.shln(96).addn(nftNr++).toString();
    return nftId;
}

async function buyToken(requestedTokenAmount, fromAccount) {
    await poolInfo("Before swap: ");
    const tokenInfo = await swap.priceOfToken(token.address, requestedTokenAmount.toString());
    //const ethAmount = new BN(tokenInfo.ethAmount.toString()).add(new BN(tokenInfo.ethFee.toString())).toString();
    console.log("Buy TOK: to get the following amount of tokens:", requestedTokenAmount.toString());
    console.log("we need to spent the this amount eth:", tokenInfo.toString());

    const previousTokenBalance = await token.balanceOf(fromAccount.address);
    const previousWeiBalance = await fromAccount.getBalance();
    //events seem not to work in current hardhat setup
    await swap.connect(fromAccount).buyToken(token.address,
        new BN(requestedTokenAmount.toString()).sub(new BN(tokenInfo.toString())).toString(),
        0,
        {value: tokenInfo.toString()});
    const afterTokenBalance = await token.balanceOf(fromAccount.address);
    const afterWeiBalance = await fromAccount.getBalance();

    //test the swap
    const bn1 = new BN(afterTokenBalance.toString()).sub(new BN(previousTokenBalance.toString()));
    //expect(bn1.sub(new BN(requestedTokenAmount.toString()))).to.lte.BN("200"); //due to round up, we may see a higher token price than the actual ratio
    const bn2 = new BN(previousWeiBalance.sub(afterWeiBalance).toString());
    expect(bn2).to.eq.BN(new BN(tokenInfo.toString()));
    await poolInfo("After swap:  ");
    return tokenInfo;
}

async function sellToken(requestedEthAmount, fromAccount) {
    await poolInfo("Before swap: ");
    const tokenInfo = await swap.priceOfEth(token.address, requestedEthAmount.toString());
    const tokenAmount = new BN(tokenInfo.tokenAmount.toString()).add(new BN(tokenInfo.tokenFee.toString()));
    const ethAmount = new BN(requestedEthAmount.toString()).sub(new BN(tokenInfo.ethFee.toString()));
    console.log("Sell TOK: to get the following amount of eth:", ethAmount.toString(), "including fee of tok: ", tokenInfo.tokenFee.toString(), ", fee eth:", tokenInfo.ethFee.toString());
    console.log("we need to spent the this amount token:", tokenAmount.toString(), "at price: ", tokenAmount.div(ethAmount).toString(),"T/ETH");

    //events seem not to work in current hardhat setup
    await token.connect(accounts[0]).transfer(fromAccount.address, tokenAmount.toString());
    const previousTokenBalance = await token.balanceOf(fromAccount.address);
    const previousWeiBalance = await fromAccount.getBalance();
    await token.connect(fromAccount).approve(swap.address, tokenAmount.toString());
    await swap.connect(fromAccount).sellToken(token.address, tokenInfo.tokenAmount.toString(), tokenInfo.tokenFee.toString(), ethAmount.toString(), 0);
    const afterTokenBalance = await token.balanceOf(fromAccount.address);
    const afterWeiBalance = await fromAccount.getBalance();

    //test the swap
    const bn1 = new BN(previousTokenBalance.toString()).sub(new BN(afterTokenBalance.toString()));
    //expect(bn1).to.eq.BN(new BN(tokenAmount.toString()));
    const bn2 = new BN(afterWeiBalance.toString()).sub(new BN(previousWeiBalance.toString()));
    //expect(bn2.sub(new BN(requestedEthAmount.toString()))).to.lte.BN("20");
    await poolInfo("After swap:  ");
    return tokenAmount;
}

async function removeLiquidity(nftId, fromAccount) {
    await lp.removeLiquidity(fromAccount.address.toString(), nftId);
}

async function poolInfo(tag) {
    const poolInfo = await swap.poolInfo(token.address);
    const price = new BN(poolInfo.tokenAmount.toString()).div(new BN(poolInfo.ethAmount.toString()));
    console.log(tag, "TOK CUR:", poolInfo.tokenAmount.toString(), "ETH CUR:", poolInfo.ethAmount.toString(), "price: ", price.toString(), "T/Eth");
}

async function nftInfo(nftId) {
    const balance = await swap.balanceOf(nftId);
    const id = new BN(nftId.toString()).andln(255);
    const poolInfo = await swap.poolInfo(token.address);
    const price = new BN(poolInfo.tokenAmount.toString()).div(new BN(poolInfo.ethAmount.toString()));
    const nft = await lp.lpInfos(nftId);
    console.log("NFT Id:",id.toString(), "ETH:", balance.ethAmount.toString(), "TOK:", balance.tokenAmount.toString(), "price:", price.toString(), "T/Eth");
    console.log("NFT Id:",id.toString(), "total:", new BN(balance.ethAmount.toString()).mul(price).add(new BN(balance.tokenAmount.toString())).toString());
    console.log("NFT Id:",id.toString(), "HODL: ", new BN(nft.ethAmount.toString()).mul(price).add(new BN(nft.tokenAmount.toString())).toString());
}

async function poolTest(... nftIds) {
    let totalToken = new BN("0");
    let totalEth = new BN("0");
    for (let i = 0; i < nftIds.length; i++) {
        const balance = await swap.balanceOf(nftIds[i]);
        totalToken = totalToken.add(new BN(balance.tokenAmount.toString()));
        totalEth = totalEth.add(new BN(balance.ethAmount.toString()));
    }

    const poolInfo = await swap.poolInfo(token.address);
    expect(new BN(poolInfo.tokenAmount.toString()).sub(totalToken)).to.lte.BN("10000000");
    expect(new BN(poolInfo.ethAmount.toString()).sub(totalEth)).to.lte.BN("10000000");
    console.log("TOK CUR:", poolInfo.tokenAmount.toString(), "\tETH CUR:", poolInfo.ethAmount.toString());
}

describe("FondueSwap Test", function () {

    before("Setup TGT and FondueSwap Contracts", async function () {
        accounts = await hre.ethers.getSigners();
        SE20 = await ethers.getContractFactory("SomeERC20");
        LP = await ethers.getContractFactory("FondueLPNFT");
        SWAP = await ethers.getContractFactory("FondueSwap");
    });

    beforeEach("Setup TGT and FondueSwap Contracts", async function () {
        token = await SE20.deploy();
        lp = await LP.deploy();
        await lp.deployed();
        swap = await SWAP.deploy(lp.address);
        await swap.deployed();
        await token.deployed();
        await lp.setSwapAddress(swap.address);
        nftNr = 0;
    });

    it('Check Token', async function () {
        expect(await token.name()).to.equal("SomeERC20");
    });

    it('Test Impermanent Loss 4', async function () {
        //initially, the price is 200$/1ETH
        const mul = 1e3;
        const nftId1 = await addLiquidity(200 * mul, 1 * mul, accounts[0]);
        const nftId2 = await addLiquidity(2000 * mul, 10 * mul, accounts[1]);
        //now the price of ETH goes up to 300$/ETH
        //arbitrage 1.5ETH, get for 412 Dai at 297$/ETH
        //as soon as there is 1 wei profit, the arbitrage will happen, however, any blockchain fee is excluded
        await sellToken(5 * mul, accounts[6]);
        await sellToken(1 * mul, accounts[6]);
        await buyToken(393 * mul, accounts[7]);
        await buyToken(500 * mul, accounts[7]);
        await sellToken(1 * mul, accounts[6]);
        await buyToken(3000 * mul, accounts[7]);
        const nftId3 = await addLiquidity(100000 * mul, 10 * mul, accounts[1]);
        await sellToken(500, accounts[6]);

        await nftInfo(nftId1);
        await nftInfo(nftId2);
        await nftInfo(nftId3);
        await poolInfo();
    });

});
