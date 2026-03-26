require("@nomicfoundation/hardhat-ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    tpix: {
      url: "https://rpc.tpix.online",
      chainId: 4289,
      gasPrice: 0,
      // Set deployer private key via environment variable:
      //   export DEPLOYER_KEY=0x...
      accounts: process.env.DEPLOYER_KEY ? [process.env.DEPLOYER_KEY] : [],
    },
    localhost: {
      url: "http://localhost:8545",
      chainId: 4289,
      gasPrice: 0,
    },
  },
};
