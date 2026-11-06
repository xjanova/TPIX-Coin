/**
 * เปิดขายเหรียญลูกผ่าน LaunchpadFactory — presale + PoolFeeder (เงินขายเข้าพูลอัตโนมัติ) + TrancheVesting
 * ในธุรกรรมเดียว แล้วเปิดพูล <เหรียญ>/USDT_TPIX ที่ราคาขายพร้อมกัน (seedUsdt)
 *
 *   ซ้อมบนเครื่อง:  npx hardhat run scripts/launchpad-create.js            (สัญญาจำลองทั้งชุด + ลองซื้อ 1 USDT)
 *   ดูก่อนส่ง:      npx hardhat run scripts/launchpad-create.js --network tpix    (อ่านเชนจริง ไม่ส่งอะไร)
 *   ส่งจริง:        CONFIRM_LAUNCH=<SYMBOL> ... --network tpix                 (ผ่าน launchpad-create.ps1)
 *   ดูสถานะ:       STATUS=1 npx hardhat run scripts/launchpad-create.js --network tpix
 *
 * ค่าที่ตั้งผ่าน environment (ของจริง: ต้องมีทุกตัว ยกเว้นที่บอกว่าไม่บังคับ):
 *   LAUNCH_PLAN       ชื่อไฟล์ใน scripts/launch-plans/ (ค่าปริยาย idtc) — อ่านหัวข้อ launchpad + vesting + sale
 *   TOKEN             ไม่บังคับ — ที่อยู่เหรียญ (ค่าปริยาย plan.token) ต้องสร้างจาก TPIXTokenFactoryV2 และปิด mint/pause/blacklist/auto-burn
 *   SALE_START        วันเปิดขาย เช่น 2026-11-20T10:00:00+07:00 หรือ unix — vesting เริ่มนับวันเดียวกัน
 *   BENEFICIARY       กระเป๋าที่รับเหรียญ vesting เมื่อปลดล็อก (แนะนำ multisig)
 *   PROJECT_TREASURY  กระเป๋าที่รับส่วนแบ่งโครงการ (poolShareBps 10000 = ไม่ได้อะไร แต่ต้องมีที่อยู่)
 *   SEED_USDT         ไม่บังคับ — ทับ seedUsdt ในแผน (0 = ให้การซื้อครั้งแรกเปิดพูลเอง)
 *
 * ด่านกันพลาด (หยุดก่อนส่งอะไรถ้าไม่ผ่าน):
 *   - เชนต้องตรง registry · LaunchpadFactory ต้องผูกกับ USDT_TPIX / router / Token Factory ตัวจริง
 *   - เหรียญตรงแผน (symbol/decimals/supply) · tokenCheck = 0 · กระเป๋าถือเหรียญ + USDT_TPIX พอ
 *   - กฎกันรักคิดก่อน (lib/launchpad-plan.js): LP ≥ 180 วัน, ≥ 50% เข้าพูล, ≥ 80% ของซัพพลายยังล็อกตอน LP ปลด
 *   - เหรียญนี้เคยเปิดขายผ่านโรงงานแล้ว = หยุด (ไม่เปิดซ้ำ)
 *   - คู่ <เหรียญ>/USDT_TPIX มีอยู่แล้วและราคาห่างเกินกรอบ = หยุด (โรงงานก็จะ revert)
 *   - จำลอง createLaunch (eth_call) ก่อนส่งจริง — revert = แจ้งชื่อ error แล้วหยุด
 * อนุมัติ (approve) ยอดพอดีเท่านั้น · ไม่ถือคีย์ ไม่เขียนคีย์ลงไฟล์ (คีย์มาจาก DEPLOYER_KEY ที่ .ps1 ตั้งชั่วคราว)
 *
 * Developed by Xman Studio
 */
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const { ethers, network } = hre;
const { buildLaunch, PlanError } = require("./lib/launchpad-plan");

