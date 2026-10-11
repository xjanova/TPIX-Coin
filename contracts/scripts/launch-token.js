/**
 * เปิดตัวเหรียญจาก Token Factory: deploy สัญญาล็อก (TrancheVesting) + presale ราคาคงที่ (FixedPriceSale)
 *
 *   ซ้อมบนเครื่อง:  npx hardhat run scripts/launch-token.js
 *   ของจริง:       npx hardhat run scripts/launch-token.js --network tpix
 *   ดูสถานะ:       STATUS=1 npx hardhat run scripts/launch-token.js --network tpix
 *
 * ค่าที่ตั้งผ่าน environment (hardhat run รับ argument เองไม่ได้):
 *   LAUNCH_PLAN    ชื่อไฟล์ใน scripts/launch-plans/ (ค่าปริยาย idtc)
 *   TOKEN          ที่อยู่เหรียญที่สร้างผ่าน Token Factory แล้ว           (ของจริง: ต้องมี)
 *   BENEFICIARY    กระเป๋าที่รับเหรียญเมื่อปลดล็อก — แนะนำ multisig          (ของจริง: ต้องมี)
 *   VESTING_START  วันเริ่มนับล็อก เช่น 2026-11-01 หรือ unix — ใช้วันเปิดตลาด   (ของจริง: ต้องมี)
 *   SALE_CAP       จำนวนเหรียญที่เปิดขาย presale (หน่วยเต็ม) — ไม่ตั้ง = ข้าม presale
 *   SALE_START / SALE_END   ช่วงเวลาขาย (วันที่หรือ unix)
 *   SALE_TREASURY  กระเป๋าที่รับ USDT จากการขาย
 *   SALE_OWNER     ผู้คุม presale (หยุด/ตั้งเพดาน) — ค่าปริยายคือกระเป๋าที่ deploy
 *
 * สคริปต์นี้ "ไม่โอนเหรียญ" บนเชนจริง — เจ้าของเหรียญโอนเข้าสัญญาเองจากกระเป๋าของตัวเอง
 * แล้วรันโหมด STATUS ยืนยันว่าล็อกครบ · รันซ้ำได้: ตัวที่ deploy แล้วจะใช้ของเดิม ไม่ deploy ซ้ำ
 *   - ใช้ของเดิมเฉพาะเมื่อค่าทุกตัวบนเชนตรงกับที่ตั้งไว้ (ผู้รับ วันเริ่ม ตาราง treasury ผู้คุม ช่วงขาย ...)
 *     ไม่ตรง = หยุด แล้วบอกว่าตัวไหนต่าง — ไม่หยิบสัญญาเดิมมาใช้เงียบ ๆ (scripts/lib/launch-checks.js)
 *   - ตรวจค่าที่ตั้งครบทุกตัวก่อน deploy อะไรทั้งนั้น และบันทึก registry ทันทีหลัง deploy แต่ละตัว
 *   - เหรียญต้องเป็น FactoryERC20V2 standard จาก build นี้ (ไม่มี mint/pause/blacklist/auto-burn) ไม่งั้นหยุด
 *     (ALLOW_NONSTANDARD_TOKEN=1 ถ้าตั้งใจจริง)
 *
 * Developed by Xman Studio
 */
const fs = require("fs");
const path = require("path");
const { ethers, network, artifacts } = require("hardhat");
const checks = require("./lib/launch-checks");

const ROOT = path.join(__dirname, "..");
const REGISTRY_PATH = path.join(ROOT, "deployed-contracts.json");
const DRY_RUN = network.name === "hardhat" || network.name === "localhost";

const RED = (s) => `\x1b[41m\x1b[97m ${s} \x1b[0m`;
const fmt = (wei, dec) => Number(ethers.formatUnits(wei, dec)).toLocaleString("en-US", { maximumFractionDigits: 6 });

