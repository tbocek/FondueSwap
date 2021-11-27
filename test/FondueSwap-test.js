const hre = require("hardhat");
const {expect} = require("chai");
const {expectRevert, BN} = require("@openzeppelin/test-helpers");
const {web3} = require("@openzeppelin/test-helpers/src/setup");


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
const FIV_E18 = new BN("5000000000000000000");
const FIV_E19 = new BN("50000000000000000000");
const SEV_E17 = new BN("700000000000000000");
const ONE_E12 = new BN("1000000000000");
const FIV_E02 = new BN("500");

async function addLiquidity(nftNr, tokenAmount, ethAmount, fromAccount) {
    //all our accounts have weis/eth, but only the first account has tokens
    if(fromAccount.address.toString() != accounts[0].address.toString()) {
        await token.connect(accounts[0]).transfer(fromAccount.address, tokenAmount.toString());
        await token.connect(fromAccount).approve(swap.address, tokenAmount.toString());
    }
    //we need to approve that the swap contract can transferFrom tokens
    await token.connect(fromAccount).approve(swap.address, tokenAmount.toString())
    const addr = new BN(web3.utils.hexToNumberString(token.address.toString()));
    const nftId = addr.shln(96).addn(nftNr).toString();
    await swap.connect(fromAccount).addLiquidity(token.address, tokenAmount.toString(), {value: ethAmount.toString()});
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

    expect(afterTokenBalance.sub(previousTokenBalance).toString()).to.eq(requestedTokenAmount.toString());
    expect(previousWeiBalance.sub(afterWeiBalance).toString()).to.eq(ethAmount.toString());
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

    expect(previousTokenBalance.sub(afterTokenBalance).sub(tokenAmount).toNumber()).to.lte(11);
    const bn = new BN(afterWeiBalance.sub(previousWeiBalance).toString());
    expect(bn.sub(requestedEthAmount).toNumber()).to.lte(11);
    return tokenAmount;
}

async function poolInfo() {
    const poolInfo = await swap.poolInfo(token.address);
    console.log("current pool token: ", poolInfo.tokenAmount.toString());
    console.log("current pool eth:   ", poolInfo.ethAmount.toString());
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
        await token.deployed();
        lp = await LP.deploy();
        await lp.deployed();
        swap = await SWAP.deploy(lp.address);
        await swap.deployed();
        await lp.setSwapAddress(swap.address);
    });

    /*it('Check Token', async function () {
        expect(await token.name()).to.equal("SomeERC20");
    });

    it('Add Liquidity', async function () {

        const nftId = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);

        const info = await lp.lpInfos(nftId);
        expect(info.liquidity.toString()).to.eq(TWO_E18.mul(ONE_E18).toString());
        expect(info.poolAccWin.toString()).to.eq("0");

        const balance = await swap.balanceOf(nftId);
        expect(balance.ethAmount.toString()).to.eq(ONE_E18.toString());
        expect(balance.tokenAmount.toString()).to.eq(TWO_E18.toString());

        const p1 = await swap.poolInfo(token.address);
        expect(p1.ethAmount.toString()).to.eq(ONE_E18.toString());
        expect(p1.tokenAmount.toString()).to.eq(TWO_E18.toString());

    });

    it('Large trade, Buy tokens, Sell Weis (resulting in balanced pool)', async function () {
        const nftId = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);
        const {tx, ethAmount} = await swapToToken(FIV_E17, accounts[1]);

        //check balances on swap contract
        const balanceNFT = await swap.balanceOf(nftId);
        const balancePool = await swap.poolInfo(token.address);

        //console.log("Pool eth:    ", balancePool.ethAmount.toString());
        //console.log("My liq eth:  ", balanceNFT.ethAmount.toString());
        //console.log("Pool token:  ", balancePool.tokenAmount.toString());
        //console.log("My liq token:", balanceNFT.tokenAmount.toString());

        //due to rounding, we expect it to be smaller
        expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(1500001);
        expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500000);

        //show price ratio
        //const rc = await tx.wait();
        //const event = tx.events.find(event => event.event === 'SwapToToken');
        //const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));
        //console.log("price ratio: ", priceRatio);
    });

    it('Small trade, Buy tokens, Sell Weis (not much impact)', async function () {

        const nftId = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);

        const balanceNFT = await swap.balanceOf(nftId);
        const balancePool = await swap.poolInfo(token.address);

        //console.log("Pool eth:    ", balancePool.ethAmount.toString());
        //console.log("My liq eth:  ", balanceNFT.ethAmount.toString());
        //console.log("Pool token:  ", balancePool.tokenAmount.toString());
        //console.log("My liq token:", balanceNFT.tokenAmount.toString());

        //due to rounding, we expect it to be smaller
        expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(1500001);
        expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500001);
    });

    it('Large trade, Buy tokens, Sell Weis', async function () {
        const nftId = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);

        const balanceNFT = await swap.balanceOf(nftId);
        const balancePool = await swap.poolInfo(token.address);

        //console.log("Pool eth:    ", balancePool.ethAmount.toString());
        //console.log("My liq eth:  ", balanceNFT.ethAmount.toString());
        //console.log("Pool token:  ", balancePool.tokenAmount.toString());
        //console.log("My liq token:", balanceNFT.tokenAmount.toString());

        //due to rounding, we expect it to be smaller
        expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(12000001);
        expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500001);
    });

    it('Large trade, Buy Wei, Sell Tokens', async function () {
        const nftId = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);

        await swapToEth(FIV_E17, accounts[4]);

        const balanceNFT = await swap.balanceOf(nftId);
        const balancePool = await swap.poolInfo(token.address);

        //due to rounding, we expect it to be smaller
        expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(12000001);
        expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500001);
    });

    it('Large trade, Buy Wei, Sell Tokens', async function () {
        const nftId = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        await swapToToken(FIV_E02, accounts[2]);
        await swapToToken(SEV_E17, accounts[3]);

        await swapToEth(FIV_E17, accounts[4]);
        await swapToEth(ONE_E18, accounts[5]);

        const balanceNFT = await swap.balanceOf(nftId);
        const balancePool = await swap.poolInfo(token.address);

        //due to rounding, we expect it to be smaller
        expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(12000001);
        expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500001);
    });*/


    it('Add Liquidity and Retrieve it', async function () {
        const nftId1 = await addLiquidity(0, TWO_E18, ONE_E18, accounts[0]);
        await swapToToken(FIV_E17, accounts[1]);
        const nftId2 = await addLiquidity(1, OFI_E18, OFI_E18, accounts[6]);

        //await swapToToken(FIV_E02, accounts[2]);
        //await swapToToken(SEV_E17, accounts[3]);

        //await swapToEth(FIV_E17, accounts[4]);
        //await swapToEth(ONE_E18, accounts[5]);

        const b1 = await swap.balanceOf(nftId1);
        const b2 = await swap.balanceOf(nftId2);

        await poolInfo();
        console.log("Tok total:          ", b2.tokenAmount.add(b1.tokenAmount).toString());
        console.log("Eth total:          ", b1.ethAmount.add(b2.ethAmount).toString());


    });

});