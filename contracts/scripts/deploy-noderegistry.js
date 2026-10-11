/**
 * Deploy NodeRegistryV2 (+ optional ValidatorKYC) to TPIX Chain.
 *
 *   แนะนำ: .\scripts\deploy-noderegistry.ps1   (ถามคีย์แบบซ่อน + ลงทะเบียนกับเว็บให้เอง)
 *   หรือ:   DEPLOY_KYC=1 npx hardhat run scripts/deploy-noderegistry.js --network tpix
 *   ซ้อม:   DEPLOY_KYC=1 npx hardhat run scripts/deploy-noderegistry.js          (hardhat network)
 *
 * Requires DEPLOYER_KEY in the environment (see hardhat.config.js).
 * Optional: TPIX_SITE_URL + CONTRACT_REGISTRY_TOKEN → registers the addresses
 * with the website (POST /api/infra/contracts) so /masternode, the desktop app
 * and TPIX Wallet pick the contract up without anyone editing .env.
 *
 * ─────────────────────────────────────────────────────────────────────
 *  READ THIS FIRST — this contract custodies real TPIX
 * ─────────────────────────────────────────────────────────────────────
 *  Deploying it does NOT fund it. The reward pool starts empty and the
 *  contract deliberately pays 0 rewards until someone sends TPIX to it
 *  via fundRewardPool(). That is the safe state: user stake principal is
 *  never spendable as rewards.
 *
 *  Fund it as a SEPARATE, deliberate transaction from the masternode-rewards
 *  allocation wallet with scripts/fund-reward-pool.ps1 — NOT with
 *  send-tpix.ps1: a plain 21,000-gas transfer runs out of gas in receive().
 *  Money sent to the pool can never be withdrawn by anyone (no such function),
 *  so fund in tranches.
 *
 *  The deploying wallet becomes the permanent owner: it can pause NEW
 *  registrations, set uptime, slash (capped at the % in force when a node
 *  registered), set APR caps / tier terms and approve Validator KYC. It can
 *  NOT withdraw anyone's stake or the reward pool.
 * ─────────────────────────────────────────────────────────────────────
 */
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { registerWithSite, printEnvFallback } = require("./lib/register-with-site");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");

// ตั้ง DEPLOY_KYC=1 ถ้าต้องการ deploy ValidatorKYC แล้วผูกเข้ากับ registry ด้วย
const DEPLOY_KYC = process.env.DEPLOY_KYC === "1";

// rpc1.tpix.online อยู่หลัง nginx ที่ตั้ง client_max_body_size 32k
// (TPIX-Coin/infrastructure/nginx-rpc.conf) — tx deploy ที่ใหญ่กว่านี้โดน 413 ก่อนถึงเชน
const RPC_BODY_LIMIT = 32 * 1024;

const TIER_NAMES = ["Guardian", "Sentinel", "Light", "Validator"];

// ข้อความยินยอม PDPA ที่ ValidatorKYC เก็บเป็น hash ไว้บนเชน
// ต้องตรงกับข้อความจริงที่ผู้สมัครกดยอมรับบนเว็บ ไม่งั้นพิสูจน์ย้อนหลังไม่ได้
const DEFAULT_CONSENT_TEXT =
    "TPIX Chain Validator KYC — I consent to the collection and processing of my " +
    "identity documents for validator eligibility verification under Thailand PDPA. " +
    "I may withdraw consent and request erasure at any time.";

/**
 * ประมาณขนาด body ของ eth_sendRawTransaction ก่อนส่งจริง
 * ถ้าเกินลิมิตของ proxy จะได้ 413 กลับมาแบบงง ๆ — บอกทางออกตั้งแต่ตอนนี้
 */
function assertFitsRpcBody(name, initcodeHex) {
    const initBytes = (initcodeHex.length - 2) / 2;
    // raw tx = initcode + ฟิลด์อื่น ~120 ไบต์ → hex ×2 + ห่อ JSON ~100 ไบต์
    const body = (initBytes + 120) * 2 + 2 + 100;
    const usingProxy = !/^https?:\/\/(127\.0\.0\.1|localhost)/.test(network.config.url || "");
    console.log(`      ${name}: initcode ${initBytes.toLocaleString()} ไบต์ → body ~${body.toLocaleString()} / ${RPC_BODY_LIMIT.toLocaleString()}`);
    if (usingProxy && body >= RPC_BODY_LIMIT) {
        throw new Error(
            `${name} ใหญ่เกินลิมิต body ของ RPC proxy — ส่งผ่าน ${network.config.url} ไม่ได้\n` +
            "  ทางออก: เปิด ssh tunnel ไปที่ RPC ภายในของเครื่องเชนแล้วรันใหม่ด้วย\n" +
            "    ssh -N -L 18545:127.0.0.1:<พอร์ต json-rpc ของ validator> <เครื่องเชน>\n" +
            "    TPIX_RPC_URL=http://127.0.0.1:18545"
        );
    }
}