function loadPlan() {
    const name = (process.env.LAUNCH_PLAN || "idtc").replace(/[^a-z0-9_-]/gi, "");
    const file = path.join(__dirname, "launch-plans", `${name}.json`);
    if (!fs.existsSync(file)) throw new Error(`ไม่พบแผน ${file}`);
    return JSON.parse(fs.readFileSync(file, "utf8"));
}

function loadRegistry() {
    return JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
}

function registryAddress(reg, name) {
    return (reg.contracts || []).find((c) => c.name === name)?.address || null;
}

function envAddress(key, { required }) {
    const raw = (process.env[key] || "").trim();
    if (!raw) {
        if (required) throw new Error(`ต้องตั้ง ${key}`);
        return null;
    }
    if (!/^0x[0-9a-fA-F]{40}$/.test(raw)) throw new Error(`${key} ไม่ใช่ที่อยู่: ${raw}`);
    return ethers.getAddress(raw.toLowerCase());
}

/** "2026-11-01" · "2026-11-01T09:00:00+07:00" · "1793491200" → unix seconds */
function envTime(key, { required, fallback }) {
    const raw = (process.env[key] || "").trim();
    if (!raw) {
        if (required) throw new Error(`ต้องตั้ง ${key}`);
        return fallback;
    }
    if (/^\d{9,11}$/.test(raw)) return BigInt(raw);
    const ms = Date.parse(raw);
    if (Number.isNaN(ms)) throw new Error(`${key} อ่านเป็นวันที่ไม่ได้: ${raw}`);
    return BigInt(Math.floor(ms / 1000));
}

const iso = (t) => new Date(Number(t) * 1000).toISOString().replace(".000Z", "Z");

/** "0.0000015" → { num: 15n, den: 10000000n } */
function decimalToFraction(s) {
    if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(`ราคาไม่ถูกรูปแบบ: ${s}`);
    const [int, frac = ""] = s.split(".");
    return { num: BigInt(int + frac), den: 10n ** BigInt(frac.length) };
}

const gcd = (a, b) => (b === 0n ? a : gcd(b, a % b));

/**
 * tokensOut = payAmount × num ÷ den (หน่วยเล็กสุดทั้งคู่)
 * ราคา p USD ต่อเหรียญ, จ่ายด้วยเหรียญ $1 → 1 หน่วย pay = 10^-payDec USD = 10^-payDec / p เหรียญ
 */
function saleRate(priceUsd, tokenDecimals, payDecimals) {
    const p = decimalToFraction(priceUsd);
    if (p.num === 0n) throw new Error("ราคาต้องมากกว่า 0");
    let num = 10n ** BigInt(tokenDecimals) * p.den;
    let den = p.num * 10n ** BigInt(payDecimals);
    const g = gcd(num, den);
    return { num: num / g, den: den / g };
}

async function hasCode(addr) {
    return addr && (await ethers.provider.getCode(addr)) !== "0x";
}

/**
 * deploy ครั้งเดียว — ถ้า registry มีตัวเดิมที่มีโค้ดอยู่ ใช้ของเดิม "เฉพาะเมื่อ mismatches() ว่าง"
 * deploy ใหม่บนเชนจริง → บันทึก registry ทันที (ถ้าขั้นถัดไปล้ม รอบหน้าจะเห็นตัวนี้ ไม่ deploy ซ้ำจนมีสัญญากำพร้า)
 */
