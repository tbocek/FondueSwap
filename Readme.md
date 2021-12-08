# Fondue Swap

This is a contract for a decentralized exchange (DEX). It is written from scratch, 
however, UniSwap, SushiSwap and other swaps were used as inspiration. Features of 
this DEX are: 

* **No impermanent loss**: This swap does not have impermanent loss or gain. The liquidity provider is not better off than HODLing its assets
* **Swap does not change price**: The formula (Yx/(X+2x)) is used (SushiSwap uses Yx/(X+x)), which leaves the swap with the same price as the trade.
* **Solidity based**: can be used on any Ethereum-based blockchain.

The main difference to other swaps is that this swap will not have impermanent loss for liquidity providers. 
If a token is bought, then the impermanent gain will be stored in a safety net. In case of a token sell, 
a fee of 1% from the price difference will be charged and stored in the safety net. Thus, the higher the price 
difference, the higher the fee. If a token is sold, then the impermanent loss is covered by the safety net, if 
the safety net is empty, the seller has to cover the impermanent loss. That means that 
a seller may need to sell tokens at a worse rate than the price of the pool to cover the impermanent loss.

This swap shifts the risk from liquidity providers to token traders, where in the worst case, a sell of tokens is at a 
much higher price, as it needs to cover the impermanent loss. Thus, buying tokens is always at the pool price, but selling 
a token not. If in such a case the seller does not want to sell at this price, the seller has to wait until more liquidity
is provided, which results in a smaller impermanent loss to cover, or another seller or buyer adds funds to the safety net.

Here is an example:

* Liquidity in the pool: 2.2m tokens, 11k eth 
* Sell token 1.1m tokens for 4.4k eth, trade at 2474 T/ETH
* Pool is now at price 2200 T/ETH (the above trade has higher price due to the safety net fee, with fee its 2200 T/ETH)
* The pool has now 13m tokens and 6k eth
* Sell token 6m token for 702eth, trade at 8635 T/ETH. now the safety net is empty. More selling will have a much higher price as the full impermanent loss has to be covered
* The pool is now at price 3300 T/ETH, with 19m tokens and 5.8k eth
* Buy tokens 400k for 125 eth at price 3164 T/ETH, filling the safety net again
* Buy tokens 500k for 168 eth at price 2992 T/ETH, filling the safety net again
* Pool has now 17.5 tokens and 5.8 eth
* Sell 7.7m tokens for 369 at price 20988 T/ETH. Since the safety net did not have many funds, the sell is at a very high price
* Pool is now at 4539 T/ETH, with 26m tokens and 5.7k eth

That means if you want to sell large amount of tokens, you have to pay up to 10x the price to cover the pool for an impermanent loss.

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