const ROOT = path.join(__dirname, "..");
const REGISTRY_PATH = path.join(ROOT, "deployed-contracts.json");
const DRY_RUN = network.name === "hardhat" || network.name === "localhost";
const ZERO = ethers.ZeroAddress;

const RED = (s) => `\x1b[41m\x1b[97m ${s} \x1b[0m`;
const fmt = (v, dec) => Number(ethers.formatUnits(v, dec)).toLocaleString("en-US", { maximumFractionDigits: 6 });
const iso = (t) => new Date(Number(t) * 1000).toISOString().replace(".000Z", "Z");
const thai = (t) => new Date(Number(t) * 1000).toLocaleString("th-TH", { timeZone: "Asia/Bangkok", dateStyle: "medium", timeStyle: "short" });

function loadPlan() {
    const name = (process.env.LAUNCH_PLAN || "idtc").replace(/[^a-z0-9_-]/gi, "");
    const file = path.join(__dirname, "launch-plans", `${name}.json`);
    if (!fs.existsSync(file)) throw new PlanError(`ไม่พบแผน ${file}`);
    return JSON.parse(fs.readFileSync(file, "utf8"));
}

const loadRegistry = () => JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
const registryAddress = (reg, name) => (reg.contracts || []).find((c) => c.name === name)?.address || null;

function upsert(reg, entry) {
    reg.contracts = reg.contracts || [];
    const i = reg.contracts.findIndex((c) => c.name === entry.name);
    if (i >= 0) reg.contracts[i] = { ...reg.contracts[i], ...entry };
    else reg.contracts.push(entry);
}

function envAddress(key, { required }) {
    const raw = (process.env[key] || "").trim();
    if (!raw) {
        if (required) throw new PlanError(`ต้องตั้ง ${key}`);
        return null;
    }
    if (!/^0x[0-9a-fA-F]{40}$/.test(raw)) throw new PlanError(`${key} ไม่ใช่ที่อยู่: ${raw}`);
    const a = ethers.getAddress(raw.toLowerCase());
    if (a === ZERO) throw new PlanError(`${key} เป็นที่อยู่ศูนย์`);
    return a;
}

function envTime(key, { required, fallback }) {
    const raw = (process.env[key] || "").trim();
    if (!raw) {
        if (required) throw new PlanError(`ต้องตั้ง ${key}`);
        return fallback;
    }
    if (/^\d{9,11}$/.test(raw)) return BigInt(raw);
    // a bare date has no time zone — refuse it rather than guess UTC vs Bangkok
    if (!/[T ]\d{2}:\d{2}/.test(raw) || !/(Z|[+-]\d{2}:?\d{2})$/.test(raw)) {
        throw new PlanError(`${key} ต้องมีเวลาและเขตเวลา เช่น 2026-11-20T10:00:00+07:00 (ได้รับ ${raw})`);
    }
    const ms = Date.parse(raw);
    if (Number.isNaN(ms)) throw new PlanError(`${key} อ่านเป็นวันที่ไม่ได้: ${raw}`);
    return BigInt(Math.floor(ms / 1000));
}

function decodeRevert(err, iface) {
    const data = err?.data || err?.error?.data || err?.info?.error?.data;
    if (typeof data === "string" && data.length >= 10) {
        try {
            const e = iface.parseError(data);
            if (e) return `${e.name}(${e.args.map(String).join(", ")})`;
        } catch { /* not ours */ }
    }
    return err?.shortMessage || err?.reason || err?.message || String(err);
}

