/**
 * Deploy ชุด Token Factory ทั้งก้อนขึ้น TPIX Chain
 *
 *   npx hardhat run scripts/deploy-token-factory.js --network tpix
 *
 * ต้องมี DEPLOYER_KEY ใน environment (ดู hardhat.config.js)
 *
 * ─────────────────────────────────────────────────────────────────────
 *  อ่านก่อน — เชนนี้รับได้แค่ถึง london
 * ─────────────────────────────────────────────────────────────────────
 *  TPIX Chain คือ Polygon Edge v0.9.0 ที่ fork สูงสุดคือ london
 *  ถ้าคอมไพล์ด้วย evmVersion เริ่มต้นของ solc (shanghai) จะได้ PUSH0 ติดมา
 *  แล้วเชนตอบ "opcode not found" ตอนส่ง tx — เงียบมาก ดูไม่ออกว่าพังเพราะอะไร
 *
 *  hardhat.config.js ตั้ง evmVersion: "london" ไว้แล้ว ห้ามแก้
 *  ก่อน deploy จริงให้รัน  node scripts/check-deployable.js  เพื่อยืนยันกับเชนก่อน
 * ─────────────────────────────────────────────────────────────────────
 *
 *  ลำดับ deploy (factory ต้องรู้จัก creator ก่อน จึงต้องมาทีหลัง):
 *    1. creator ของ ERC-20 ทั้ง 5 ตัว
 *    2. TPIXTokenFactoryV2(creator ทั้ง 5)
 *    3. creator ของ NFT ทั้ง 2 ตัว
 *    4. TPIXNFTFactory(creator ทั้ง 2)
 *
 *  หมายเหตุ: create*() ทุกตัวเป็น onlyOwner — เว็บใช้กระเป๋าเซิร์ฟเวอร์เป็นคนเรียก
 *  แล้วส่ง owner_ เป็นกระเป๋าของผู้ใช้ ตัวเหรียญจึงเป็นของผู้ใช้ตั้งแต่วินาทีแรก
 */
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { registerWithSite, printEnvFallback } = require("./lib/register-with-site");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");
const EIP170 = 24576;

/** deploy พร้อมเช็กขนาดโค้ดและยืนยันว่ามี bytecode อยู่บนเชนจริง */
async function deploy(name, args = []) {
    const Factory = await ethers.getContractFactory(name);

    const artifact = JSON.parse(
        fs.readFileSync(
            path.join(__dirname, "..", "artifacts", findArtifact(name)),
            "utf8"
        )
    );
    const runtimeSize = ((artifact.deployedBytecode || "0x").length - 2) / 2;
    if (runtimeSize > EIP170) {
        throw new Error(`${name} โค้ด ${runtimeSize} ไบต์ เกินลิมิต EIP-170 (${EIP170}) — deploy ไม่ขึ้นแน่นอน`);
    }

    const c = await Factory.deploy(...args);
    await c.waitForDeployment();
    const addr = await c.getAddress();

    // อย่าเชื่อแค่ receipt — ถามเชนว่ามีโค้ดอยู่จริงไหม
    const code = await ethers.provider.getCode(addr);
    if (code === "0x") {
        throw new Error(`${name}: eth_getCode คืน 0x — สัญญาไม่ได้ขึ้นเชนจริง`);
    }

    console.log(`      ${name.padEnd(24)} ${addr}  (${runtimeSize.toLocaleString()} ไบต์)`);
    return addr;
}

function findArtifact(name) {
    const roots = [
        `src/token-factory/creators/${name}.sol/${name}.json`,
        `src/token-factory/${name}.sol/${name}.json`,
    ];
    for (const r of roots) {
        if (fs.existsSync(path.join(__dirname, "..", "artifacts", r))) return r;
    }
    throw new Error(`หา artifact ของ ${name} ไม่เจอ — รัน npx hardhat compile ก่อน`);
}

