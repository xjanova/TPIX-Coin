/**
 * Deploy NodeRegistryV2 (+ optional ValidatorKYC) to TPIX Chain.
 *
 *   npx hardhat run scripts/deploy-noderegistry.js --network tpix
 *
 * Requires DEPLOYER_KEY in the environment (see hardhat.config.js).
 *
 * ─────────────────────────────────────────────────────────────────────
 *  READ THIS FIRST — this contract custodies real TPIX
 * ─────────────────────────────────────────────────────────────────────
 *  Deploying it does NOT fund it. The reward pool starts empty and the
 *  contract deliberately pays 0 rewards until someone sends TPIX to it
 *  (fundRewardPool() or a plain transfer). That is the safe state: user
 *  stake principal is never spendable as rewards.
 *
 *  Fund it as a SEPARATE, deliberate transaction from the masternode
 *  reward allocation — not from this script — so the amount is a
 *  conscious decision and shows up as its own entry in the explorer.
 * ─────────────────────────────────────────────────────────────────────
 */
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");

// ตั้ง DEPLOY_KYC=1 ถ้าต้องการ deploy ValidatorKYC แล้วผูกเข้ากับ registry ด้วย
const DEPLOY_KYC = process.env.DEPLOY_KYC === "1";

// ข้อความยินยอม PDPA ที่ ValidatorKYC เก็บเป็น hash ไว้บนเชน
// ต้องตรงกับข้อความจริงที่ผู้สมัครกดยอมรับบนเว็บ ไม่งั้นพิสูจน์ย้อนหลังไม่ได้
const DEFAULT_CONSENT_TEXT =
    "TPIX Chain Validator KYC — I consent to the collection and processing of my " +
    "identity documents for validator eligibility verification under Thailand PDPA. " +
    "I may withdraw consent and request erasure at any time.";

