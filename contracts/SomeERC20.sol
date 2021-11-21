// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SomeERC20 is ERC20 {
    constructor() ERC20("SomeERC20", "SE20") {
        //1mio supply to creator
        _mint(msg.sender, 1000000 * 10e18);
    }
}