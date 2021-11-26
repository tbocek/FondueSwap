const hre = require("hardhat");
const {expect} = require("chai");
const {expectRevert, BN} = require("@openzeppelin/test-helpers");
const {web3} = require("@openzeppelin/test-helpers/src/setup");


let token = undefined;
let lp = undefined;
let swap = undefined;
let accounts = undefined;
const ONE_E18 = new BN("1000000000000000000");
const TWO_E18 = new BN("2000000000000000000");
const FIV_E17 = new BN("500000000000000000");
const FIV_E18 = new BN("5000000000000000000");
const FIV_E19 = new BN("50000000000000000000");
const SEV_E17 = new BN("700000000000000000");
const ONE_E12 = new BN("1000000000000");
const FIV_E02 = new BN("500");

async function addLiquidity(nftNr, tokenAmount, ethAmount, fromAccount) {
    await token.connect(fromAccount).approve(swap.address, tokenAmount.toString())
    const addr = new BN(web3.utils.hexToNumberString(token.address.toString()));
    const nftId = addr.shln(96).addn(nftNr).toString();
    expect(await swap.connect(fromAccount).addLiquidity(token.address, tokenAmount.toString(), {value: ethAmount.toString()})).to.emit(
        swap, 'AddLiquidity').withArgs(token.address, tokenAmount.toString(), ethAmount.toString(), nftId);
    return nftId;
}

async function swapToToken(requestedTokenAmount, fromAccount) {
    const ethAmount = await swap.priceOfToken(token.address, requestedTokenAmount.toString());
    console.log("to get the following amount of tokens: ", requestedTokenAmount.toString());
    console.log("we need to spent the this amount eth : ", ethAmount.toString());

    const previousTokenBalance = await token.balanceOf(fromAccount.toString());
    const previousWeiBalance = fromAccount.getBalance();
    const tx = await swap.connect(fromAccount).swapToToken(token.address, requestedTokenAmount.toString(), 0, {value: ethAmount.toString()});

    const afterTokenBalance = await token.balanceOf(fromAccount.toString());
    const afterWeiBalance = fromAccount.getBalance();

    expect(afterTokenBalance.sub(previousTokenBalance).toString()).to.eq(requestedTokenAmount.toString());
    expect(previousWeiBalance.sub(afterWeiBalance).toString()).to.eq(ethAmount.toString());

    return (ethAmount, tx);
}