async function main() {
    const [deployer] = await ethers.getSigners();
    if (!deployer) {
        throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน เช่น  export DEPLOYER_KEY=0x...");
    }

    const net = await ethers.provider.getNetwork();
    const balance = await ethers.provider.getBalance(deployer.address);
    const isDryRun = network.name === "hardhat" || network.name === "localhost";

    console.log("─".repeat(64));
    console.log("network   :", network.name, "chainId", net.chainId.toString());
    console.log("deployer  :", deployer.address, "  ← จะเป็นเจ้าของสัญญาถาวร");
    console.log("balance   :", ethers.formatEther(balance), "TPIX");
    console.log("─".repeat(64));

    if (net.chainId !== 4289n && !isDryRun) {
        throw new Error(`chainId ${net.chainId} ไม่ใช่ TPIX Chain (4289) — หยุดไว้ก่อน`);
    }
    if (balance === 0n) {
        throw new Error("deployer ไม่มี TPIX เลย — เติมค่าธรรมเนียมก่อน (เชนนี้ gas = 0 แต่ต้องมีบัญชีอยู่จริง)");
    }

    // ── ด่านขนาด tx (ตรวจก่อนเสียเวลาส่งอะไรขึ้นเชน) ──
    const Registry = await ethers.getContractFactory("NodeRegistryV2");
    const KYC = await ethers.getContractFactory("ValidatorKYC");
    console.log("\n[0/3] ตรวจขนาด tx เทียบลิมิต RPC proxy");
    assertFitsRpcBody("NodeRegistryV2", Registry.bytecode);
    if (DEPLOY_KYC) assertFitsRpcBody("ValidatorKYC", KYC.bytecode);

    // ── ValidatorKYC (ไม่บังคับ — ต้องมีถ้าจะเปิด tier Validator) ──
    let kycAddress = null;
    if (DEPLOY_KYC) {
        console.log("\n[1/3] deploy ValidatorKYC ...");
        // ValidatorKYC ผูก hash ของข้อความยินยอม PDPA ไว้ในสัญญา
        // ตั้ง KYC_CONSENT_TEXT ให้ตรงกับข้อความจริงที่ผู้สมัครเห็นบนเว็บ
        const consentText = process.env.KYC_CONSENT_TEXT || DEFAULT_CONSENT_TEXT;
        const consentHash = ethers.keccak256(ethers.toUtf8Bytes(consentText));
        console.log("      consent hash :", consentHash);
        console.log("      consent text :", consentText.slice(0, 60) + (consentText.length > 60 ? "..." : ""));
        const kyc = await KYC.deploy(consentHash);
        await kyc.waitForDeployment();
        kycAddress = await kyc.getAddress();
        console.log("      ValidatorKYC :", kycAddress);
    } else {
        console.log("\n[1/3] ข้าม ValidatorKYC (ตั้ง DEPLOY_KYC=1 ถ้าต้องการ)");
        console.log("      → tier Validator จะยังลงทะเบียนไม่ได้จนกว่าจะ setKYCContract()");
    }

    // ── NodeRegistryV2 ──
    console.log("\n[2/3] deploy NodeRegistryV2 ...");
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
    console.log("      eth_getCode    :", (code.length - 2) / 2, "ไบต์ ✓");

    // ── อ่านค่าจากเชนกลับมาโชว์ — ถ้าตรงนี้อ่านไม่ได้ เว็บก็อ่านไม่ได้ ──
    console.log("\n[3/3] ค่าบนเชนหลัง deploy");
    for (let t = 0; t < 4; t++) {
        const info = await registry.getTierInfo(t);
        const cap = await registry.tierAprCapBps(t);
        console.log(
            `      ${String(t)} ${TIER_NAMES[t].padEnd(9)} stake ${ethers.formatEther(info.minStake).padStart(12)} TPIX` +
            ` · ล็อก ${String(info.lockDays).padStart(3)} วัน · APR สูงสุด ${Number(cap) / 100}%` +
            ` · โควตา ${info.maxNodes === 0n ? "ไม่จำกัด" : info.maxNodes}`
        );
    }
    console.log("      หยุดรับสมัคร   :", await registry.registrationPaused());
    console.log("      owner          :", await registry.owner());

    const [funded, totalFunded, distributed, cap] = await registry.rewardPoolStatus();
    console.log("\nสถานะ reward pool ตอนนี้");
    console.log("  เงินจริงในพูล   :", ethers.formatEther(funded), "TPIX   ← ต้องเติมเอง (fund-reward-pool.ps1)");
    console.log("  เติมสะสม        :", ethers.formatEther(totalFunded), "TPIX");
    console.log("  จ่ายไปแล้ว      :", ethers.formatEther(distributed), "TPIX");
    console.log("  เพดานตามตาราง   :", ethers.formatEther(cap), "TPIX");

    if (isDryRun) {
        console.log("\n[dry-run] เครือข่าย", network.name, "— ไม่เขียน deployed-contracts.json และไม่ลงทะเบียนกับเว็บ");
        console.log("\nซ้อมผ่านหมด พร้อม deploy จริงด้วย --network tpix");
        return;
    }

    // ── บันทึกลง deployed-contracts.json ──
    const reg = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    const today = new Date().toISOString().slice(0, 10);
    const entries = [
        {
            name: "NodeRegistryV2",
            category: "masternode",
            address: registryAddress,
            sourceFile: "contracts/src/masternode/NodeRegistryV2.sol",
            compilerVersion: "0.8.24",   // hardhat เลือก solc สูงสุดที่เข้ากับ ^0.8.20 → 0.8.24 (ดู build-info)
            optimizer: { enabled: true, runs: 200 },
            evmVersion: "london",
            verified: false,
            deployedAt: today,
            owner: deployer.address,
            description: "Master node staking + reward distribution (APR-capped). Reward pool must be funded separately.",
        },
    ];
    if (kycAddress) {
        entries.push({
            name: "ValidatorKYC",
            category: "masternode",
            address: kycAddress,
            sourceFile: "contracts/src/masternode/ValidatorKYC.sol",
            compilerVersion: "0.8.24",   // hardhat เลือก solc สูงสุดที่เข้ากับ ^0.8.20 → 0.8.24 (ดู build-info)
            optimizer: { enabled: true, runs: 200 },
            evmVersion: "london",
            verified: false,
            deployedAt: today,
            owner: deployer.address,
            description: "KYC gate for the Validator tier of NodeRegistryV2",
        });
    }

    reg.contracts = (reg.contracts || []).filter(
        (c) => !entries.some((e) => e.name === c.name)
    ).concat(entries);
    reg.updated = today;
    // ช่อง pending ไม่จำเป็นอีกแล้วเมื่อ NodeRegistry ขึ้นเชนจริง
    if (Array.isArray(reg.pending)) {
        reg.pending = reg.pending.filter((p) => p.name !== "NodeRegistry" && p.name !== "NodeRegistryV2");
        if (reg.pending.length === 0) delete reg.pending;
    }
    delete reg._contractsNote;
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + "\n");
    console.log("\nบันทึกลง deployed-contracts.json แล้ว (commit ไฟล์นี้ด้วย)");

    // ── ลงทะเบียนกับเว็บ — /masternode, แอป PC และ TPIX Wallet อ่านที่อยู่จากตรงนี้ ──
    const payload = { masternode_registry: registryAddress };
    if (kycAddress) payload.validator_kyc = kycAddress;
    const registered = await registerWithSite(payload);
    if (!registered) printEnvFallback(payload);

    console.log("\n" + "─".repeat(64));
    console.log("ขั้นต่อไป");
    console.log("─".repeat(64));
    console.log("1. เติม reward pool จากกระเป๋า masternode-rewards (แยก tx — ห้ามใช้ send-tpix.ps1):");
    console.log(`     .\\scripts\\fund-reward-pool.ps1 -Amount <จำนวน TPIX> -Registry ${registryAddress}`);
    console.log(`2. ตรวจหน้าเว็บ: ${(process.env.TPIX_SITE_URL || "https://tpix.online").replace(/\/+$/, "")}/api/v1/masternode/config`);
    console.log("3. ยืนยันซอร์สบน explorer:  node scripts/verify-blockscout.js NodeRegistryV2" + (kycAddress ? " ValidatorKYC" : ""));
    console.log("─".repeat(64));
}

main().catch((e) => {
    console.error("\ndeploy ล้มเหลว:", e.message);
    process.exitCode = 1;
});
