/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require("@nomiclabs/hardhat-waffle");
const {task} = require("hardhat/config");

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

module.exports = {
    solidity: "0.8.10",
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
            blockGasLimit: 10000000,
            mining: {
                auto: true, // required to be able to run tests correctly
                interval: 0
            },
            gasPrice: 0, //no gas charged, this way its easier to track the ETH of the swap
            initialBaseFeePerGas: 0
        }
    }
};
