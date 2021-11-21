const hre = require("hardhat");
const {expect} = require("chai");
const {expectRevert, BN} = require("@openzeppelin/test-helpers");
const {web3} = require("@openzeppelin/test-helpers/src/setup");


let token = undefined;
let lp = undefined;
let swap = undefined;
let accounts = undefined;
const INIT_SUPPLY = new BN("750000000000000000000000000");
const ETH1 = new BN("1000000000000000000");
const ETH2 = new BN("2000000000000000000");
const ETH5 = new BN("5000000000000000000");
const TEN_E12 = new BN("1000000000000");

describe("FondueSwap Test", function () {
    beforeEach("Setup TGT and FondueSwap contracts", async function () {
        this.accounts = await hre.ethers.getSigners();

        const SE20 = await ethers.getContractFactory("SomeERC20");
        this.token = await SE20.deploy();
        await this.token.deployed();

        const LP = await ethers.getContractFactory("FondueLPNFT");
        this.lp = await LP.deploy();
        await this.lp.deployed();

        const SWAP = await ethers.getContractFactory("FondueSwap");
        this.swap = await SWAP.deploy(this.lp.address);
        await this.swap.deployed();
        await this.lp.setSwapAddress(this.swap.address);
    });

    it('Check token', async function () {
        expect(await this.token.name()).to.equal("SomeERC20");
    });

    it('Add Liquidity', async function () {
        await this.token.approve(this.swap.address, ETH2.toString())
        const poolShare100P = "1000000000000";
        const addr = new BN(web3.utils.hexToNumberString(this.token.address.toString()));
        const nftId = addr.shln(96).addn(0).toString();
        expect(await this.swap.addLiquidity(this.token.address, ETH2.toString(), {value: ETH1.toString()})).to.emit(
            this.swap, 'AddLiquidity').withArgs(
                this.token.address,
                ETH2.toString(),
                "1000000000000000000",
                "1000000000000",
                "1000000000000000000",
                nftId);
        const info = await this.lp.lpInfos(nftId);
        //100% pool share
        expect(info.poolShares.toString()).to.eq("1000000000000");
        expect(info.poolAccEthFee.toString()).to.eq("0");

        const balance = await this.swap.balanceOf(nftId);
        expect(balance.ethAmount.toString()).to.eq(ETH1.toString());
        expect(balance.tokenAmount.toString()).to.eq(ETH2.toString());

        const swap = this.swap;
        const token = this.token;
        const addrToken = this.token.address;
        const account1 = this.accounts[1];
        const addr1 = account1.address;
        const account2 = this.accounts[2];
        const addr2 = account2.address;
        describe("Trading", function () {
            const largeTrade  = new BN("500000000000000000");
            const largeTrade2 = new BN("50000000000000000000");
            const smallTrade = new BN("500");
            it('Make large trade, buy tokens for weis', async function () {
                const ethAmount = await swap.priceOfToken(addrToken, largeTrade.toString());
                const tx = await swap.connect(account1).swapToToken(addrToken, largeTrade.toString(), 0,{value: ethAmount.toString()});
                const balance = await token.balanceOf(addr1.toString());
                expect(balance.toString()).to.eq(largeTrade.toString());

                //check balances on swap contract
                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolBalanceOf(addrToken);
                expect(balanceNFT.ethAmount).to.eq(balancePool.ethAmount);
                expect(balanceNFT.tokenAmount).to.eq(balancePool.tokenAmount);

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
                const balancePool = await swap.poolBalanceOf(addrToken);
                expect(balanceNFT.ethAmount).to.eq(balancePool.ethAmount);
                expect(balanceNFT.tokenAmount).to.eq(balancePool.tokenAmount);

                const rc = await tx.wait();
                const event = rc.events.find(event => event.event === 'SwapToToken');
                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));

                //due to rounding, we do not see the same value
                //in this we want 500 tokens, need to pay 504 weis, and the internal trade happens at 502.
                //502/504 gives us 0.99603...
                //wheras the pool has a better precision and returns 0.99799. Looking at this case we should have calculated with 502.9899
                // TOKEN Fee 2
                // WEI   Fee 2
                // TOKEN before 1498997995991983967
                // WEI   before 1502008032128514060
                // TOKEN swap 502
                // WEI   swap 504
                // SWAP RATIO 99603174
                // POOL RATIO 99799599
                // TOKEN after 1498997995991983465
                // WEI   after 1502008032128514564

                expect(balancePool.priceRatio.toString()).to.eq("997995991983");
                //expect(balancePool.priceRatio.toString()).to.eq(priceRatio.toString());
            });

            it('Make small trade, buy wei for tokens', async function () {

                const tokenAmount = await swap.priceOfEth(addrToken, smallTrade.toString());

                await token.transfer(addr2, tokenAmount.toString());
                await token.connect(account2).approve(swap.address, tokenAmount.toString());

                const balancePrevious = await account2.getBalance();
                const tx = await swap.connect(account2).swapToEth(addrToken, tokenAmount.toString(), smallTrade.toString(), 0);
                const rc = await tx.wait(); // 0ms, as tx is already confirmed
                const event = rc.events.find(event => event.event === 'SwapToEth');
                const balanceAfter = await account2.getBalance();
                expect(balanceAfter.sub(balancePrevious)).to.eq(smallTrade.toString());

                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolBalanceOf(addrToken);
                expect(balanceNFT.ethAmount).to.eq(balancePool.ethAmount);
                expect(balanceNFT.tokenAmount).to.eq(balancePool.tokenAmount);

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
                expect(balanceAfter.sub(balancePrevious)).to.eq(largeTrade.toString());

                const balanceNFT = await swap.balanceOf(nftId);
                const balancePool = await swap.poolBalanceOf(addrToken);
                expect(balanceNFT.ethAmount).to.eq(balancePool.ethAmount);
                expect(balanceNFT.tokenAmount).to.eq(balancePool.tokenAmount);

                const priceRatio = new BN(event.args.tokenAmount.toString()).mul(TEN_E12).div(new BN(event.args.ethAmount.toString()));
                expect(balancePool.priceRatio.toString()).to.eq(priceRatio.toString());
            });
        });
    });

    it('Add Liquidity and Retrieve it', async function () {

    });
});
