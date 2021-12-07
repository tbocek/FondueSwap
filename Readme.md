# Fondue Swap

This is a contract for a decentralized exchange (DEX). It is written from scratch, 
however, UniSwap, SushiSwap and other swaps were used as inspiration. Features of 
this DEX are: 

* **No impermanent loss**: This swap does not have impermanent loss or gain.
* **Swap does not change price**: The formula (Yx/(X+2x)) is used (SushiSwap uses Yx/(X+x)), which leaves the swap with the same price as the trade.
* **Solidity based**: can be used on any Ethereum-based blockchain.

The main difference is that this swap will not have impermanent loss. If a token is bought, then the impermanent gain will
be stored in a safety net. In case of a token sell, a fee of 1% from the price difference will be charged and stored in 
the safety net. Thus, the higher the price difference, the higher the fee. If a token is sold, then the impermanent loss
is covered by the safety net, if the safety net is empty, the seller has to cover the impermanent loss. That means that 
a seller may need to sell at a worse rate than the price of the pool.

Due to roundings, the added liquidity will not be fully recovered.

**Do not use this in production, this is a prototype and under testing**

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
