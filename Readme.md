# Fondue Swap

This is a contract for a decentralized exchange (DEX). It is written from scratch, 
however, UniSwap, SushiSwap and other swaps were used as inspiration. Features of 
this DEX are: 

* **No impermanent loss**: since a trade never leaves the pool in a worse state, there is no impermanent loss (to be verified)
* **Swap changes liquidity**: Since the formula (Yx/(X+2x)) is used (SushiSwap uses Yx/(X+x)), a swap also adds liquidity  
* **No fees charged**: A liquidity provider does not get fees (e.g., 3‰), but the added liquidity from a swap will be add proportionally to the liquidity providers
* **Solidity based**: can be used on any Ethereum-based blockchain

The main difference is that a swap will always increase liquidity in the pool, since the trader can only do a trade if the resulting pool has the same ratio as the trade. For an arbitrage trader, a trade only pays off if the exchange rate is higher/lower than with other swaps. If the market is at price 200$/ETH, the pool is at 190$/ETH, then optimal trade is somewhere between 190 < x < 200, depending on the pool depth. It never pays off to trade at 200$/ETH, although, the trader will get the most coins, but this will be at the market price, which is not interesting for an arbitrage trader.

Due to the formula this pool is expected to have a higher price fluctuation.

## Installation and Testing

To install and run the tests, use:
```
npm install
npx hardhat test
```
To run specific test files, use:
```
npx hardhat test test/FondueSwap-test.js
```