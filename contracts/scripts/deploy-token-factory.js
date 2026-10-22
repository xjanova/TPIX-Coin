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
const { ethers, network, artifacts } = require("hardhat");
const { registerWithSite, printEnvFallback } = require("./lib/register-with-site");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");
const EIP170 = 24576;
const IS_DRY_RUN = network.name === "hardhat" || network.name === "localhost";

/*
 * ── ส่งธุรกรรมเป็นจังหวะ ────────────────────────────────────────────────────
 * ด่าน njs หน้า rpc1 (infrastructure/njs/tpix-rpc.js) ให้ 10 ธุรกรรมต่อ IP และตัวนับ "ล้างเมื่อเงียบครบ 10 วินาที"
 * (js_shared_dict_zone timeout=10s) — ไม่ใช่หน้าต่างเลื่อน · ส่งต่อเนื่องใบละ ~2 วินาทีจึงชนที่ใบที่ 11
 * แล้ว hardhat ลองซ้ำทุก 5 วินาทีจนตัวนับไม่เคยล้าง (เกิดจริง 2026-10-22: ผูก creator ตัวที่ 2 ได้ 429 ค้าง)
 * → ทุก 8 ธุรกรรมพักเงียบ 12 วินาที
 */
const TX_PER_BURST = 8;
const QUIET_MS = 12_000;
let txSent = 0;
async function pace() {
    if (IS_DRY_RUN) return;
    if (txSent > 0 && txSent % TX_PER_BURST === 0) {
        console.log(`      … พัก ${QUIET_MS / 1000} วินาทีตามโควตาเขียนของ RPC`);
        await new Promise((r) => setTimeout(r, QUIET_MS));
    }
    txSent++;
}

/*
 * ── รันต่อจากรอบที่ค้างได้ ──────────────────────────────────────────────────
 * เดิมบันทึกที่อยู่ลง registry ตอนจบเท่านั้น → ล้มกลางทาง (เช่น 429) แล้วรันใหม่ = deploy ซ้ำทั้งชุด สัญญาเก่ากำพร้า
 * ตอนนี้จดที่อยู่ลงไฟล์ progress ทันทีหลัง deploy แต่ละตัว รอบหน้าใช้ของเดิมเฉพาะเมื่อผ่าน reuseCheck() ทุกข้อ
 * (โค้ดบนเชนตรง artifact · deployer ของ creator = กระเป๋านี้ · factory ชี้ creator ชุดเดียวกัน)
 * ไฟล์ถูกลบเมื่อจบครบ (registry เป็นที่บันทึกถาวร) · ตั้ง FRESH_DEPLOY=1 ถ้าตั้งใจ deploy ใหม่ทั้งชุด
 */
function progressPath(chainId) {
    return path.join(__dirname, "..", "deployments", `token-factory-${chainId}.progress.json`);
}
function loadProgress(chainId) {
    if (IS_DRY_RUN || process.env.FRESH_DEPLOY === "1") return {};
    try { return JSON.parse(fs.readFileSync(progressPath(chainId), "utf8")); } catch { return {}; }
}
function saveProgress(chainId, progress) {
    if (IS_DRY_RUN) return;
    fs.mkdirSync(path.dirname(progressPath(chainId)), { recursive: true });
    fs.writeFileSync(progressPath(chainId), JSON.stringify(progress, null, 2) + "\n");
}

/** runtime bytecode บนเชนต้องตรง artifact ทุกไบต์ (ยกเว้นช่อง immutable ที่ constructor เขียนลงโค้ด) */
async function codeMatches(name, addr) {
    const source = findArtifact(name).replace(/\/[^/]+\.json$/, "");
    const bi = await artifacts.getBuildInfo(`${source}:${name}`);
    const out = bi.output.contracts[source][name].evm.deployedBytecode;
    const mask = (hex) => {
        const b = Buffer.from(hex.replace(/^0x/, ""), "hex");
        for (const list of Object.values(out.immutableReferences || {})) for (const { start, length } of list) b.fill(0, start, start + length);
        return b;
    };
    return mask(await ethers.provider.getCode(addr)).equals(mask("0x" + out.object));
}