async function deployOnce(reg, regName, contractName, args, { mismatches, entry }) {
    const existing = registryAddress(reg, regName);
    if (!DRY_RUN && (await hasCode(existing))) {
        const diff = await mismatches(await ethers.getContractAt(contractName, existing));
        if (diff.length) {
            throw new Error([
                `${regName} ${existing} ใน registry ไม่ตรงกับค่าที่ตั้งตอนนี้:`,
                ...diff.map((d) => `        - ${d}`),
                `      ถ้าค่าใหม่ถูก: สัญญาเดิมต้องยังไม่มีเหรียญ → ลบรายการ ${regName} ออกจาก deployed-contracts.json แล้วรันใหม่ (deploy ตัวใหม่)`,
                "      ถ้าค่าเดิมถูก: ตั้ง environment ให้ตรงกับบนเชน · ห้ามโอนเหรียญเข้าสัญญาจนกว่าจะรันผ่าน",
            ].join("\n"));
        }
        console.log(`      ${regName.padEnd(16)} ${existing}  (มีอยู่แล้ว ค่าตรงทุกตัว — ใช้ของเดิม)`);
        return { address: existing, fresh: false };
    }
    const c = await (await ethers.getContractFactory(contractName)).deploy(...args);
    await c.waitForDeployment();
    const address = await c.getAddress();
    if (!(await hasCode(address))) throw new Error(`${contractName}: eth_getCode คืน 0x — ไม่ได้ขึ้นเชนจริง`);
    console.log(`      ${regName.padEnd(16)} ${address}`);
    if (!DRY_RUN) saveEntry({ name: regName, address, ...(await buildMeta(contractName)), ...entry });
    return { address, fresh: true };
}

/** compiler/optimizer/evm/viaIR จาก build-info ที่ compile จริง (เดิมเขียน viaIR: true ตายตัว ทั้งที่ src/launch ไม่ได้ใช้ viaIR) */
async function buildMeta(contractName) {
    const bi = await artifacts.getBuildInfo(`src/launch/${contractName}.sol:${contractName}`);
    const st = bi.input.settings;
    return {
        sourceFile: `contracts/src/launch/${contractName}.sol`, category: "launch", compilerVersion: bi.solcVersion,
        optimizer: st.optimizer, evmVersion: st.evmVersion, viaIR: !!st.viaIR, verified: false,
        deployedAt: new Date().toISOString().slice(0, 10),
    };
}

function saveEntry(e) {
    const fresh = loadRegistry();
    fresh.contracts = (fresh.contracts || []).filter((c) => c.name !== e.name).concat(e);
    fresh.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(fresh, null, 2) + "\n");
}

/** ตรวจเหรียญก่อนผูกสัญญาใด ๆ — เหรียญที่หักค่าตอนโอนทำให้สัญญาล็อก/ขายคำนวณผิดทั้งหมด */
async function inspectToken(tokenAddr, plan) {
    if (!(await hasCode(tokenAddr))) throw new Error(`TOKEN ${tokenAddr} ไม่มีโค้ดบนเชน`);
    const token = await ethers.getContractAt("FactoryERC20V2", tokenAddr);
    const [symbol, decimals, supply] = await Promise.all([token.symbol(), token.decimals(), token.totalSupply()]);
    console.log(`      ${symbol} · ${decimals} ทศนิยม · supply ${fmt(supply, decimals)}`);

    if (symbol !== plan.symbol) throw new Error(`symbol ${symbol} ไม่ตรงแผน (${plan.symbol})`);
    if (Number(decimals) !== plan.decimals) throw new Error(`decimals ${decimals} ไม่ตรงแผน (${plan.decimals})`);
    if (supply !== ethers.parseUnits(plan.totalSupply, plan.decimals)) {
        throw new Error(`supply ${fmt(supply, decimals)} ไม่ตรงแผน (${plan.totalSupply})`);
    }

    // เดิมแค่พิมพ์ตัวแดงแล้วไปต่อ — เหรียญแก้ไม่ได้หลังสร้าง ต้องหยุดก่อนล็อก 770B เข้าไป
    const problems = await checks.tokenProblems(token, { artifacts, provider: ethers.provider });
    if (problems.some((p) => p.startsWith("auto-burn: เปิด"))) {
        throw new Error("เหรียญเปิด auto-burn (หักค่าตอนโอน) — สัญญาล็อก/presale และ router ของ DEX รองรับไม่ได้");
    }
    if (problems.length) {
        for (const p of problems) console.log("      " + RED(p));
        if (process.env.ALLOW_NONSTANDARD_TOKEN !== "1") {
            throw new Error("เหรียญไม่ใช่ FactoryERC20V2 standard ตามแผน — หยุดก่อน deploy (ตั้ง ALLOW_NONSTANDARD_TOKEN=1 ถ้าตั้งใจจริง)");
        }
    } else {
        console.log("      ✅ standard: ไม่มี mint/pause/blacklist/auto-burn · โค้ดตรงกับ FactoryERC20V2 ที่ตรวจแล้ว");
    }
    return { token, symbol, decimals: Number(decimals) };
}

