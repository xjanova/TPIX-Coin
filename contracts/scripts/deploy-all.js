/**
 * ติดตั้งสัญญาทั้งระบบขึ้น TPIX Chain ด้วยคำสั่งเดียว
 *
 *   export DEPLOYER_KEY=0x...
 *   npx hardhat run scripts/deploy-all.js --network tpix
 *
 * ทำให้ครบในรอบเดียว:
 *   1. ตรวจก่อนว่า bytecode ทุกตัว deploy ขึ้นเชนนี้ได้จริง (ด่าน PUSH0)
 *   2. deploy ValidatorKYC + NodeRegistryV2 แล้วผูกเข้าหากัน
 *   3. deploy ชุด Token Factory (creator 7 ตัว + factory 2 ตัว)
 *   4. deploy ชุด DEX (WTPIX + USDT_TPIX + Factory + Router) — ทุกเหรียญบนเชนเทรดได้
 *   5. เติมพูลรางวัลมาสเตอร์โหนด (ถ้าตั้ง FUND_REWARD_POOL ไว้)
 *   6. ซ้อมใช้งานจริง — สร้างเหรียญทดสอบ 1 ใบ
 *   7. บันทึกลง deployed-contracts.json
 *   8. **ลงทะเบียนที่อยู่กับเว็บให้เอง** → ไม่ต้อง ssh ไปแก้ .env แล้ว config:cache อีก
 *      (เว็บจะเปิดเชน 4289 เป็น live และสร้างคู่เทรดจากพูล DEX เองภายใน 1 นาที)
 *
 * ─────────────────────────────────────────────────────────────────────
 *  ตัวแปรที่ต้องตั้ง
 * ─────────────────────────────────────────────────────────────────────
 *   DEPLOYER_KEY              คีย์กระเป๋าที่ใช้ deploy (ต้องมีอยู่จริงบนเชน)
 *
 *   TPIX_SITE_URL             เช่น https://tpix.online   ← ตั้งคู่กันสองตัวนี้
 *   CONTRACT_REGISTRY_TOKEN   ค่าเดียวกับใน .env ของเว็บ   ← แล้วจะลงทะเบียนให้อัตโนมัติ
 *
 *   FUND_REWARD_POOL          จำนวน TPIX ที่จะเติมพูลรางวัล (ไม่ตั้ง = ข้าม)
 *   FEE_COLLECTOR             กระเป๋ารับส่วนแบ่งค่าธรรมเนียม DEX (แนะนำ = fee_collector_wallet ของเว็บ)
 *   LIQ_TPIX + LIQ_USDT       เติมพูล TPIX/USDT ตั้งราคาเปิด (ไม่ตั้ง = เติมทีหลังที่หน้า /liquidity)
 *   SKIP_TOKEN_FACTORY=1      ข้ามชุดสร้างเหรียญ
 *   SKIP_MASTERNODE=1         ข้ามชุดมาสเตอร์โหนด
 *   SKIP_DEX=1                ข้ามชุด DEX
 * ─────────────────────────────────────────────────────────────────────
 *
 * ⚠️ เชน TPIX รับได้แค่ถึง london — hardhat.config.js ตั้ง evmVersion "london" ไว้แล้ว
 *    ถ้าใครไปแก้เป็นค่าอื่น solc จะปล่อย PUSH0 ออกมาแล้ว deploy ไม่ขึ้นทั้งหมด
 *    (ขั้นที่ 1 ของสคริปต์นี้จะจับได้ก่อนเสียเวลา)
 */
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { registerWithSite: postToSite, printEnvFallback } = require("./lib/register-with-site");
const { deployDex, dexRegistryPayload, writeSiteConfigs } = require("./deploy-dex");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");
const EIP170 = 24576;

const DEPLOY_KYC = process.env.DEPLOY_KYC !== "0";
const SKIP_MASTERNODE = process.env.SKIP_MASTERNODE === "1";
const SKIP_TOKEN_FACTORY = process.env.SKIP_TOKEN_FACTORY === "1";
const SKIP_DEX = process.env.SKIP_DEX === "1";
const FUND_REWARD_POOL = process.env.FUND_REWARD_POOL || "";

const DEFAULT_CONSENT_TEXT =
    "TPIX Chain Validator KYC — I consent to the collection and processing of my " +
    "identity documents for validator eligibility verification under Thailand PDPA. " +
    "I may withdraw consent and request erasure at any time.";

const deployed = {};

// ═══════════════════════════════════════════════════════════════════
//  helper
// ═══════════════════════════════════════════════════════════════════

