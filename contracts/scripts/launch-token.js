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
 *
 * Developed by Xman Studio
 */
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

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

async function deployOnce(reg, regName, contractName, args) {
    const existing = registryAddress(reg, regName);
    if (!DRY_RUN && (await hasCode(existing))) {
        console.log(`      ${regName.padEnd(16)} ${existing}  (มีอยู่แล้ว — ใช้ของเดิม)`);
        return { address: existing, fresh: false };
    }
    const c = await (await ethers.getContractFactory(contractName)).deploy(...args);
    await c.waitForDeployment();
    const address = await c.getAddress();
    if (!(await hasCode(address))) throw new Error(`${contractName}: eth_getCode คืน 0x — ไม่ได้ขึ้นเชนจริง`);
    console.log(`      ${regName.padEnd(16)} ${address}`);
    return { address, fresh: true };
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

    const flag = async (fn) => { try { return await token[fn](); } catch { return null; } };
    const flags = {
        mint: await flag("isMintable"),
        pause: await flag("isPausable"),
        blacklist: await flag("isBlacklistEnabled"),
        autoBurn: await flag("isAutoBurnEnabled"),
    };
    if (flags.autoBurn) {
        throw new Error("เหรียญเปิด auto-burn (หักค่าตอนโอน) — สัญญาล็อก/presale และ router ของ DEX รองรับไม่ได้");
    }
    for (const [k, v] of Object.entries(flags)) {
        if (v) console.log("      " + RED(`เหรียญเปิด ${k} — เจ้าของยังมีอำนาจเหนือเหรียญ นักลงทุนจะเห็นเป็นความเสี่ยง`));
    }
    if (Object.values(flags).every((v) => v === false)) console.log("      ✅ standard: ไม่มี mint/pause/blacklist/auto-burn");
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

    // ── ซ้อม: สร้างเหรียญ standard ขึ้นมาเองแบบเดียวกับที่ factory สร้าง และ USDT จำลอง ──
    let tokenAddr = envAddress("TOKEN", { required: !DRY_RUN });
    let payAddr = registryAddress(reg, plan.sale.payToken);
    let mockUsdt = null;
    if (DRY_RUN) {
        const T = await ethers.getContractFactory("FactoryERC20V2");
        tokenAddr = tokenAddr || await (await T.deploy("Dry Run " + plan.symbol, plan.symbol, plan.decimals,
            ethers.parseUnits(plan.totalSupply, plan.decimals), deployer.address,
            false, true, false, false, 0, false, 0, 0)).getAddress();
        mockUsdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        payAddr = await mockUsdt.getAddress();
    }

    console.log("\n[1/4] ตรวจเหรียญ ...");
    const { decimals } = await inspectToken(tokenAddr, plan);

    // ── สัญญาล็อก ──
    const beneficiary = envAddress("BENEFICIARY", { required: !DRY_RUN }) || deployer.address;
    const start = envTime("VESTING_START", { required: !DRY_RUN, fallback: now + 86400n });
    if (start < now - 3600n && process.env.ALLOW_PAST_START !== "1") {
        throw new Error(`VESTING_START ${iso(start)} อยู่ในอดีต — ล็อกจะเริ่มนับย้อนหลัง (ตั้ง ALLOW_PAST_START=1 ถ้าตั้งใจ)`);
    }
    const tranches = plan.vesting.tranches.map((t) => ({
        amount: ethers.parseUnits(t.amount, decimals), cliffPeriods: t.cliffPeriods, releasePeriods: t.releasePeriods,
    }));
    const vestTotal = tranches.reduce((a, t) => a + t.amount, 0n);
    const period = BigInt(plan.vesting.periodSeconds);

    console.log(`\n[2/4] สัญญาล็อก ${fmt(vestTotal, decimals)} ${plan.symbol} · เริ่มนับ ${iso(start)} · ผู้รับ ${beneficiary}`);
    for (const t of plan.vesting.tranches) {
        const from = t.cliffPeriods + 1, to = t.cliffPeriods + t.releasePeriods;
        console.log(`      ${t.name.padEnd(10)} ${Number(t.amount).toLocaleString("en-US").padStart(18)} → ปลดงวดที่ ${from}–${to}`);
    }
    const vest = await deployOnce(reg, `${plan.symbol}_Vesting`, "TrancheVesting",
        [tokenAddr, beneficiary, start, period, tranches, plan.vesting.label]);
    const vesting = await ethers.getContractAt("TrancheVesting", vest.address);
    if ((await vesting.token()).toLowerCase() !== tokenAddr.toLowerCase()) throw new Error("สัญญาล็อกใน registry ผูกกับเหรียญอื่น");
    if ((await vesting.totalAllocation()) !== vestTotal) throw new Error("ยอดในสัญญาล็อกไม่ตรงแผน");

    // ── presale ──
    let sale = null;
    const capRaw = (process.env.SALE_CAP || (DRY_RUN ? "100000000000" : "")).replace(/[,_]/g, "");
    if (capRaw) {
        if (!payAddr || !(await hasCode(payAddr))) throw new Error(`ไม่พบ ${plan.sale.payToken} บนเชน`);
        const pay = await ethers.getContractAt("FactoryERC20V2", payAddr);
        const payDec = Number(await pay.decimals());
        const { num, den } = saleRate(plan.sale.priceUsd, decimals, payDec);
        const cap = ethers.parseUnits(capRaw, decimals);
        const saleStart = envTime("SALE_START", { required: !DRY_RUN, fallback: now + 60n });
        const saleEnd = envTime("SALE_END", { required: !DRY_RUN, fallback: saleStart + 30n * 86400n });
        const treasury = envAddress("SALE_TREASURY", { required: !DRY_RUN }) || deployer.address;
        const owner = envAddress("SALE_OWNER", { required: false }) || deployer.address;
        if (saleEnd <= saleStart) throw new Error("SALE_END ต้องหลัง SALE_START");

        console.log(`\n[3/4] presale ${fmt(cap, decimals)} ${plan.symbol} ที่ $${plan.sale.priceUsd} · ${iso(saleStart)} → ${iso(saleEnd)}`);
        console.log(`      ราคา: 1 ${await pay.symbol()} = ${fmt((10n ** BigInt(payDec)) * num / den, decimals)} ${plan.symbol} (rate ${num}/${den})`);
        console.log(`      เงินเข้า ${treasury} · ผู้คุม ${owner}`);
        const s = await deployOnce(reg, `${plan.symbol}_Presale`, "FixedPriceSale",
            [tokenAddr, payAddr, num, den, cap, treasury, saleStart, saleEnd, owner]);
        sale = await ethers.getContractAt("FixedPriceSale", s.address);
        if ((await sale.rateNumerator()) !== num || (await sale.rateDenominator()) !== den) {
            throw new Error("ราคาในสัญญา presale ใน registry ไม่ตรงแผน — ราคาแก้ไม่ได้ ต้อง deploy ใหม่ (ลบรายการเดิมออกจาก registry)");
        }
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

    // ── บันทึก registry ──
    const today = new Date().toISOString().slice(0, 10);
    const entries = [
        { name: `${plan.symbol}_Vesting`, address: vest.address, sourceFile: "contracts/src/launch/TrancheVesting.sol",
          description: `${plan.vesting.label} · token ${tokenAddr} · ผู้รับ ${beneficiary}` },
        ...(sale ? [{ name: `${plan.symbol}_Presale`, address: await sale.getAddress(), sourceFile: "contracts/src/launch/FixedPriceSale.sol",
          description: `Presale ${plan.symbol} ที่ $${plan.sale.priceUsd} จ่ายด้วย ${plan.sale.payToken}` }] : []),
    ].map((e) => ({
        ...e, category: "launch", compilerVersion: "0.8.24", optimizer: { enabled: true, runs: 200 },
        evmVersion: "london", viaIR: true, verified: false, deployedAt: today,
    }));
    const fresh = loadRegistry();
    for (const e of entries) {
        const old = fresh.contracts.find((c) => c.name === e.name);
        if (old && old.address === e.address) continue;          // ใช้ของเดิม — ไม่แตะรายการ
        fresh.contracts = fresh.contracts.filter((c) => c.name !== e.name).concat(e);
    }
    fresh.updated = today;
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(fresh, null, 2) + "\n");

    console.log("\n[4/4] บันทึกลง deployed-contracts.json แล้ว");
    console.log("\n=== ขั้นต่อไป (เจ้าของเหรียญทำเองจากกระเป๋าที่ถือเหรียญ) ===");
    console.log(`  1. โอน ${fmt(vestTotal, decimals)} ${plan.symbol} → ${vest.address}  (สัญญาล็อก)`);
    if (sale) console.log(`  2. โอน ${fmt(await sale.saleCap(), decimals)} ${plan.symbol} → ${await sale.getAddress()}  (presale)`);
    console.log("  3. ตรวจ:   STATUS=1 npx hardhat run scripts/launch-token.js --network tpix");
    console.log(`  4. verify: node scripts/verify-blockscout.js ${entries.map((e) => e.name).join(" ")}`);
}

main().catch((e) => {
    console.error("\nล้มเหลว:", e.message);
    process.exitCode = 1;
});