async function printStatus(reg, plan) {
    const vestAddr = registryAddress(reg, `${plan.symbol}_Vesting`);
    const saleAddr = registryAddress(reg, `${plan.symbol}_Presale`);
    if (!vestAddr && !saleAddr) throw new Error(`ยังไม่มี ${plan.symbol}_Vesting / ${plan.symbol}_Presale ใน registry`);

    if (vestAddr) {
        const v = await ethers.getContractAt("TrancheVesting", vestAddr);
        const token = await ethers.getContractAt("FactoryERC20V2", await v.token());
        const dec = Number(await token.decimals());
        const [total, released, funded, bal, locked, [nextAt, nextAmt]] = await Promise.all([
            v.totalAllocation(), v.released(), v.isFunded(), token.balanceOf(vestAddr), v.lockedAmount(), v.nextUnlock(),
        ]);
        console.log(`\nสัญญาล็อก ${vestAddr}`);
        console.log(`  ผู้รับ       : ${await v.beneficiary()}`);
        console.log(`  เริ่มนับ     : ${iso(await v.start())}`);
        console.log(`  ตามตาราง    : ${fmt(total, dec)} · ปลดไปแล้ว ${fmt(released, dec)} · ยังล็อก ${fmt(locked, dec)}`);
        console.log(`  เหรียญในสัญญา: ${fmt(bal, dec)}  ${funded ? "✅ ล็อกครบ" : RED("ยังฝากไม่ครบ — ห้ามประกาศว่าล็อกแล้ว")}`);
        if (nextAt > 0n) console.log(`  งวดถัดไป    : ${iso(nextAt)} · ${fmt(nextAmt, dec)}`);
    }
    if (saleAddr) {
        const s = await ethers.getContractAt("FixedPriceSale", saleAddr);
        const token = await ethers.getContractAt("FactoryERC20V2", await s.saleToken());
        const pay = await ethers.getContractAt("FactoryERC20V2", await s.payToken());
        const [dec, payDec] = [Number(await token.decimals()), Number(await pay.decimals())];
        const [cap, sold, raised, bal, active, start, end] = await Promise.all([
            s.saleCap(), s.sold(), s.raised(), token.balanceOf(saleAddr), s.isActive(), s.startTime(), s.endTime(),
        ]);
        const needed = cap - sold;
        console.log(`\nPresale ${saleAddr}`);
        console.log(`  ช่วงขาย     : ${iso(start)} → ${iso(end)} · ${active ? "🟢 เปิดขายอยู่" : "⚪ ไม่ได้เปิดขาย"}`);
        console.log(`  ราคา        : 1 ${await pay.symbol()} = ${fmt(await s.quote(10n ** BigInt(payDec)), dec)} ${await token.symbol()}`);
        console.log(`  ขายแล้ว     : ${fmt(sold, dec)} / ${fmt(cap, dec)} · ได้เงิน ${fmt(raised, payDec)}`);
        console.log(`  เหรียญในสัญญา: ${fmt(bal, dec)}  ${bal >= needed ? "✅ พอขายถึงเพดาน" : RED(`ขาด ${fmt(needed - bal, dec)} — ผู้ซื้อจะซื้อไม่ผ่านเมื่อเหรียญหมด`)}`);
        console.log(`  เงินเข้า     : ${await s.treasury()} · ผู้คุม ${await s.owner()} · ${(await s.paused()) ? "⏸ หยุดอยู่" : "ทำงาน"}`);
    }
}