function artifactPathFor(name) {
    const roots = [
        `src/masternode/${name}.sol/${name}.json`,
        `src/token-factory/${name}.sol/${name}.json`,
        `src/token-factory/creators/${name}.sol/${name}.json`,
        `src/dex/amm/${name}.sol/${name}.json`,
        `src/sale/WTPIX_ERC20.sol/${name}.json`,
        `src/bridge/${name}.sol/${name}.json`,
    ];
    for (const r of roots) {
        const full = path.join(__dirname, "..", "artifacts", r);
        if (fs.existsSync(full)) return full;
    }
    throw new Error(`หา artifact ของ ${name} ไม่เจอ — รัน npx hardhat compile ก่อน`);
}

/** deploy พร้อมตรวจขนาดโค้ดและยืนยันว่ามี bytecode อยู่บนเชนจริง */
async function deploy(name, args = []) {
    const artifact = JSON.parse(fs.readFileSync(artifactPathFor(name), "utf8"));
    const runtimeSize = ((artifact.deployedBytecode || "0x").length - 2) / 2;
    if (runtimeSize > EIP170) {
        throw new Error(`${name} โค้ด ${runtimeSize} ไบต์ เกินลิมิต EIP-170 (${EIP170})`);
    }

    const Factory = await ethers.getContractFactory(name);
    const c = await Factory.deploy(...args);
    await c.waitForDeployment();
    const address = await c.getAddress();

    // อย่าเชื่อแค่ receipt — ถามเชนว่ามีโค้ดอยู่จริงไหม
    if ((await ethers.provider.getCode(address)) === "0x") {
        throw new Error(`${name}: eth_getCode คืน 0x — สัญญาไม่ได้ขึ้นเชนจริง`);
    }

    console.log(`      ${name.padEnd(24)} ${address}  (${runtimeSize.toLocaleString()} ไบต์)`);
    return { address, contract: c };
}

/**
 * ด่านแรก — bytecode ทุกตัวที่จะ deploy ต้องผ่านโอปโค้ดของเชนนี้
 * ถามเชนตรง ๆ ด้วย eth_estimateGas (อ่านอย่างเดียว) ดีกว่าไปตายกลางทาง
 */
async function preflight(names) {
    console.log("\n[0/5] ตรวจว่า bytecode ผ่านโอปโค้ดของเชนนี้ ...");

    const [signer] = await ethers.getSigners();
    let blocked = 0;

    for (const name of names) {
        const artifact = JSON.parse(fs.readFileSync(artifactPathFor(name), "utf8"));
        const ctor = (artifact.abi || []).find((x) => x.type === "constructor");
        if (ctor && ctor.inputs.length) continue; // ตัวมี constructor args ข้ามไป จะเจอตอน deploy จริงอยู่ดี

        try {
            await ethers.provider.estimateGas({ from: signer.address, data: artifact.bytecode });
        } catch (e) {
            const msg = e.shortMessage || e.message || "";
            if (/opcode not found|invalid opcode/i.test(msg)) {
                blocked++;
                console.log(`      ❌ ${name} — ${msg}`);
            }
            // error อื่น (gas/limit/ขนาด body) แปลว่าผ่านด่านโอปโค้ดแล้ว
        }
    }

    if (blocked > 0) {
        throw new Error(
            `มี ${blocked} สัญญาที่เชนนี้รันไม่ได้ — ตรวจว่า hardhat.config.js ยังตั้ง evmVersion "london" อยู่ไหม`
        );
    }
    console.log("      ผ่านหมด");
}

/** ลงทะเบียนที่อยู่กับเว็บ — ใช้ตัวเดียวกับ deploy-dex.js (scripts/lib/register-with-site.js) */
async function registerWithSite() {
    const payload = {};
    for (const key of [
        "masternode_registry", "validator_kyc", "token_factory_v2", "nft_factory",
        "wtpix", "usdt_tpix", "dex_factory", "dex_router",
    ]) {
        if (deployed[key]) payload[key] = deployed[key];
    }
    if (Object.keys(payload).length === 0) return false;
    return postToSite(payload);
}

function dexRegistryPayloadToConfig(a) {
    return { WTPIX: a.WTPIX, USDT: a.USDT, FACTORY: a.FACTORY, ROUTER: a.ROUTER };
}

function saveRegistry(entries) {
    const reg = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    reg.contracts = (reg.contracts || [])
        .filter((c) => !entries.some((e) => e.name === c.name))
        .concat(entries);
    reg.updated = new Date().toISOString().slice(0, 10);
    if (Array.isArray(reg.pending)) {
        reg.pending = reg.pending.filter((p) => p.name !== "NodeRegistry");
        if (reg.pending.length === 0) delete reg.pending;
    }
    delete reg._contractsNote;
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + "\n");
}

// ═══════════════════════════════════════════════════════════════════
//  main
// ═══════════════════════════════════════════════════════════════════

