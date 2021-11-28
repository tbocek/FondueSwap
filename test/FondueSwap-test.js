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

async function swapToToken(requestedTokenAmount, fromAccount) {
    await poolInfo();
    const ethAmount = await swap.priceOfToken(token.address, requestedTokenAmount.toString());

    console.log("to get the following amount of tokens: ", requestedTokenAmount.toString());
    console.log("we need to spent the this amount eth : ", ethAmount.toString());

    const previousTokenBalance = await token.balanceOf(fromAccount.address);
    const previousWeiBalance = await fromAccount.getBalance();
    //events seem not to work in current hardhat setup
    await swap.connect(fromAccount).swapToToken(token.address, requestedTokenAmount.toString(), 0, {value: ethAmount.toString()});
    const afterTokenBalance = await token.balanceOf(fromAccount.address);
    const afterWeiBalance = await fromAccount.getBalance();

    //test the swap
    const bn1 = new BN(afterTokenBalance.toString()).sub(new BN(previousTokenBalance.toString()));
    expect(bn1.sub(requestedTokenAmount)).to.lte.BN("20"); //due to round up, we may see a higher token price than the actual ratio
    const bn2 = new BN(previousWeiBalance.sub(afterWeiBalance).toString());
    expect(bn2).to.eq.BN(new BN(ethAmount.toString()));

    return ethAmount;
}

async function swapToEth(requestedEthAmount, fromAccount) {
    await poolInfo();
    const tokenAmount = await swap.priceOfEth(token.address, requestedEthAmount.toString());

    console.log("to get the following amount of eth:     ", requestedEthAmount.toString());
    console.log("we need to spent the this amount token: ", tokenAmount.toString());

    //events seem not to work in current hardhat setup
    await token.connect(accounts[0]).transfer(fromAccount.address, tokenAmount.toString());
    const previousTokenBalance = await token.balanceOf(fromAccount.address);
    const previousWeiBalance = await fromAccount.getBalance();
    await token.connect(fromAccount).approve(swap.address, tokenAmount.toString());
    await swap.connect(fromAccount).swapToEth(token.address, tokenAmount.toString(), requestedEthAmount.toString(), 0);
    const afterTokenBalance = await token.balanceOf(fromAccount.address);
    const afterWeiBalance = await fromAccount.getBalance();

    //test the swap
    const bn1 = new BN(previousTokenBalance.toString()).sub(new BN(afterTokenBalance.toString()));
    expect(bn1).to.eq.BN(new BN(tokenAmount.toString()));
    const bn2 = new BN(afterWeiBalance.sub(previousWeiBalance).toString());
    expect(bn2.sub(requestedEthAmount)).to.lte.BN("20");

    return tokenAmount;
}

async function removeLiquidity(nftId, fromAccount) {
    await lp.removeLiquidity(fromAccount.address.toString(), nftId);
}

