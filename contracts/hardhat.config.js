require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomicfoundation/hardhat-network-helpers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  paths: {
    sources: "./src",      // consolidated source directory
    scripts: "./scripts",
    cache: "./cache",
    artifacts: "./artifacts",
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
