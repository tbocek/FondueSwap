# Fondue Swap

This is a contract for a decentralized exchange (DEX). It is written from scratch, 
however, UniSwap, SushiSwap and other swaps were used as inspiration. Features of 
this DEX are: 

* **No impermanent loss**: since a trade never leaves the pool in a worse state, there is no impermanent loss
* **Solidity based**: can be used on any Ethereum-based blockchain



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