async function poolInfo() {
    const poolInfo = await swap.poolInfo(token.address);
    console.log("TOK CUR:", poolInfo.tokenAmount.toString(), "\tETH CUR:", poolInfo.ethAmount.toString());
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

    it('Add Liquidity', async function () {
        const nftId = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);

        const info = await lp.lpInfos(nftId);
        expect(new BN(info.liquidity.toString())).to.eq.BN(TWO_E18.mul(ONE_E18));
        expect(new BN(info.poolAccWin.toString())).to.eq.BN("0");

        const balance = await swap.balanceOf(nftId);
        expect(new BN(balance.ethAmount.toString())).to.eq.BN(ONE_E18);
        expect(new BN(balance.tokenAmount.toString())).to.eq.BN(TWO_E18);

        const p1 = await swap.poolInfo(token.address);
        expect(new BN(p1.ethAmount.toString())).to.eq.BN(ONE_E18);
        expect(new BN(p1.tokenAmount.toString())).to.eq.BN(TWO_E18);
    });

    it('Large trade, Buy tokens, Sell Weis (resulting in balanced pool)', async function () {
        const nftId = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        const {tx, ethAmount} = await swapToToken(FIV_E17, accounts[1]);
        poolTest(nftId);
    });

    it('Small trade, Buy tokens, Sell Weis (not much impact)', async function () {
        const nftId = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        poolTest(nftId);
    });

    it('Large trade, Buy tokens, Sell Weis', async function () {
        const nftId = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);
        poolTest(nftId);
    });

    it('Large trade, Buy Wei, Sell Tokens', async function () {
        const nftId = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);
        await swapToEth(FIV_E17, accounts[4]);
        poolTest(nftId);
    });

    it('Large trade, Buy Wei, Sell Tokens', async function () {
        const nftId = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);
        await swapToEth(FIV_E17, accounts[4]);
        await swapToEth(ONE_E18, accounts[5]);
        poolTest(nftId);
    });

    it('Add Liquidity and Retrieve it', async function () {
        const nftId1 = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        const b1m = await swap.balanceOf(nftId1);
        const nftId2 = await addLiquidity(OFI_E18, OFI_E18, accounts[6]);

        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);

        await swapToEth(FIV_E17, accounts[4]);
        await swapToEth(ONE_E18, accounts[5]);

        const b1 = await swap.balanceOf(nftId1);
        const b2 = await swap.balanceOf(nftId2);

        await poolTest(nftId1, nftId2);
        console.log("Tok total:          ", b2.tokenAmount.add(b1.tokenAmount).toString());
        console.log("Eth total:          ", b1.ethAmount.add(b2.ethAmount).toString());
    });

    it('Add Liquidity and Retrieve it 2', async function () {
        const nftId1 = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        const nftId2 = await addLiquidity(OFI_E18, OFI_E18, accounts[6]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);
        const nftId3 = await addLiquidity(TWO_E18, TWO_E18, accounts[7]);
        await swapToEth(FIV_E17, accounts[4]);
        await swapToEth(ONE_E18, accounts[5]);

        const b1 = await swap.balanceOf(nftId1);
        const b2 = await swap.balanceOf(nftId2);
        const b3 = await swap.balanceOf(nftId3);

        await poolTest(nftId1, nftId2, nftId3);
        console.log("TOK ADD:", b2.tokenAmount.add(b1.tokenAmount).add(b3.tokenAmount).toString(), "\tETH ADD:", b1.ethAmount.add(b2.ethAmount).add(b3.ethAmount).toString());
    });

    it('Add Liquidity and Remove Liquidity', async function () {
        const nftId1 = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await poolTest(nftId1);
        await removeLiquidity(nftId1, accounts[0]);
        await poolTest();
    });

    it('Add Liquidity, Swap, and Remove Liquidity', async function () {
        const nftId1 = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await poolTest(nftId1);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);
        await swapToEth(FIV_E17, accounts[4]);
        await swapToEth(ONE_E18, accounts[5]);
        await removeLiquidity(nftId1, accounts[0]);
        await poolTest();
    });

    it('Add Liquidity, Swap, and Remove Liquidity 2', async function () {
        const nftId1 = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        const nftId2 = await addLiquidity(ONE_E18, ONE_E18, accounts[6]);
        await swapToToken(SEV_E17, accounts[3]);
        await swapToEth(FIV_E17, accounts[4]);
        await removeLiquidity(nftId1, accounts[0]);
        await swapToEth(FIV_E17, accounts[5]);
        await swapToToken(ONE_E12, accounts[5]);
        await poolTest(nftId1, nftId2);
        await removeLiquidity(nftId2, accounts[6]);
        await poolTest();
    });

    it('Add Liquidity, Swap, and Remove Liquidity 3', async function () {
        const nftId1 = await addLiquidity(TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        const nftId2 = await addLiquidity(ONE_E18, ONE_E18, accounts[6]);
        await swapToToken(SEV_E17, accounts[3]);
        await swapToEth(FIV_E17, accounts[4]);
        await removeLiquidity(nftId1, accounts[0]);
        await swapToEth(ONE_E12, accounts[5]);
        const nftId3 = await addLiquidity(ONE_E18, ONE_E18, accounts[9]);
        await swapToToken(FIV_E17, accounts[5]);
        await poolTest(nftId2, nftId3);
        await removeLiquidity(nftId2, accounts[6]);
        await swapToEth(FIV_E17, accounts[8]);
        await removeLiquidity(nftId3, accounts[9]);
        await poolTest();
    });

});