/** the local rehearsal: real contracts from this build, stand-in coins, a token made by the real Token Factory */
async function standIns(signer, plan) {
    const { deployTokenFactory } = require("../test/helpers/deployTokenFactory");
    const W = await (await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX")).deploy();
    const U = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
    const F = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(signer.address);
    const R = await (await ethers.getContractFactory("TPIXDEXRouter02")).deploy(await F.getAddress(), await W.getAddress());
    const { tokenFactory } = await deployTokenFactory();
    const VD = await (await ethers.getContractFactory("LaunchVestingDeployer")).deploy();
    const LF = await (await ethers.getContractFactory("LaunchpadFactory")).deploy(
        await U.getAddress(), await R.getAddress(), await VD.getAddress(), await tokenFactory.getAddress()
    );
    const supply = ethers.parseUnits(String(plan.totalSupply), Number(plan.decimals));
    const rc = await (await tokenFactory.createERC20V2(plan.name || plan.symbol, plan.symbol, Number(plan.decimals), supply, signer.address, false, false, false, false, 0, false, 0, 0)).wait();
    const ev = rc.logs.map((l) => { try { return tokenFactory.interface.parseLog(l); } catch { return null; } }).find((e) => e?.name === "TokenCreated");
    await U.setBridge(signer.address, true);
    await U.bridgeMint(signer.address, 1_000n * 10n ** 6n, ethers.id("dry-run-seed"));
    console.log("[dry-run] สัญญาจำลอง: USDT_TPIX, DEX, Token Factory, LaunchpadFactory — เหรียญทดสอบ", ev.args.tokenAddress);
    return {
        usdt: await U.getAddress(), router: await R.getAddress(), tokenRegistry: await tokenFactory.getAddress(),
        factory: await LF.getAddress(), token: ev.args.tokenAddress,
    };
}

async function findLaunch(lf, token) {
    const n = Number(await lf.launchCount());
    for (let i = n - 1; i >= 0; i--) {
        const l = await lf.launchAt(i);
        if (l.token.toLowerCase() === token.toLowerCase()) return { id: i, ...l.toObject() };
    }
    return null;
}

async function printStatus(launch, tokenC, dec, sym) {
    const sale = await ethers.getContractAt("FixedPriceSale", launch.sale);
    const feeder = await ethers.getContractAt("PoolFeeder", launch.feeder);
    const [cap, sold, raised, active, st, en, minP, maxW, inSale] = await Promise.all([
        sale.saleCap(), sale.sold(), sale.raised(), sale.isActive(), sale.startTime(), sale.endTime(),
        sale.minPurchase(), sale.maxPerWallet(), tokenC.balanceOf(launch.sale),
    ]);
    const [res, pair, unlock, pending] = await Promise.all([feeder.poolReserves(), feeder.pair(), feeder.lpUnlockTime(), feeder.pendingQuote()]);
    console.log(`\n=== ${sym} launch #${launch.id} ===`);
    console.log(`Sale     : ${launch.sale}`);
    console.log(`Feeder   : ${launch.feeder}`);
    console.log(`Vesting  : ${launch.vesting === ZERO ? "(ไม่มี)" : launch.vesting}`);
    console.log(`ช่วงขาย  : ${thai(st)} → ${thai(en)} · เปิดอยู่: ${active ? "ใช่" : "ไม่"}`);
    console.log(`ขายแล้ว  : ${fmt(sold, dec)} / ${fmt(cap, dec)} ${sym} · ได้เงิน ${fmt(raised, 6)} USDT · เหรียญในสัญญาขาย ${fmt(inSale, dec)}`);
    console.log(`ขั้นต่ำ  : ${fmt(minP, 6)} USDT · เพดาน/กระเป๋า ${maxW === 0n ? "ไม่จำกัด" : fmt(maxW, dec)}`);
    console.log(`พูล      : ${pair === ZERO ? "(ยังไม่มี)" : pair} · ${fmt(res[0], dec)} ${sym} / ${fmt(res[1], 6)} USDT · รอเข้าพูล ${fmt(pending, 6)} USDT`);
    console.log(`LP ปลด   : ${thai(unlock)}`);
    if (launch.vesting !== ZERO) {
        const v = await ethers.getContractAt("TrancheVesting", launch.vesting);
        console.log(`Vesting  : ${fmt(await v.totalAllocation(), dec)} ${sym} · ครบ: ${(await v.isFunded()) ? "ใช่" : RED("ไม่")}`);
    }
}

async function main() {
    const [signer] = await ethers.getSigners();
    if (!signer) throw new PlanError("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน (ผ่าน launchpad-create.ps1)");
    const plan = loadPlan();
    const reg = loadRegistry();
    const sym = plan.symbol;
    const dec = Number(plan.decimals);

    let addr;
    if (DRY_RUN) {
        addr = await standIns(signer, plan);
    } else {
        const live = Number((await ethers.provider.getNetwork()).chainId);
        if (Number(reg?.chain?.chainId) !== live) throw new PlanError(`chainId ไม่ตรง: registry ${reg?.chain?.chainId} แต่ต่อกับเชน ${live}`);
        addr = {
            usdt: registryAddress(reg, "USDT_TPIX"),
            router: registryAddress(reg, "TPIXDEXRouter02"),
            tokenRegistry: registryAddress(reg, "TPIXTokenFactoryV2"),
            factory: registryAddress(reg, "LaunchpadFactory"),
            token: envAddress("TOKEN", { required: false }) || (plan.token ? ethers.getAddress(plan.token.toLowerCase()) : null),
        };
        if (!addr.factory) throw new PlanError("ยังไม่มี LaunchpadFactory ใน deployed-contracts.json — รัน deploy-launchpad.ps1 ก่อน");
    }
    for (const [n, a] of Object.entries(addr)) {
        if (!a || (await ethers.provider.getCode(a)) === "0x") throw new PlanError(`${n} ${a} ไม่มีโค้ดบนเชนนี้`);
    }

    const lf = await ethers.getContractAt("LaunchpadFactory", addr.factory);
    const binds = [[await lf.quote(), addr.usdt, "USDT_TPIX"], [await lf.router(), addr.router, "router"], [await lf.tokenRegistry(), addr.tokenRegistry, "Token Factory"]];
    for (const [got, want, n] of binds) if (got.toLowerCase() !== want.toLowerCase()) throw new PlanError(`LaunchpadFactory ผูกกับ ${n} คนละตัว (${got})`);

    const tokenC = await ethers.getContractAt("FactoryERC20V2", addr.token);
    const usdtC = await ethers.getContractAt("USDT_TPIX", addr.usdt);
    const [tSym, tDec, tSupply, payDec] = await Promise.all([tokenC.symbol(), tokenC.decimals(), tokenC.totalSupply(), usdtC.decimals()]);
    if (tSym !== sym || Number(tDec) !== dec || tSupply !== ethers.parseUnits(String(plan.totalSupply), dec)) {
        throw new PlanError(`เหรียญไม่ตรงแผน: ${tSym}/${tDec}/${fmt(tSupply, Number(tDec))} — แผน ${sym}/${dec}/${plan.totalSupply}`);
    }
    if (Number(payDec) !== 6) throw new PlanError("USDT_TPIX decimals ไม่ใช่ 6");

    const existing = await findLaunch(lf, addr.token);
    if (existing || process.env.STATUS === "1") {
        if (!existing) { console.log(`${sym} ยังไม่เคยเปิดขายผ่าน LaunchpadFactory`); return; }
        await printStatus(existing, tokenC, dec, sym);
        if (process.env.STATUS !== "1") console.log(`\n${sym} เปิดขายผ่านโรงงานไปแล้ว — ไม่เปิดซ้ำ`);
        return;
    }

    const check = Number(await lf.tokenCheck(addr.token));
    if (check === 1) throw new PlanError(`${sym} ไม่ได้สร้างจาก TPIX Token Factory (ERC20V2) — โรงงานไม่รับ`);
    if (check === 2) throw new PlanError(`${sym} เปิดสวิตช์ mint/pause/blacklist/auto-burn ไว้ — โรงงานไม่รับ`);

    const now = BigInt((await ethers.provider.getBlock("latest")).timestamp);
    const L = buildLaunch(plan, {
        token: addr.token,
        saleStart: envTime("SALE_START", { required: !DRY_RUN, fallback: now + 120n }),
        beneficiary: envAddress("BENEFICIARY", { required: !DRY_RUN }) || signer.address,
        projectTreasury: envAddress("PROJECT_TREASURY", { required: !DRY_RUN }) || signer.address,
        payDecimals: 6,
        now,
        seedUsdt: process.env.SEED_USDT,
    });
    const p = L.params;

    const [tokBal, usdtBal] = await Promise.all([tokenC.balanceOf(signer.address), usdtC.balanceOf(signer.address)]);
    const pairAddr = await (await ethers.getContractAt("TPIXDEXFactory", await (await ethers.getContractAt("TPIXDEXRouter02", addr.router)).factory())).getPair(addr.token, addr.usdt);

    const perUsdt = (10n ** 6n * p.rateNumerator) / p.rateDenominator;
    console.log(`\n=== เปิดขาย ${sym} ผ่าน LaunchpadFactory ${DRY_RUN ? "(ซ้อม)" : "(เชน 4289)"} ===`);
    console.log(`กระเป๋าที่ส่ง     : ${signer.address}`);
    console.log(`เหรียญ            : ${addr.token}`);
    console.log(`LaunchpadFactory  : ${addr.factory}`);
    console.log(`ราคา              : 1 USDT = ${fmt(perUsdt, dec)} ${sym}  (${plan.sale.priceUsd} USD/เหรียญ · rate ${p.rateNumerator}/${p.rateDenominator})`);
    console.log(`เปิดขาย           : ${fmt(p.saleCap, dec)} ${sym}  ·  ${thai(p.startTime)} → ${thai(p.endTime)}  (${plan.launchpad.durationDays} วัน)`);
    console.log(`สำรองจับคู่พูล     : ${fmt(p.feederReserve, dec)} ${sym}`);
    console.log(`เข้าพูล            : ${p.poolShareBps / 100}% ของเงินขาย · กรอบราคา ±${(p.bandBps || 300) / 100}%`);
    console.log(`เปิดพูลทันที       : ${L.seedQuote === 0n ? "ไม่ (การซื้อครั้งแรกเปิดเอง)" : `${fmt(L.seedQuote, 6)} USDT_TPIX + ${fmt((L.seedQuote * p.rateNumerator) / p.rateDenominator, dec)} ${sym}`}`);
    console.log(`LP ล็อกถึง        : ${thai(p.lpUnlockTime)}  (${plan.launchpad.lpLockDaysAfterEnd} วันหลังจบขาย)`);
    console.log(`Vesting           : ${L.vesting.tranches.length ? `${fmt(L.vesting.tranches.reduce((a, t) => a + t.amount, 0n), dec)} ${sym} → ${L.vesting.beneficiary} · เริ่ม ${thai(L.vesting.start)}` : "(ไม่มี)"}`);
    console.log(`ส่วนแบ่งโครงการไป  : ${p.projectTreasury}`);
    console.log(`ซื้อขั้นต่ำ/เพดาน   : ${fmt(L.minPurchase, 6)} USDT / ${L.maxPerWallet === 0n ? "ไม่จำกัด" : `${fmt(L.maxPerWallet, dec)} ${sym}`}`);
    console.log(`ล็อกตอน LP ปลด     : ${Number(L.lockedBps) / 100}% ของซัพพลาย (ขั้นต่ำ 80%) · เหลือในกระเป๋าหลังเปิด ${fmt(L.freeAfter, dec)} ${sym}`);
    console.log(`ต้องใช้            : ${fmt(L.tokensNeeded, dec)} ${sym} (มี ${fmt(tokBal, dec)}) · ${fmt(L.seedQuote, 6)} USDT_TPIX (มี ${fmt(usdtBal, 6)})`);
    console.log(`คู่ ${sym}/USDT_TPIX  : ${pairAddr === ZERO ? "ยังไม่มี — จะสร้างใหม่ที่ราคาขาย" : pairAddr}`);

    if (tokBal < L.tokensNeeded) throw new PlanError(`${sym} ในกระเป๋าไม่พอ — ต้อง ${fmt(L.tokensNeeded, dec)}`);
    if (usdtBal < L.seedQuote) throw new PlanError(`USDT_TPIX ไม่พอเปิดพูล — ต้อง ${fmt(L.seedQuote, 6)} (ฝาก USDT จาก BSC ผ่าน tpix.online/bridge ก่อน หรือ SEED_USDT=0)`);
    if (pairAddr !== ZERO) {
        const pairC = await ethers.getContractAt("TPIXDEXPair", pairAddr);
        const [r0, r1] = await pairC.getReserves();
        if (r0 !== 0n || r1 !== 0n) console.log(RED(`คู่นี้มีสภาพคล่องอยู่แล้ว — โรงงานจะเช็กว่าราคาอยู่ในกรอบ ±${(p.bandBps || 300) / 100}% ไม่งั้น revert PoolPriceOff`));
    }

    if (!DRY_RUN && process.env.CONFIRM_LAUNCH !== sym) {
        console.log(`\nยังไม่ได้ส่งอะไร — ตรวจตัวเลขด้านบน แล้วยืนยันด้วย CONFIRM_LAUNCH=${sym} (launchpad-create.ps1 ถามให้)`);
        return;
    }

    // ── approve ยอดพอดี ─────────────────────────────────────────────────────
    const lfAddr = addr.factory;
    const approveExact = async (c, amount, label) => {
        const cur = await c.allowance(signer.address, lfAddr);
        if (cur === amount) return;
        console.log(`approve ${label}...`);
        await (await c.connect(signer).approve(lfAddr, amount)).wait();
    };
    await approveExact(tokenC, L.tokensNeeded, sym);
    if (L.seedQuote > 0n) await approveExact(usdtC, L.seedQuote, "USDT_TPIX");

    // ── จำลองก่อนส่ง ────────────────────────────────────────────────────────
    try {
        await lf.connect(signer).createLaunch.staticCall(p, L.vesting);
    } catch (e) {
        throw new PlanError(`จำลอง createLaunch ไม่ผ่าน: ${decodeRevert(e, lf.interface)} — ไม่ได้ส่ง (allowance ที่ตั้งไว้ใช้ได้เฉพาะโรงงาน และโรงงานดึงจากผู้เรียกเท่านั้น)`);
    }

    console.log("createLaunch...");
    const rc = await (await lf.connect(signer).createLaunch(p, L.vesting)).wait();
    const ev = rc.logs.map((l) => { try { return lf.interface.parseLog(l); } catch { return null; } }).find((x) => x?.name === "LaunchCreated");
    if (!ev) throw new Error(`ไม่พบ LaunchCreated ใน ${rc.hash}`);
    const launch = { id: Number(ev.args.id), token: addr.token, sale: ev.args.sale, feeder: ev.args.feeder, vesting: ev.args.vesting };
    console.log(`  tx ${rc.hash}`);

    if (!DRY_RUN) {
        // บันทึกทันที — ถ้าขั้นต่อไปพัง รันซ้ำจะเจอ launch นี้แล้วแสดงสถานะ ไม่เปิดซ้ำ
        const today = new Date().toISOString().slice(0, 10);
        const base = { compilerVersion: "0.8.24", optimizer: { enabled: true, runs: 200 }, evmVersion: "london", category: "launchpad", verified: false, deployedAt: today };
        upsert(reg, { ...base, name: `${sym}_LaunchpadSale`, address: launch.sale, sourceFile: "contracts/src/launch/FixedPriceSale.sol", description: `presale ${sym} ผ่าน LaunchpadFactory #${launch.id} — เจ้าของคือ PoolFeeder ตลอดไป` });
        upsert(reg, { ...base, name: `${sym}_PoolFeeder`, address: launch.feeder, sourceFile: "contracts/src/launch/PoolFeeder.sol", description: `รับเงินขาย ${sym} แล้วเติมพูล ${sym}/USDT_TPIX · LP ล็อกถึง ${iso(p.lpUnlockTime)}` });
        if (launch.vesting !== ZERO) upsert(reg, { ...base, name: `${sym}_LaunchpadVesting`, address: launch.vesting, sourceFile: "contracts/src/launch/TrancheVesting.sol", description: `${sym} ล็อกตามตาราง — สร้างโดย LaunchpadFactory #${launch.id}` });
        reg.updated = today;
        fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + "\n");
    }

    const feeder = await ethers.getContractAt("PoolFeeder", launch.feeder);
    if (L.minPurchase > 0n || L.maxPerWallet > 0n) {
        console.log("ตั้งซื้อขั้นต่ำ/เพดาน...");
        await (await feeder.connect(signer).setSaleLimits(L.minPurchase, L.maxPerWallet)).wait();
    }

    // ── ตรวจผลบนเชน ─────────────────────────────────────────────────────────
    const sale = await ethers.getContractAt("FixedPriceSale", launch.sale);
    const problems = [];
    if ((await tokenC.balanceOf(launch.sale)) !== p.saleCap) problems.push("เหรียญในสัญญาขายไม่ครบ");
    if ((await sale.owner()).toLowerCase() !== launch.feeder.toLowerCase()) problems.push("เจ้าของสัญญาขายไม่ใช่ feeder");
    if (L.seedQuote > 0n) {
        const [tSide, qSide] = await feeder.poolReserves();
        if (qSide < L.seedQuote || tSide === 0n) problems.push("พูลยังไม่เปิดตาม seed");
    }
    if (launch.vesting !== ZERO && !(await (await ethers.getContractAt("TrancheVesting", launch.vesting)).isFunded())) problems.push("vesting ไม่ครบ");
    await printStatus(launch, tokenC, dec, sym);
    if (problems.length) throw new Error(`ตรวจหลังเปิดไม่ผ่าน: ${problems.join(" · ")}`);

    if (DRY_RUN) {
        // ลองซื้อ 1 USDT แบบที่ตัวแทนบนเว็บจะทำ (buyFor) แล้วเติมพูล
        const [, buyer] = await ethers.getSigners();
        await hre.network.provider.send("evm_setNextBlockTimestamp", [Number(p.startTime)]);
        const one = 10n ** 6n;
        await (await usdtC.connect(signer).approve(launch.sale, one)).wait();
        await (await sale.connect(signer).buyFor(buyer.address, one)).wait();
        const got = await tokenC.balanceOf(buyer.address);
        if (got !== (one * p.rateNumerator) / p.rateDenominator) throw new Error(`ซื้อ 1 USDT ได้ ${fmt(got, dec)} ไม่ตรงราคา`);
        if ((await feeder.pendingQuote()) >= p.minFeed) await (await feeder.feed()).wait();
        const [tSide, qSide] = await feeder.poolReserves();
        console.log(`\n[dry-run] ซื้อ 1 USDT ได้ ${fmt(got, dec)} ${sym} · พูลหลังเติม ${fmt(tSide, dec)} ${sym} / ${fmt(qSide, 6)} USDT`);
        console.log("[dry-run] ซ้อมผ่าน — ไม่เขียน deployed-contracts.json");
        return;
    }

    console.log(`\nเปิดขายแล้ว — แจ้ง Claude ที่อยู่ Sale ด้านบน เพื่อ:`);
    console.log(`  1. verify บน explorer: npx hardhat verify-explorer ${sym}_LaunchpadSale ${sym}_PoolFeeder ${launch.vesting !== ZERO ? `${sym}_LaunchpadVesting` : ""}`);
    console.log(`  2. ลงทะเบียนหน้าขายบนเว็บ: php artisan launchpad:register ${launch.sale} --approve`);
    console.log(`  3. (ไม่บังคับ) พูล ${sym}/TPIX: POOL_USDT=0 ผ่าน launch-pools.js — พูล ${sym}/USDT เปิดแล้วในธุรกรรมนี้`);
}

main().catch((e) => {
    console.error(`\n${e instanceof PlanError ? "หยุด" : "❌ ล้มเหลว"}: ${e.message || e}`);
    process.exitCode = 1;
});
