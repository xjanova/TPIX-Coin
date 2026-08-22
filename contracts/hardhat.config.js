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
      // rpc1 ไม่ใช่ rpc — rpc.tpix.online มี Cloudflare bot rule ครอบอยู่ ตอบ 403
      // ให้ client ที่ไม่มี User-Agent แบบเบราว์เซอร์ ซึ่งรวมถึง hardhat
      // (ดู masternode-ui/electron/rpc-client.js ที่ทดสอบไว้แล้ว)
      url: process.env.TPIX_RPC_URL || "https://rpc1.tpix.online",
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