async function main() {
    const [deployer] = await ethers.getSigners();
    if (!deployer) {
        throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน เช่น  export DEPLOYER_KEY=0x...");
    }

    const net = await ethers.provider.getNetwork();
    const balance = await ethers.provider.getBalance(deployer.address);
    const isDryRun = network.name === "hardhat" || network.name === "localhost";

    console.log("─".repeat(72));
    console.log("network   :", network.name, "chainId", net.chainId.toString());
    console.log("deployer  :", deployer.address);
    console.log("balance   :", ethers.formatEther(balance), "TPIX");
    console.log("─".repeat(72));

    if (net.chainId !== 4289n && !isDryRun) {
        throw new Error(`chainId ${net.chainId} ไม่ใช่ TPIX Chain (4289) — หยุดไว้ก่อน`);
    }
    if (balance === 0n) {
        throw new Error("deployer ไม่มี TPIX เลย — เชนนี้ gas = 0 แต่บัญชีต้องมีอยู่จริง");
    }

    const preflightNames = [];
    if (!SKIP_MASTERNODE) preflightNames.push("NodeRegistryV2");
    if (!SKIP_TOKEN_FACTORY) {
        preflightNames.push(
            "ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator",
            "GovernanceTokenCreator", "StablecoinTokenCreator",
            "FactoryERC721Creator", "NFTCollectionCreator"
        );
    }
    if (!SKIP_DEX) preflightNames.push("WTPIX", "USDT_TPIX", "TPIXDEXPair");
    await preflight(preflightNames);

    const entries = [];
    const add = (name, address, sourceFile) => {
        entries.push({
            name,
            category: sourceFile.includes("masternode") ? "masternode"
                : sourceFile.includes("dex") ? "dex"
                : (sourceFile.includes("sale") || sourceFile.includes("bridge")) ? "dex-token"
                : "token-factory",
            address,
            sourceFile: `contracts/src/${sourceFile}`,
            compilerVersion: sourceFile.includes("token-factory") ? "0.8.24" : "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            evmVersion: "london",
            verified: false,
            deployedAt: new Date().toISOString().slice(0, 10),
        });
    };

    // ── มาสเตอร์โหนด ────────────────────────────────────────────────
    let registry = null;
    if (!SKIP_MASTERNODE) {
        console.log("\n[1/5] มาสเตอร์โหนด ...");

        let kycAddress = null;
        if (DEPLOY_KYC) {
            const consentText = process.env.KYC_CONSENT_TEXT || DEFAULT_CONSENT_TEXT;
            const consentHash = ethers.keccak256(ethers.toUtf8Bytes(consentText));
            const kyc = await deploy("ValidatorKYC", [consentHash]);
            kycAddress = kyc.address;
            deployed.validator_kyc = kycAddress;
            add("ValidatorKYC", kycAddress, "masternode/ValidatorKYC.sol");
        } else {
            console.log("      ข้าม ValidatorKYC — ชั้น Validator จะลงทะเบียนไม่ได้");
        }

        const reg = await deploy("NodeRegistryV2");
        registry = reg.contract;
        deployed.masternode_registry = reg.address;
        add("NodeRegistryV2", reg.address, "masternode/NodeRegistryV2.sol");

        if (kycAddress) {
            await (await registry.setKYCContract(kycAddress)).wait();
            console.log("      ผูก KYC เข้ากับ registry แล้ว");
        }
    }

    // ── ชุดสร้างเหรียญ ──────────────────────────────────────────────
    if (!SKIP_TOKEN_FACTORY) {
        console.log("\n[2/5] ชุดสร้างเหรียญ ...");

        const c = {};
        for (const n of [
            "ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator",
            "GovernanceTokenCreator", "StablecoinTokenCreator",
            "FactoryERC721Creator", "NFTCollectionCreator",
        ]) {
            c[n] = (await deploy(n)).address;
            add(n, c[n], `token-factory/creators/${n}.sol`);
        }

        const tokenFactory = await deploy("TPIXTokenFactoryV2", [
            c.ERC20V2Creator, c.UtilityTokenCreator, c.RewardTokenCreator,
            c.GovernanceTokenCreator, c.StablecoinTokenCreator,
        ]);
        deployed.token_factory_v2 = tokenFactory.address;
        add("TPIXTokenFactoryV2", tokenFactory.address, "token-factory/TPIXTokenFactoryV2.sol");

        const nftFactory = await deploy("TPIXNFTFactory", [
            c.FactoryERC721Creator, c.NFTCollectionCreator,
        ]);
        deployed.nft_factory = nftFactory.address;
        add("TPIXNFTFactory", nftFactory.address, "token-factory/TPIXNFTFactory.sol");

        // ── ซ้อมสร้างเหรียญจริง 1 ใบ ──
        // deploy สำเร็จไม่ได้แปลว่าสร้างเหรียญได้ ต้องลองเรียก create จริงถึงจะรู้
        console.log("\n[3/5] ซ้อมสร้างเหรียญทดสอบ ...");
        const tx = await tokenFactory.contract.createERC20V2(
            "Deploy Smoke Test", "SMOKE", 18, ethers.parseUnits("1000", 18), deployer.address,
            false, false, false, false, 0, false, 0, 0
        );
        const receipt = await tx.wait();
        const created = receipt.logs
            .map((l) => { try { return tokenFactory.contract.interface.parseLog(l); } catch { return null; } })
            .find((l) => l && l.name === "TokenCreated");
        if (!created) throw new Error("สร้างเหรียญทดสอบแล้วไม่มี event TokenCreated — สายการสร้างพัง");

        const token = await ethers.getContractAt("FactoryERC20V2", created.args.tokenAddress);
        console.log("      เหรียญทดสอบ :", created.args.tokenAddress, `(${await token.symbol()})`);
    }

    // ── ชุด DEX ────────────────────────────────────────────────────
    // เขียนลง deployed-contracts.json ผ่าน registry object ที่ deployDex upsert ให้ (แยกจาก entries)
    let dexAddresses = null;
    if (!SKIP_DEX) {
        console.log("\n[3b/5] TPIX DEX (WTPIX + USDT_TPIX + Factory + Router) ...");
        const reg = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
        dexAddresses = await deployDex({ deployer, registry: reg });
        deployed.wtpix = dexAddresses.WTPIX;
        deployed.usdt_tpix = dexAddresses.USDT;
        deployed.dex_factory = dexAddresses.FACTORY;
        deployed.dex_router = dexAddresses.ROUTER;
        if (!isDryRun) {
            reg.updated = new Date().toISOString().slice(0, 10);
            fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + "\n");
            writeSiteConfigs({
                chainId: 4289,
                rpc: "https://rpc.tpix.online",
                updated: new Date().toISOString(),
                ...dexRegistryPayloadToConfig(dexAddresses),
            });
        }
    }

    // ── เติมพูลรางวัล ───────────────────────────────────────────────
    console.log("\n[4/5] พูลรางวัลมาสเตอร์โหนด ...");
    if (registry && FUND_REWARD_POOL) {
        const amount = ethers.parseEther(String(FUND_REWARD_POOL));
        if (amount > balance) {
            throw new Error(
                `จะเติมพูล ${FUND_REWARD_POOL} TPIX แต่กระเป๋ามี ${ethers.formatEther(balance)} TPIX`
            );
        }
        await (await registry.fundRewardPool({ value: amount })).wait();
        const [, totalFunded] = await registry.rewardPoolStatus();
        console.log(`      เติมแล้ว ${ethers.formatEther(totalFunded)} TPIX`);
    } else if (registry) {
        console.log("      ข้าม — ไม่ได้ตั้ง FUND_REWARD_POOL");
        console.log("      ⚠️ พูลว่าง = ผู้ใช้เห็นรางวัลสะสมขึ้นแต่กดรับได้ 0");
        console.log("         เติมทีหลังได้ด้วย fundRewardPool() จากกระเป๋า Master Node Rewards");
    } else {
        console.log("      ข้าม (ไม่ได้ deploy มาสเตอร์โหนด)");
    }

    // ── บันทึก + ลงทะเบียนกับเว็บ ──────────────────────────────────
    console.log("\n[5/5] บันทึกผล ...");
    if (isDryRun) {
        console.log(`      [dry-run] เครือข่าย ${network.name} — ไม่เขียน deployed-contracts.json`);
    } else {
        saveRegistry(entries);
        console.log("      บันทึกลง deployed-contracts.json แล้ว");
    }

    const registered = await registerWithSite();

    // ── สรุป ────────────────────────────────────────────────────────
    console.log("\n" + "─".repeat(72));
    console.log("ที่อยู่สัญญา");
    console.log("─".repeat(72));
    for (const [k, v] of Object.entries(deployed)) {
        console.log(`  ${k.padEnd(22)} ${v}`);
    }

    if (!registered && !isDryRun) {
        printEnvFallback(deployed);
    }

    console.log("\n" + "─".repeat(72));
    if (isDryRun) {
        console.log("ซ้อมผ่านหมด พร้อม deploy จริงด้วย --network tpix");
    } else if (registered) {
        console.log("เสร็จแล้ว — หน้าเว็บเปิดใช้งานเองภายใน 5 นาที (แคชสถานะสัญญา)");
    } else {
        console.log("deploy เสร็จแล้ว เหลือใส่ที่อยู่ให้เว็บตามด้านบน");
    }
    console.log("─".repeat(72));
}

main().catch((e) => {
    console.error("\n❌ deploy ล้มเหลว:", e.message);
    process.exitCode = 1;
});
