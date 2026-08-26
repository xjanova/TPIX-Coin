require("@nomicfoundation/hardhat-ethers");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomicfoundation/hardhat-network-helpers");

const fs = require("fs");
const path = require("path");

/**
 * ⚠️ evmVersion ต้องเป็น "london" — ห้ามลบ ห้ามปล่อยให้ solc เลือกเอง
 *
 * เชน TPIX คือ Polygon Edge v0.9.0 ที่ genesis เปิด fork สูงสุดแค่ london
 * (infrastructure/genesis.json → params.forks ไม่มี shanghai/cancun เลย)
 * แต่ solc 0.8.20+ ตั้งค่าเริ่มต้นเป็น shanghai ซึ่งปล่อยโอปโค้ด PUSH0 (0x5f) ออกมา
 *
 * ยืนยันสดกับเชนจริง 2026-08-27 ด้วย eth_estimateGas (อ่านอย่างเดียว ไม่ต้องมีคีย์):
 *   data 0x5f5ff3   (มี PUSH0) → {"error":"opcode not found"}
 *   data 0x60006000f3 (ไม่มี)  → ผ่านด่านโอปโค้ด
 *
 * นี่คือเหตุผลที่ตลอด ~620k บล็อกไม่เคยมีสัญญาไหน deploy ขึ้นเชนนี้ได้เลยสักตัว
 * bytecode ที่คอมไพล์ไว้เดิมมี PUSH0 อยู่ข้างใน → ส่ง tx ไปกี่ครั้งก็ตายที่โอปโค้ด
 *
 * "paris" ให้ชุดโอปโค้ดเท่ากับ london (PREVRANDAO ใช้เลขโอปโค้ดเดียวกับ DIFFICULTY)
 * แต่เลือก "london" ให้ตรงกับ genesis ตรง ๆ จะได้ไม่ต้องมาเถียงกันทีหลัง
 */
const EVM_VERSION = "london";

const OPTIMIZER = { optimizer: { enabled: true, runs: 200 }, evmVersion: EVM_VERSION };

// token-factory ต้องใช้ viaIR — ตัว creator ฝัง bytecode ของ token เต็มก้อนไว้ข้างใน
// และ createUtilityToken/createGovernanceToken รับพารามิเตอร์ 14+ ตัว
// คอมไพล์แบบเดิมชน "Stack too deep" (รวมถึง OZ Bytes.sol ที่มันลากมาด้วย)
const OPTIMIZER_VIA_IR = { optimizer: { enabled: true, runs: 200 }, viaIR: true, evmVersion: EVM_VERSION };

/**
 * token-factory ใช้ pragma ^0.8.24 เพราะพึ่ง OZ ERC721 / Votes / EIP712 / Strings
 * ซึ่งใน OZ 5.6.1 เป็น ^0.8.24 ทั้งหมด
 *
 * ส่วนสัญญาที่เหลือ (masternode / dex / sale / bridge) ถูกเทสต์และตรวจมาบน 0.8.20 แล้ว
 * ถ้าปล่อยให้ hardhat เลือกคอมไพเลอร์เองโดยใส่ 0.8.24 ลงใน compilers[] มันจะหยิบตัวสูงสุด
 * ที่เข้ากับ pragma ^0.8.20 ได้ → bytecode ของสัญญาที่ตรวจไปแล้วขยับหมดโดยไม่มีใครสั่ง
 *
 * จึง pin เฉพาะไฟล์ใต้ src/token-factory ไว้ที่ 0.8.24 ผ่าน overrides
 * (สร้างรายการอัตโนมัติ เพิ่มไฟล์ใหม่แล้วไม่ต้องมาแก้ config ตาม)
 */
function tokenFactoryOverrides() {
  const root = path.join(__dirname, "src", "token-factory");
  const out = {};
  if (!fs.existsSync(root)) return out;

  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".sol")) {
        const rel = path.relative(__dirname, full).split(path.sep).join("/");
        out[rel] = { version: "0.8.24", settings: OPTIMIZER_VIA_IR };
      }
    }
  };
  walk(root);
  return out;
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      { version: "0.8.20", settings: OPTIMIZER },
      { version: "0.8.24", settings: OPTIMIZER },
    ],
    overrides: tokenFactoryOverrides(),
  },
  paths: {
    sources: "./src",      // consolidated source directory
    scripts: "./scripts",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  networks: {
    // เทสต์รันบน chainId เดียวกับของจริง เพื่อให้การเซ็น tx (EIP-155)
    // เหมือนกับตอน deploy จริง ไม่ใช่ 31337 ที่เป็นค่าเริ่มต้น
    hardhat: {
      chainId: 4289,
      // เชนจริงคิดค่าแก๊สเป็น 0 และบล็อกไม่มี baseFeePerGas เลย (ยืนยันสด: eth_gasPrice = 0x0)
      // ถ้าไม่ตั้งตรงนี้ โหนดทดสอบจะมี baseFee ของ EIP-1559 ขึ้นมาเอง
      // แล้ว tx ที่ส่ง gasPrice: 0 แบบเดียวกับของจริงจะถูกปฏิเสธ — เทสต์กับของจริงไม่ตรงกัน
      initialBaseFeePerGas: 0,
    },
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