async function main() {
    const [deployer] = await ethers.getSigners();
    if (!deployer) {
        throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน เช่น  export DEPLOYER_KEY=0x...");
    }

    const net = await ethers.provider.getNetwork();
    const balance = await ethers.provider.getBalance(deployer.address);

    console.log("─".repeat(64));
    console.log("network   :", network.name, "chainId", net.chainId.toString());
    console.log("deployer  :", deployer.address);
    console.log("balance   :", ethers.formatEther(balance), "TPIX");
    console.log("─".repeat(64));

    if (net.chainId !== 4289n && network.name !== "hardhat" && network.name !== "localhost") {
        throw new Error(`chainId ${net.chainId} ไม่ใช่ TPIX Chain (4289) — หยุดไว้ก่อน`);
    }
    if (balance === 0n) {
        throw new Error("deployer ไม่มี TPIX เลย — เติมค่าธรรมเนียมก่อน (เชนนี้ gas = 0 แต่ต้องมีบัญชีอยู่จริง)");
    }

    // ── ValidatorKYC (ไม่บังคับ — ต้องมีถ้าจะเปิด tier Validator) ──
    let kycAddress = null;
    if (DEPLOY_KYC) {
        console.log("\n[1/2] deploy ValidatorKYC ...");
        // ValidatorKYC ผูก hash ของข้อความยินยอม PDPA ไว้ในสัญญา
        // ตั้ง KYC_CONSENT_TEXT ให้ตรงกับข้อความจริงที่ผู้สมัครเห็นบนเว็บ
        const consentText = process.env.KYC_CONSENT_TEXT || DEFAULT_CONSENT_TEXT;
        const consentHash = ethers.keccak256(ethers.toUtf8Bytes(consentText));
        console.log("      consent hash :", consentHash);
        console.log("      consent text :", consentText.slice(0, 60) + (consentText.length > 60 ? "..." : ""));
        const KYC = await ethers.getContractFactory("ValidatorKYC");
        const kyc = await KYC.deploy(consentHash);
        await kyc.waitForDeployment();
        kycAddress = await kyc.getAddress();
        console.log("      ValidatorKYC :", kycAddress);
    } else {
        console.log("\n[1/2] ข้าม ValidatorKYC (ตั้ง DEPLOY_KYC=1 ถ้าต้องการ)");
        console.log("      → tier Validator จะยังลงทะเบียนไม่ได้จนกว่าจะ setKYCContract()");
    }

    // ── NodeRegistryV2 ──
    console.log("\n[2/2] deploy NodeRegistryV2 ...");
    const Registry = await ethers.getContractFactory("NodeRegistryV2");
    const registry = await Registry.deploy();
    await registry.waitForDeployment();
    const registryAddress = await registry.getAddress();
    console.log("      NodeRegistryV2 :", registryAddress);

    if (kycAddress) {
        const tx = await registry.setKYCContract(kycAddress);
        await tx.wait();
        console.log("      ผูก KYC เข้ากับ registry แล้ว");
    }

    // ── ยืนยันว่ามีโค้ดอยู่บนเชนจริง (อย่าเชื่อแค่ receipt) ──
    const code = await ethers.provider.getCode(registryAddress);
    if (code === "0x") {
        throw new Error("eth_getCode คืน 0x — สัญญาไม่ได้ขึ้นเชนจริง");
    }
    console.log("      eth_getCode    :", code.length, "ตัวอักษร ✓");

    // ── สถานะเริ่มต้น ──
    const [funded, totalFunded, distributed, cap] = await registry.rewardPoolStatus();
    console.log("\nสถานะ reward pool ตอนนี้");
    console.log("  เงินจริงในพูล   :", ethers.formatEther(funded), "TPIX   ← ต้องเติมเอง");
    console.log("  เติมสะสม        :", ethers.formatEther(totalFunded), "TPIX");
    console.log("  จ่ายไปแล้ว      :", ethers.formatEther(distributed), "TPIX");
    console.log("  เพดานตามตาราง   :", ethers.formatEther(cap), "TPIX");

    // ── บันทึกลง deployed-contracts.json (เฉพาะเชนจริง) ──
    const isDryRun = network.name === "hardhat" || network.name === "localhost";
    if (isDryRun) {
        console.log("\n[dry-run] เครือข่าย", network.name, "— ไม่เขียน deployed-contracts.json");
        console.log("\nซ้อมผ่านหมด พร้อม deploy จริงด้วย --network tpix");
        return;
    }

    const reg = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    const entries = [
        {
            name: "NodeRegistryV2",
            category: "masternode",
            address: registryAddress,
            sourceFile: "contracts/src/masternode/NodeRegistryV2.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            deployedAt: new Date().toISOString().slice(0, 10),
            description: "Master node staking + reward distribution. Reward pool must be funded separately.",
        },
    ];
    if (kycAddress) {
        entries.push({
            name: "ValidatorKYC",
            category: "masternode",
            address: kycAddress,
            sourceFile: "contracts/src/masternode/ValidatorKYC.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            deployedAt: new Date().toISOString().slice(0, 10),
            description: "KYC gate for the Validator tier of NodeRegistryV2",
        });
    }

    reg.contracts = (reg.contracts || []).filter(
        (c) => !entries.some((e) => e.name === c.name)
    ).concat(entries);
    reg.updated = new Date().toISOString().slice(0, 10);
    // ช่อง pending ไม่จำเป็นอีกแล้วเมื่อ NodeRegistry ขึ้นเชนจริง
    if (Array.isArray(reg.pending)) {
        reg.pending = reg.pending.filter((p) => p.name !== "NodeRegistry");
        if (reg.pending.length === 0) delete reg.pending;
    }
    delete reg._contractsNote;
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + "\n");
    console.log("\nบันทึกลง deployed-contracts.json แล้ว");

    console.log("\n" + "─".repeat(64));
    console.log("ขั้นต่อไป");
    console.log("─".repeat(64));
    console.log("1. เติม reward pool (แยก tx ต่างหาก จากกระเป๋า masternode allocation):");
    console.log(`     cast send ${registryAddress} "fundRewardPool()" --value <จำนวน> ...`);
    console.log("   หรือโอน TPIX เข้าแอดเดรสนี้ตรง ๆ ก็ได้");
    console.log("2. ใส่ลง .env ของ ThaiXTrade:");
    console.log(`     MASTERNODE_REGISTRY_ADDRESS=${registryAddress}`);
    console.log("3. ยืนยันซอร์สบน explorer:  npm run verify:sources");
    console.log("─".repeat(64));
}

main().catch((e) => {
    console.error("\ndeploy ล้มเหลว:", e.message);
    process.exitCode = 1;
});