describe("FondueSwap Test", function () {

    beforeEach("Setup TGT and FondueSwap contracts", async function () {
        accounts = await hre.ethers.getSigners();
        const SE20 = await ethers.getContractFactory("SomeERC20");
        token = await SE20.deploy();
        const LP = await ethers.getContractFactory("FondueLPNFT");
        lp = await LP.deploy();
        const SWAP = await ethers.getContractFactory("FondueSwap");
        swap = await SWAP.deploy(lp.address);
        await lp.setSwapAddress(swap.address);
    });

    it('Check token', async function () {
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

        describe("Trading", function () {

            it('Make large trade, buy tokens for weis', async function () {

                const balancePool1 = await swap.poolInfo(nftId);
                expect(balancePool1.ethAmount.toString()).to.eq(ONE_E18.toString());

                const {ethAmount,tx} = await swapToToken(FIV_E17, accounts[1]);


                //check balances on swap contract
                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolInfo(addrToken);

                console.log("the pool has eth:", balancePool.ethAmount.toString());
                console.log("the pool has tok:", balancePool.tokenAmount.toString());

                console.log("I have   has eth:", balanceNFT.ethAmount.toString());
                console.log("I have   has tok:", balanceNFT.tokenAmount.toString());

                //due to rounding, we expect it to be smaller
                expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(1500001);
                expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500000);

                //check price ratio
                const rc = await tx.wait();
                const event = rc.events.find(event => event.event === 'SwapToToken');
                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));
                expect(balancePool.priceRatio.toString()).to.eq(priceRatio.toString());
            });

            it('Make small trade, buy tokens for weis', async function () {
                const ethAmount = await swap.priceOfToken(addrToken, smallTrade.toString());
                const tx = await swap.connect(account1).swapToToken(addrToken, smallTrade.toString(), 0, {value: ethAmount.toString()});
                const balance = await token.balanceOf(addr1.toString());
                expect(balance.toString()).to.eq(smallTrade.add(largeTrade).toString());

                //check balances on swap contract
                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolInfo(addrToken);
                expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(1500001);
                expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1500001);

                const rc = await tx.wait();
                const event = rc.events.find(event => event.event === 'SwapToToken');
                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));

                expect(balancePool.priceRatio.toString()).to.eq("999999999999");
            });

            it('Make large trade1, buy tokens for weis', async function () {
                const ethAmount = await swap.priceOfToken(addrToken, largeTrade1.toString());
                console.log("to get the following amount of tokens: ", largeTrade1.toString());
                console.log("we need to spent the this amount eth : ", ethAmount.toString());
                const tx = await swap.connect(account2).swapToToken(addrToken, largeTrade1.toString(), 0,{value: ethAmount.toString()});
                const balance = await token.balanceOf(addr2.toString());
                expect(balance.toString()).to.eq(largeTrade1.toString());

                //check balances on swap contract
                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolInfo(addrToken);

                console.log("the pool has eth:", balancePool.ethAmount.toString());
                console.log("the pool has tok:", balancePool.tokenAmount.toString());

                console.log("I have   has eth:", balanceNFT.ethAmount.toString());
                console.log("I have   has tok:", balanceNFT.tokenAmount.toString());

                //due to rounding, we expect it to be smaller
                expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(12000001);
                expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1238480);

                //check price ratio
                const rc = await tx.wait();
                const event = rc.events.find(event => event.event === 'SwapToToken');
                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));
                expect(balancePool.priceRatio.toString()).to.eq(priceRatio.toString());
            });

            it('Make small trade, buy wei for tokens', async function () {
                const tokenAmount = await swap.priceOfEth(addrToken, smallTrade.toString());
                console.log("to get the following amount of eth: ", smallTrade.toString());
                console.log("we need to spent the this amount tokens : ", tokenAmount.toString());

                await token.transfer(addr2, tokenAmount.toString());
                await token.connect(account2).approve(swap.address, tokenAmount.toString());

                const balancePrevious = await account2.getBalance();
                const tx = await swap.connect(account2).swapToEth(addrToken, tokenAmount.toString(), smallTrade.toString(), 0);
                const rc = await tx.wait(); // 0ms, as tx is already confirmed
                const event = rc.events.find(event => event.event === 'SwapToEth');
                const balanceAfter = await account2.getBalance();
                //expect(balanceAfter.sub(balancePrevious)).to.eq(smallTrade.toString());

                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolInfo(addrToken);
                expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(12000001);
                expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1238480);

                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));
                //expect(balancePool.priceRatio.toString()).to.eq(priceRatio.toString());
            });

            it('Make super large trade, buy wei for tokens', async function () {

                const tokenAmount = await swap.priceOfEth(addrToken, largeTrade.toString());

                await token.transfer(addr2, tokenAmount.toString());
                await token.connect(account2).approve(swap.address, tokenAmount.toString());

                const balancePrevious = await account2.getBalance();
                const tx = await swap.connect(account2).swapToEth(addrToken, tokenAmount.toString(), largeTrade.toString(), 0);
                const rc = await tx.wait(); // 0ms, as tx is already confirmed
                const event = rc.events.find(event => event.event === 'SwapToEth');
                const balanceAfter = await account2.getBalance();
                //expect(balanceAfter.sub(balancePrevious)).to.eq(largeTrade.toString());

                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolInfo(addrToken);
                expect(balancePool.ethAmount.sub(balanceNFT.ethAmount).toNumber()).to.lte(12000001);
                expect(balancePool.tokenAmount.sub(balanceNFT.tokenAmount).toNumber()).to.lte(1238480);

                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));
                expect(balancePool.priceRatio.toString()).to.eq(priceRatio.toString());
            });
        });
    });

    it('Add Liquidity and Retrieve it', async function () {

    });
});