async function main() {
    const plan = loadPlan();
    const reg = loadRegistry();
    const [deployer] = await ethers.getSigners();
    if (!deployer) throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน");

    const net = await ethers.provider.getNetwork();
    if (net.chainId !== 4289n) throw new Error(`chainId ${net.chainId} ไม่ใช่ TPIX Chain (4289) — หยุดไว้ก่อน`);

    if (process.env.STATUS === "1") return printStatus(reg, plan);

    console.log("─".repeat(72));
    console.log(`เปิดตัว ${plan.symbol} · network ${network.name}${DRY_RUN ? " (ซ้อม)" : ""} · deployer ${deployer.address}`);
    console.log("─".repeat(72));

    const now = BigInt((await ethers.provider.getBlock("latest")).timestamp);

    // ── อ่านและตรวจค่าที่ตั้งทั้งหมดก่อน deploy อะไรทั้งนั้น ──
    // (เดิมอ่าน SALE_TREASURY/SALE_START หลัง deploy สัญญาล็อกไปแล้ว — ลืมตั้งตัวเดียว = สัญญาล็อกกำพร้าบนเชน)
    let tokenAddr = envAddress("TOKEN", { required: !DRY_RUN });
    const beneficiary = envAddress("BENEFICIARY", { required: !DRY_RUN }) || deployer.address;
    const start = envTime("VESTING_START", { required: !DRY_RUN, fallback: now + 86400n });
    if (start < now - 3600n && process.env.ALLOW_PAST_START !== "1") {
        throw new Error(`VESTING_START ${iso(start)} อยู่ในอดีต — ล็อกจะเริ่มนับย้อนหลัง (ตั้ง ALLOW_PAST_START=1 ถ้าตั้งใจ)`);
    }
    const period = BigInt(plan.vesting.periodSeconds);
    const capRaw = (process.env.SALE_CAP || (DRY_RUN ? "100000000000" : "")).replace(/[,_]/g, "");
    let saleCfg = null;
    if (capRaw) {
        if (!/^\d+$/.test(capRaw)) throw new Error(`SALE_CAP ต้องเป็นจำนวนเหรียญเต็มหน่วย: ${capRaw}`);
        const saleStart = envTime("SALE_START", { required: !DRY_RUN, fallback: now + 60n });
        const saleEnd = envTime("SALE_END", { required: !DRY_RUN, fallback: saleStart + 30n * 86400n });
        const treasury = envAddress("SALE_TREASURY", { required: !DRY_RUN }) || deployer.address;
        const owner = envAddress("SALE_OWNER", { required: false }) || deployer.address;
        if (saleEnd <= saleStart) throw new Error("SALE_END ต้องหลัง SALE_START");
        if (saleEnd <= now) throw new Error(`SALE_END ${iso(saleEnd)} ผ่านไปแล้ว`);
        saleCfg = { capRaw, saleStart, saleEnd, treasury, owner };
    }
    if (!DRY_RUN) {
        // กระเป๋าที่ deploy คือคีย์ร้อน (อยู่ใน environment) — ไม่ควรเป็นผู้รับเหรียญล็อกหรือผู้คุม presale
        if (beneficiary.toLowerCase() === deployer.address.toLowerCase()) {
            console.log(RED("BENEFICIARY = กระเป๋าที่ deploy (คีย์ร้อน) — แนะนำ multisig"));
        }
        if (saleCfg && saleCfg.owner.toLowerCase() === deployer.address.toLowerCase()) {
            console.log(RED("SALE_OWNER = กระเป๋าที่ deploy (คีย์ร้อน) — ผู้คุมหยุดขาย/ถอนเหรียญที่เหลือ/เปลี่ยนกระเป๋ารับเงินได้ แนะนำ multisig"));
        }
    }

    // ── ซ้อม: สร้างเหรียญ standard ขึ้นมาเองแบบเดียวกับที่ factory สร้าง และ USDT จำลอง ──
    let payAddr = registryAddress(reg, plan.sale.payToken);
    let mockUsdt = null;
    if (DRY_RUN) {
        const T = await ethers.getContractFactory("FactoryERC20V2");
        tokenAddr = tokenAddr || await (await T.deploy("Dry Run " + plan.symbol, plan.symbol, plan.decimals,
            ethers.parseUnits(plan.totalSupply, plan.decimals), deployer.address,
            false, false, false, false, 0, false, 0, 0)).getAddress();   // "standard" ตามที่ ThaiXTrade ส่งจริง
        mockUsdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        payAddr = await mockUsdt.getAddress();
    }

    console.log("\n[1/4] ตรวจเหรียญ ...");
    const { decimals } = await inspectToken(tokenAddr, plan);

    const tranches = plan.vesting.tranches.map((t) => ({
        amount: ethers.parseUnits(t.amount, decimals), cliffPeriods: t.cliffPeriods, releasePeriods: t.releasePeriods,
    }));
    const vestTotal = tranches.reduce((a, t) => a + t.amount, 0n);

    let sale = null, saleExp = null;
    if (saleCfg) {
        if (!payAddr || !(await hasCode(payAddr))) throw new Error(`ไม่พบ ${plan.sale.payToken} บนเชน`);
        const pay = await ethers.getContractAt("FactoryERC20V2", payAddr);
        const payDec = Number(await pay.decimals());
        const { num, den } = saleRate(plan.sale.priceUsd, decimals, payDec);
        saleExp = {
            saleToken: tokenAddr, payToken: payAddr, num, den, cap: ethers.parseUnits(saleCfg.capRaw, decimals),
            treasury: saleCfg.treasury, start: saleCfg.saleStart, end: saleCfg.saleEnd, owner: saleCfg.owner,
            paySymbol: await pay.symbol(), payDec,
        };
    }

    // ── สัญญาล็อก ──
    console.log(`\n[2/4] สัญญาล็อก ${fmt(vestTotal, decimals)} ${plan.symbol} · เริ่มนับ ${iso(start)} · ผู้รับ ${beneficiary}`);
    for (const t of plan.vesting.tranches) {
        const from = t.cliffPeriods + 1, to = t.cliffPeriods + t.releasePeriods;
        console.log(`      ${t.name.padEnd(10)} ${Number(t.amount).toLocaleString("en-US").padStart(18)} → ปลดงวดที่ ${from}–${to}`);
    }
    const vest = await deployOnce(reg, `${plan.symbol}_Vesting`, "TrancheVesting",
        [tokenAddr, beneficiary, start, period, tranches, plan.vesting.label], {
            mismatches: (c) => checks.vestingMismatches(c, { token: tokenAddr, beneficiary, start, period, tranches, label: plan.vesting.label }),
            entry: { description: `${plan.vesting.label} · token ${tokenAddr} · ผู้รับ ${beneficiary}` },
        });
    const vesting = await ethers.getContractAt("TrancheVesting", vest.address);
    if ((await vesting.totalAllocation()) !== vestTotal) throw new Error("ยอดในสัญญาล็อกไม่ตรงแผน");

    // ── presale ──
    if (saleExp) {
        const e = saleExp;
        console.log(`\n[3/4] presale ${fmt(e.cap, decimals)} ${plan.symbol} ที่ $${plan.sale.priceUsd} · ${iso(e.start)} → ${iso(e.end)}`);
        console.log(`      ราคา: 1 ${e.paySymbol} = ${fmt((10n ** BigInt(e.payDec)) * e.num / e.den, decimals)} ${plan.symbol} (rate ${e.num}/${e.den})`);
        console.log(`      เงินเข้า ${e.treasury} · ผู้คุม ${e.owner}`);
        const s = await deployOnce(reg, `${plan.symbol}_Presale`, "FixedPriceSale",
            [tokenAddr, payAddr, e.num, e.den, e.cap, e.treasury, e.start, e.end, e.owner], {
                mismatches: (c) => checks.saleMismatches(c, e),
                entry: { description: `Presale ${plan.symbol} ที่ $${plan.sale.priceUsd} จ่ายด้วย ${plan.sale.payToken}` },
            });
        sale = await ethers.getContractAt("FixedPriceSale", s.address);
    } else {
        console.log("\n[3/4] [ข้าม] presale — ไม่ได้ตั้ง SALE_CAP");
    }

    // ── ซ้อม: ฝากเหรียญ ซื้อจริง ปลดล็อกจริง เพื่อพิสูจน์ทั้งสาย ──
    if (DRY_RUN) {
        console.log("\n[4/4] ซ้อมทั้งสาย ...");
        const token = await ethers.getContractAt("FactoryERC20V2", tokenAddr);
        await (await token.transfer(vest.address, vestTotal)).wait();
        if (!(await vesting.isFunded())) throw new Error("ฝากครบแล้วแต่ isFunded = false");
        if (sale) {
            await (await token.transfer(await sale.getAddress(), await sale.saleCap())).wait();
            await (await mockUsdt.setBridge(deployer.address, true)).wait();
            await (await mockUsdt.bridgeMint(deployer.address, 15n * 10n ** 5n, ethers.id("dry-run"))).wait();
            await (await mockUsdt.approve(await sale.getAddress(), ethers.MaxUint256)).wait();
            await network.provider.send("evm_setNextBlockTimestamp", [Number(await sale.startTime())]);
            const before = await token.balanceOf(deployer.address);
            await (await sale.buy(15n * 10n ** 5n)).wait();                // 1.5 USDT
            const got = (await token.balanceOf(deployer.address)) - before;
            console.log(`      ซื้อ 1.5 USDT ได้ ${fmt(got, decimals)} ${plan.symbol}`);
        }
        const [firstAt, firstAmt] = await vesting.nextUnlock();
        await network.provider.send("evm_setNextBlockTimestamp", [Number(firstAt)]);
        await (await vesting.release()).wait();
        console.log(`      งวดแรก ${iso(firstAt)} ปลด ${fmt(firstAmt, decimals)} ${plan.symbol} ไปที่ผู้รับ ✅`);
        await printStatus({ contracts: [
            { name: `${plan.symbol}_Vesting`, address: vest.address },
            ...(sale ? [{ name: `${plan.symbol}_Presale`, address: await sale.getAddress() }] : []),
        ] }, plan);
        console.log("\nซ้อมผ่านหมด — ของจริงใช้ --network tpix พร้อม TOKEN / BENEFICIARY / VESTING_START");
        return;
    }

    console.log("\n[4/4] deployed-contracts.json บันทึกทันทีหลัง deploy แต่ละตัวแล้ว");
    console.log("\n=== ขั้นต่อไป (เจ้าของเหรียญทำเองจากกระเป๋าที่ถือเหรียญ) ===");
    console.log(`  1. โอน ${fmt(vestTotal, decimals)} ${plan.symbol} → ${vest.address}  (สัญญาล็อก)`);
    if (sale) console.log(`  2. โอน ${fmt(await sale.saleCap(), decimals)} ${plan.symbol} → ${await sale.getAddress()}  (presale)`);
    console.log("  3. ตรวจ:   STATUS=1 npx hardhat run scripts/launch-token.js --network tpix");
    console.log(`  4. verify: node scripts/verify-blockscout.js ${plan.symbol}_Vesting${sale ? ` ${plan.symbol}_Presale` : ""}`);
}

main().catch((e) => {
    console.error("\nล้มเหลว:", e.message);
    process.exitCode = 1;
});