/** deploy พร้อมเช็กขนาดโค้ดและยืนยันว่ามี bytecode อยู่บนเชนจริง */
async function deploy(name, args = []) {
    await pace();
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

const ALL = [
    "ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator", "GovernanceTokenCreator", "StablecoinTokenCreator",
    "TPIXTokenFactoryV2", "FactoryERC721Creator", "NFTCollectionCreator", "TPIXNFTFactory",
];

/**
 * rpc1/rpc.tpix.online อยู่หลัง nginx ที่จำกัด request body ~32 KB
 * (ยืนยัน 2026-10-11: body 32,759 B ผ่าน · 34,159 B ได้ 413 Request Entity Too Large)
 * GovernanceTokenCreator มี initcode ~18.9 KB → eth_estimateGas ~38 KB → 413 หลัง deploy creator ไปแล้ว 3 ตัว
 * (ซ้อมผ่าน proxy จำกัด 32 KB: ได้ creator กำพร้า 3 ตัว ไม่มี factory)
 *
 * ถามก่อนด้วย request ขนาดเท่าตัวใหญ่สุด (eth_chainId + padding — อ่านอย่างเดียว) ถ้าโดน 413 หยุดก่อนส่งอะไรทั้งนั้น
 * ทางแก้: ขยาย client_max_body_size ของ nginx หน้า RPC (เช่น 128k) หรือ deploy ผ่าน SSH tunnel ตรงเข้าโหนด
 */
async function preflightBodySize() {
    if (network.name === "hardhat" || !network.config.url) return;
    const sizes = ALL.map((n) => {
        const a = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "artifacts", findArtifact(n)), "utf8"));
        return { n, bytes: (a.bytecode.length - 2) / 2 };
    });
    const big = sizes.reduce((a, b) => (b.bytes > a.bytes ? b : a));
    const need = big.bytes * 2 + 400;   // hex initcode + JSON/RLP ของ eth_estimateGas / eth_sendRawTransaction
    const body = JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [], pad: "0".repeat(need) });
    const res = await fetch(network.config.url, {
        method: "POST",
        headers: { "Content-Type": "application/json", "User-Agent": "Mozilla/5.0 (TPIX deploy preflight)" },
        body,
    });
    if (res.status === 413) {
        throw new Error(`RPC ${network.config.url} ปฏิเสธ request ${body.length.toLocaleString()} ไบต์ (413) — `
            + `${big.n} (initcode ${big.bytes.toLocaleString()} ไบต์) deploy ผ่าน RPC นี้ไม่ได้ · ยังไม่ได้ส่งอะไรขึ้นเชน\n`
            + "  ทางแก้: ขยาย client_max_body_size ของ nginx หน้า RPC (เช่น 128k) หรือใช้ TPIX_RPC_URL ที่ชี้ตรงเข้าโหนดผ่าน SSH tunnel");
    }
    console.log(`preflight : RPC รับ request ${body.length.toLocaleString()} ไบต์ได้ (ตัวใหญ่สุด ${big.n})`);
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
    await preflightBodySize();

    const progress = loadProgress(net.chainId);
    if (Object.keys(progress).length) {
        console.log(`\nพบรอบที่ค้าง (${path.relative(process.cwd(), progressPath(net.chainId))}) — ใช้ของเดิมเฉพาะตัวที่ตรวจบนเชนผ่าน`);
    }
    const same = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();
    const operatorEnv = (process.env.FACTORY_OPERATOR || "").trim().toLowerCase();

    /** creator: deployer ต้องเป็นกระเป๋านี้ (มีแต่ deployer ที่ bindFactory ได้) */
    const creatorCheck = async (addr) => {
        const c = new ethers.Contract(addr, ["function deployer() view returns (address)"], ethers.provider);
        return same(await c.deployer(), deployer.address) ? [] : [`deployer ของ creator ไม่ใช่ ${deployer.address}`];
    };
    /** factory: ต้องชี้ creator ชุดเดียวกับรอบนี้ และ owner เป็นกระเป๋านี้หรือผู้ดำเนินการ */
    const factoryCheck = (getters, expected) => async (addr) => {
        const abi = [...getters.map((g) => `function ${g}() view returns (address)`), "function owner() view returns (address)"];
        const f = new ethers.Contract(addr, abi, ethers.provider);
        const problems = [];
        for (let i = 0; i < getters.length; i++) {
            const got = await f[getters[i]]();
            if (!same(got, expected[i])) problems.push(`${getters[i]}() = ${got} ไม่ใช่ ${expected[i]}`);
        }
        const owner = await f.owner();
        if (!same(owner, deployer.address) && !(operatorEnv && same(owner, operatorEnv))) problems.push(`owner = ${owner}`);
        return problems;
    };

    /** ใช้ของรอบก่อนถ้าตรวจผ่านทุกข้อ ไม่งั้น deploy ใหม่แล้วจดลง progress ทันที */
    async function step(name, args = [], check = null) {
        const prev = progress[name];
        if (prev) {
            const problems = [];
            if ((await ethers.provider.getCode(prev)) === "0x") problems.push("ไม่มีโค้ดบนเชน");
            else if (!(await codeMatches(name, prev))) problems.push("โค้ดบนเชนไม่ตรง artifact ที่ compile อยู่");
            if (!problems.length && check) problems.push(...(await check(prev)));
            if (problems.length) {
                throw new Error(`${name} ${prev} จากรอบก่อนใช้ต่อไม่ได้: ${problems.join(" · ")}\n`
                    + "  ยังไม่ได้ส่งอะไรเพิ่ม — ตรวจไฟล์ progress หรือตั้ง FRESH_DEPLOY=1 ถ้าตั้งใจ deploy ใหม่ทั้งชุด");
            }
            console.log(`      ${name.padEnd(24)} ${prev}  (ของรอบก่อน — ตรวจบนเชนผ่าน)`);
            return prev;
        }
        const addr = await deploy(name, args);
        progress[name] = addr;
        saveProgress(net.chainId, progress);
        return addr;
    }

    console.log("\n[1/5] creator ของ ERC-20 ...");
    const erc20V2Creator = await step("ERC20V2Creator", [], creatorCheck);
    const utilityCreator = await step("UtilityTokenCreator", [], creatorCheck);
    const rewardCreator = await step("RewardTokenCreator", [], creatorCheck);
    const governanceCreator = await step("GovernanceTokenCreator", [], creatorCheck);
    const stablecoinCreator = await step("StablecoinTokenCreator", [], creatorCheck);

    console.log("\n[2/5] TPIXTokenFactoryV2 ...");
    const erc20Creators = [erc20V2Creator, utilityCreator, rewardCreator, governanceCreator, stablecoinCreator];
    const tokenFactory = await step("TPIXTokenFactoryV2", erc20Creators, factoryCheck(
        ["erc20V2Creator", "utilityCreator", "rewardCreator", "governanceCreator", "stablecoinCreator"], erc20Creators,
    ));

    console.log("\n[3/5] creator ของ NFT ...");
    const erc721Creator = await step("FactoryERC721Creator", [], creatorCheck);
    const collectionCreator = await step("NFTCollectionCreator", [], creatorCheck);

    console.log("\n[4/5] TPIXNFTFactory ...");
    const nftFactory = await step("TPIXNFTFactory", [erc721Creator, collectionCreator], factoryCheck(
        ["erc721Creator", "collectionCreator"], [erc721Creator, collectionCreator],
    ));

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
            await pace();
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
                await pace();
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

    if (IS_DRY_RUN) {
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
    // registry คือที่บันทึกถาวรแล้ว — ลบ progress ไม่ให้รอบหน้าหยิบของชุดนี้ไปใช้ซ้ำโดยไม่ตั้งใจ
    fs.rmSync(progressPath(net.chainId), { force: true });

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