async function main() {
    const [deployer] = await ethers.getSigners();
    if (!deployer) {
        throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน เช่น  export DEPLOYER_KEY=0x...");
    }

    const net = await ethers.provider.getNetwork();
    const balance = await ethers.provider.getBalance(deployer.address);

    console.log("─".repeat(72));
    console.log("network   :", network.name, "chainId", net.chainId.toString());
    console.log("deployer  :", deployer.address);
    console.log("balance   :", ethers.formatEther(balance), "TPIX");
    console.log("─".repeat(72));

    if (net.chainId !== 4289n && network.name !== "hardhat" && network.name !== "localhost") {
        throw new Error(`chainId ${net.chainId} ไม่ใช่ TPIX Chain (4289) — หยุดไว้ก่อน`);
    }

    console.log("\n[1/5] creator ของ ERC-20 ...");
    const erc20V2Creator = await deploy("ERC20V2Creator");
    const utilityCreator = await deploy("UtilityTokenCreator");
    const rewardCreator = await deploy("RewardTokenCreator");
    const governanceCreator = await deploy("GovernanceTokenCreator");
    const stablecoinCreator = await deploy("StablecoinTokenCreator");

    console.log("\n[2/5] TPIXTokenFactoryV2 ...");
    const tokenFactory = await deploy("TPIXTokenFactoryV2", [
        erc20V2Creator, utilityCreator, rewardCreator, governanceCreator, stablecoinCreator,
    ]);

    console.log("\n[3/5] creator ของ NFT ...");
    const erc721Creator = await deploy("FactoryERC721Creator");
    const collectionCreator = await deploy("NFTCollectionCreator");

    console.log("\n[4/5] TPIXNFTFactory ...");
    const nftFactory = await deploy("TPIXNFTFactory", [erc721Creator, collectionCreator]);

    // ── ผูก creator กับ factory ของมัน (CreatorAccess) ──
    // ไม่ผูก = ทุก create*() revert · ผูกได้ครั้งเดียวโดยกระเป๋าที่ deploy creator เท่านั้น
    console.log("\n[5/5] ผูก creator กับ factory ...");
    const bindings = [
        ["ERC20V2Creator", erc20V2Creator, tokenFactory],
        ["UtilityTokenCreator", utilityCreator, tokenFactory],
        ["RewardTokenCreator", rewardCreator, tokenFactory],
        ["GovernanceTokenCreator", governanceCreator, tokenFactory],
        ["StablecoinTokenCreator", stablecoinCreator, tokenFactory],
        ["FactoryERC721Creator", erc721Creator, nftFactory],
        ["NFTCollectionCreator", collectionCreator, nftFactory],
    ];
    for (const [name, creatorAddr, factoryAddr] of bindings) {
        const creator = await ethers.getContractAt(name, creatorAddr);
        if ((await creator.factory()) === ethers.ZeroAddress) {
            await (await creator.bindFactory(factoryAddr)).wait();
        }
        const bound = await creator.factory();
        if (bound.toLowerCase() !== factoryAddr.toLowerCase()) {
            throw new Error(`${name} ผูกกับ ${bound} ไม่ใช่ ${factoryAddr}`);
        }
        console.log(`      ${name.padEnd(24)} → ${factoryAddr}`);
    }

    // ── ซ้อมสร้างเหรียญจริง 1 ใบ เพื่อพิสูจน์ว่าทั้งสายทำงาน ──
    // deploy เฉย ๆ ไม่ได้แปลว่าสร้างเหรียญได้ ต้องลองเรียก create จริงถึงจะรู้
    // บนเชนจริงข้ามโดยปริยาย — เหรียญ SMOKE จะค้างอยู่ใน factory ตลอดไป ทดสอบจริงผ่านหน้าเว็บแทน
    const runSmoke = network.name === "hardhat" || network.name === "localhost" || process.env.SMOKE_TEST === "1";
    if (runSmoke) {
    console.log("\nซ้อมสร้างเหรียญทดสอบ 1 ใบ ...");
    const factory = await ethers.getContractAt("TPIXTokenFactoryV2", tokenFactory);
    const tx = await factory.createERC20V2(
        "Deploy Smoke Test", "SMOKE", 18, ethers.parseUnits("1000", 18), deployer.address,
        false, false, false, false, 0, false, 0, 0
    );
    const receipt = await tx.wait();
    const created = receipt.logs
        .map((l) => { try { return factory.interface.parseLog(l); } catch { return null; } })
        .find((l) => l && l.name === "TokenCreated");
    if (!created) throw new Error("สร้างเหรียญทดสอบแล้วไม่มี event TokenCreated — สายการสร้างพัง");

    const tokenAddr = created.args.tokenAddress;
    const tokenCode = await ethers.provider.getCode(tokenAddr);
    if (tokenCode === "0x") throw new Error("เหรียญทดสอบไม่มีโค้ดบนเชน");

    const token = await ethers.getContractAt("FactoryERC20V2", tokenAddr);
    console.log("      เหรียญทดสอบ :", tokenAddr);
    console.log("      symbol      :", await token.symbol());
    console.log("      supply      :", ethers.formatUnits(await token.totalSupply(), 18));
    console.log("      owner ถือ   :", ethers.formatUnits(await token.balanceOf(deployer.address), 18));
    } else {
        console.log("\n[ข้าม] ซ้อมสร้างเหรียญบนเชนจริง (ตั้ง SMOKE_TEST=1 ถ้าต้องการ)");
    }

    // ── ส่งต่อสิทธิ์สร้างเหรียญให้กระเป๋าผู้ดำเนินการของเว็บ ──
    // create*() เป็น onlyOwner และเว็บเซ็นด้วย DEPLOYER_PRIVATE_KEY ของเซิร์ฟเวอร์
    // owner ของ factory จึงต้องเป็นกระเป๋านั้น ไม่งั้นทุกคำขอสร้างเหรียญจะ revert
    // (Ownable ขั้นเดียว — ตรวจที่อยู่ให้ดี โอนผิดคือเสียสิทธิ์สร้างเหรียญถาวร แต่ไม่กระทบเหรียญที่มีอยู่)
    const operatorRaw = (process.env.FACTORY_OPERATOR || "").trim();
    let operator = null;
    if (operatorRaw) {
        if (!/^0x[0-9a-fA-F]{40}$/.test(operatorRaw)) throw new Error(`FACTORY_OPERATOR ไม่ใช่ที่อยู่: ${operatorRaw}`);
        operator = ethers.getAddress(operatorRaw.toLowerCase());
        console.log("\nโอนสิทธิ์ factory ให้กระเป๋าผู้ดำเนินการ", operator, "...");
        for (const [name, addr] of [["TPIXTokenFactoryV2", tokenFactory], ["TPIXNFTFactory", nftFactory]]) {
            const f = await ethers.getContractAt(name, addr);
            if ((await f.owner()).toLowerCase() !== operator.toLowerCase()) {
                await (await f.transferOwnership(operator)).wait();
            }
            const now = await f.owner();
            if (now.toLowerCase() !== operator.toLowerCase()) throw new Error(`${name} owner = ${now} ไม่ใช่ ${operator}`);
            console.log(`      ${name.padEnd(24)} owner → ${now}`);
        }
    } else {
        console.log("\n[ข้าม] ไม่ได้ตั้ง FACTORY_OPERATOR — owner ของ factory ยังเป็น", deployer.address);
        console.log("       เว็บจะสร้างเหรียญได้ก็ต่อเมื่อ DEPLOYER_PRIVATE_KEY บนเซิร์ฟเวอร์คือกระเป๋านี้");
    }

    const isDryRun = network.name === "hardhat" || network.name === "localhost";
    if (isDryRun) {
        console.log("\n[dry-run] เครือข่าย", network.name, "— ไม่เขียน deployed-contracts.json");
        console.log("\nซ้อมผ่านหมด พร้อม deploy จริงด้วย --network tpix");
        return;
    }

    // ── บันทึกลง registry ──
    const entries = [
        ["ERC20V2Creator", erc20V2Creator, "creators/ERC20V2Creator.sol"],
        ["UtilityTokenCreator", utilityCreator, "creators/UtilityTokenCreator.sol"],
        ["RewardTokenCreator", rewardCreator, "creators/RewardTokenCreator.sol"],
        ["GovernanceTokenCreator", governanceCreator, "creators/GovernanceTokenCreator.sol"],
        ["StablecoinTokenCreator", stablecoinCreator, "creators/StablecoinTokenCreator.sol"],
        ["TPIXTokenFactoryV2", tokenFactory, "TPIXTokenFactoryV2.sol"],
        ["FactoryERC721Creator", erc721Creator, "creators/FactoryERC721Creator.sol"],
        ["NFTCollectionCreator", collectionCreator, "creators/NFTCollectionCreator.sol"],
        ["TPIXNFTFactory", nftFactory, "TPIXNFTFactory.sol"],
    ].map(([name, address, src]) => ({
        name,
        category: "token-factory",
        address,
        sourceFile: `contracts/src/token-factory/${src}`,
        compilerVersion: "0.8.24",
        optimizer: { enabled: true, runs: 200 },
        evmVersion: "london",
        viaIR: true,
        verified: false,
        deployedAt: new Date().toISOString().slice(0, 10),
    }));

    const reg = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    reg.contracts = (reg.contracts || [])
        .filter((c) => !entries.some((e) => e.name === c.name))
        .concat(entries);
    reg.updated = new Date().toISOString().slice(0, 10);
    delete reg._contractsNote;
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + "\n");
    console.log("\nบันทึกลง deployed-contracts.json แล้ว");

    // ── ลงทะเบียนกับเว็บ (ContractRegistry) — ถ้าเครื่องนี้ไม่มีโทเคน จะพิมพ์บรรทัด .env ให้แทน ──
    const payload = { token_factory_v2: tokenFactory, nft_factory: nftFactory };
    const registered = await registerWithSite(payload);
    if (!registered) printEnvFallback(payload);

    console.log("\n=== TOKEN FACTORY DEPLOYED ===");
    console.log("TPIXTokenFactoryV2:", tokenFactory);
    console.log("TPIXNFTFactory    :", nftFactory);
    console.log("owner (operator)  :", operator || deployer.address);
}

main().catch((e) => {
    console.error("\ndeploy ล้มเหลว:", e.message);
    process.exitCode = 1;
});
