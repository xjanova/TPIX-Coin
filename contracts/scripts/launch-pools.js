/**
 * เปิดพูลของเหรียญบน TPIX DEX: IDTC/USDT + IDTC/TPIX ที่ราคา presale แล้วล็อก LP ใน TrancheVesting
 * (ทำต่อจาก launch-token.js — ไวท์เปเปอร์ IDTC หัวข้อสภาพคล่อง: เติมพูลละ ~10 USDT ต่อฝั่ง ล็อก LP อย่างน้อย 12 เดือน)
 *
 *   ซ้อมบนเครื่อง:  npx hardhat run scripts/launch-pools.js
 *   ของจริง:       npx hardhat run scripts/launch-pools.js --network tpix   (ผ่าน deploy-pools.ps1)
 *   ดูสถานะ:       STATUS=1 npx hardhat run scripts/launch-pools.js --network tpix
 *
 * ค่าที่ตั้งผ่าน environment:
 *   LAUNCH_PLAN     ชื่อไฟล์ใน scripts/launch-plans/ (ค่าปริยาย idtc) — อ่าน plan.pools
 *   TOKEN           ที่อยู่เหรียญ (ของจริง: ต้องมี) — กระเป๋าที่ deploy ต้องถือเหรียญฝั่งนี้
 *   LP_BENEFICIARY  ผู้รับ LP เมื่อครบล็อก — แนะนำ multisig (ของจริง: ต้องมี)
 *   POOL_USDT       USDT ที่เติมพูล IDTC/USDT (หน่วยเต็ม, ค่าปริยายจากแผน) · 0 = ข้ามพูลนี้
 *   POOL_TPIX       TPIX ที่เติมพูล IDTC/TPIX (หน่วยเต็ม, ค่าปริยายจากแผน) · 0 = ข้ามพูลนี้
 *   TPIX_USD        ราคา TPIX เป็น USD สำหรับคิดฝั่ง IDTC ของพูล TPIX — ไม่ตั้ง = อ่านจากพูล WTPIX/USDT บนเชน
 *
 * ด่านกันพลาด (หยุดก่อนแตะเงินถ้าไม่ผ่าน):
 *   - เหรียญต้องตรงแผน (symbol/decimals/supply) · เชนต้องเป็น 4289
 *   - คู่ที่จะเปิดต้อง "ยังไม่มีสภาพคล่อง" และไม่มีเหรียญค้างในสัญญาคู่ — ใครเปิดคู่ก่อนด้วยราคาอื่น
 *     หรือโอนเหรียญเข้าคู่ไว้ล่วงหน้า (ทำให้ mint แรกได้ราคาเพี้ยน) = หยุด ให้ตรวจก่อน
 *   - addLiquidity ใช้ยอดขั้นต่ำ = ยอดเต็ม (คู่ใหม่ต้องได้ราคาตามที่ตั้งเป๊ะ)
 *   - LP ทั้งหมดที่ได้ โอนเข้าสัญญาล็อกในรอบเดียวกัน แล้วตรวจ isFunded()
 * รันซ้ำได้: คู่ที่มีสภาพคล่องแล้วและมีสัญญาล็อกใน registry = ข้าม (ไม่เติมซ้ำ)
 *
 * Developed by Xman Studio
 */
const fs = require("fs");
const path = require("path");
const { ethers, network, artifacts } = require("hardhat");

const ROOT = path.join(__dirname, "..");
const REGISTRY_PATH = path.join(ROOT, "deployed-contracts.json");
const DRY_RUN = network.name === "hardhat" || network.name === "localhost";
const DEADLINE_S = 20n * 60n;

const RED = (s) => `\x1b[41m\x1b[97m ${s} \x1b[0m`;
const fmt = (wei, dec) => Number(ethers.formatUnits(wei, dec)).toLocaleString("en-US", { maximumFractionDigits: 6 });
const iso = (t) => new Date(Number(t) * 1000).toISOString().replace(".000Z", "Z");

function loadPlan() {
    const name = (process.env.LAUNCH_PLAN || "idtc").replace(/[^a-z0-9_-]/gi, "");
    const file = path.join(__dirname, "launch-plans", `${name}.json`);
    if (!fs.existsSync(file)) throw new Error(`ไม่พบแผน ${file}`);
    const plan = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!plan.pools) throw new Error(`แผน ${name} ไม่มีหัวข้อ pools`);
    return plan;
}

const loadRegistry = () => JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
const registryAddress = (reg, name) => (reg.contracts || []).find((c) => c.name === name)?.address || null;

function saveEntry(e) {
    const fresh = loadRegistry();
    fresh.contracts = (fresh.contracts || []).filter((c) => c.name !== e.name).concat(e);
    fresh.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(fresh, null, 2) + "\n");
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

/** จำนวนเต็มหน่วยแบบทศนิยม ("10", "12.5") → หน่วยเล็กสุด */
function envAmount(key, fallback, decimals) {
    const raw = (process.env[key] ?? fallback ?? "").toString().trim().replace(/[,_]/g, "");
    if (!/^\d+(\.\d+)?$/.test(raw)) throw new Error(`${key} ต้องเป็นตัวเลข: ${raw}`);
    return ethers.parseUnits(raw, decimals);
}

/** "0.0000015" → { num: 15n, den: 10000000n } */
function fraction(s) {
    if (!/^\d+(\.\d+)?$/.test(s)) throw new Error(`ราคาไม่ถูกรูปแบบ: ${s}`);
    const [int, frac = ""] = s.split(".");
    const f = { num: BigInt(int + frac), den: 10n ** BigInt(frac.length) };
    if (f.num === 0n) throw new Error("ราคาต้องมากกว่า 0");
    return f;
}

const hasCode = async (addr) => !!addr && (await ethers.provider.getCode(addr)) !== "0x";

async function buildMeta(source, contractName) {
    const bi = await artifacts.getBuildInfo(`${source}:${contractName}`);
    const st = bi.input.settings;
    return {
        sourceFile: `contracts/${source}`, compilerVersion: bi.solcVersion, optimizer: st.optimizer,
        evmVersion: st.evmVersion, viaIR: !!st.viaIR, verified: false, deployedAt: new Date().toISOString().slice(0, 10),
    };
}

/**
 * คู่ต้องสะอาดก่อนเปิด: ไม่มี reserve และไม่มีเหรียญค้างในสัญญาคู่
 * @returns {Promise<{pair: string|null, live: boolean}>}
 */
async function inspectPair(factory, a, b, labels) {
    const found = await factory.getPair(a, b);
    if (found === ethers.ZeroAddress) return { pair: null, live: false };
    const pair = await ethers.getContractAt("TPIXDEXPair", found);
    const [r0, r1] = await pair.getReserves();
    const supply = await pair.totalSupply();
    if (r0 > 0n || r1 > 0n || supply > 0n) return { pair: found, live: true, reserves: [r0, r1] };
    for (const [addr, label] of [[a, labels[0]], [b, labels[1]]]) {
        const bal = await (await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", addr)).balanceOf(found);
        if (bal > 0n) throw new Error(`คู่ ${found} ยังไม่มีสภาพคล่องแต่มี ${label} ค้างอยู่ (${bal}) — mint แรกจะได้ราคาเพี้ยน หยุดไว้ก่อน`);
    }
    return { pair: found, live: false };
}

async function lockLp({ reg, plan, regName, label, lpAddr, amount, beneficiary, start }) {
    const period = BigInt(plan.vesting.periodSeconds);
    const lock = plan.pools.lpLock;
    const tranches = [{ amount, cliffPeriods: lock.cliffPeriods, releasePeriods: lock.releasePeriods }];
    const existing = registryAddress(reg, regName);
    if (!DRY_RUN && (await hasCode(existing))) throw new Error(`${regName} ${existing} มีอยู่แล้วแต่ยังมี LP ใหม่ — ตรวจ registry ก่อน (ไม่ล็อกซ้ำเงียบ ๆ)`);
    const v = await (await ethers.getContractFactory("TrancheVesting")).deploy(lpAddr, beneficiary, start, period, tranches, label);
    await v.waitForDeployment();
    const vAddr = await v.getAddress();
    if (!(await hasCode(vAddr))) throw new Error("TrancheVesting (LP): eth_getCode คืน 0x");
    if (!DRY_RUN) {
        saveEntry({ name: regName, address: vAddr, category: "launch", description: `${label} · LP ${lpAddr} · ผู้รับ ${beneficiary}`, ...(await buildMeta("src/launch/TrancheVesting.sol", "TrancheVesting")) });
    }
    const lp = await ethers.getContractAt("TPIXDEXPair", lpAddr);
    await (await lp.transfer(vAddr, amount)).wait();
    if (!(await v.isFunded())) throw new Error(`${regName}: โอน LP แล้วแต่ isFunded = false`);
    const [at] = await v.nextUnlock();
    console.log(`      ล็อก LP ${fmt(amount, 18)} → ${vAddr} · ปลดได้ ${iso(at)} ✅`);
    return vAddr;
}

async function printStatus(reg, plan) {
    for (const key of ["USDT", "TPIX"]) {
        const pairAddr = registryAddress(reg, `${plan.symbol}_PAIR_${key}`);
        const lockAddr = registryAddress(reg, `${plan.symbol}_LP_LOCK_${key}`);
        if (!pairAddr) { console.log(`\n${plan.symbol}/${key}: ยังไม่เปิด`); continue; }
        const pair = await ethers.getContractAt("TPIXDEXPair", pairAddr);
        const [[r0, r1], t0, supply] = await Promise.all([pair.getReserves(), pair.token0(), pair.totalSupply()]);
        console.log(`\n${plan.symbol}/${key} ${pairAddr}`);
        console.log(`  reserve     : token0 ${t0} = ${r0} · token1 = ${r1}`);
        if (lockAddr) {
            const v = await ethers.getContractAt("TrancheVesting", lockAddr);
            const [locked, funded, [at]] = await Promise.all([pair.balanceOf(lockAddr), v.isFunded(), v.nextUnlock()]);
            const pct = supply > 0n ? Number((locked * 10000n) / supply) / 100 : 0;
            console.log(`  LP ล็อก     : ${fmt(locked, 18)} (${pct}% ของ LP ทั้งหมด) ${funded ? "✅" : RED("ยังไม่ครบ")} · ปลด ${iso(at)} · ${lockAddr}`);
        } else {
            console.log(`  LP ล็อก     : ${RED("ไม่มีสัญญาล็อก")}`);
        }
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
    console.log(`เปิดพูล ${plan.symbol} · network ${network.name}${DRY_RUN ? " (ซ้อม)" : ""} · กระเป๋า ${deployer.address}`);
    console.log("─".repeat(72));

    let tokenAddr = envAddress("TOKEN", { required: !DRY_RUN });
    const beneficiary = envAddress("LP_BENEFICIARY", { required: !DRY_RUN }) || deployer.address;
    if (!DRY_RUN && beneficiary.toLowerCase() === deployer.address.toLowerCase()) {
        console.log(RED("LP_BENEFICIARY = กระเป๋าที่ deploy (คีย์ร้อน) — แนะนำ multisig"));
    }

    // ── สัญญา DEX: ของจริงจาก registry · ซ้อม: deploy ชุดใหม่บน hardhat ──
    let routerAddr = registryAddress(reg, "TPIXDEXRouter02");
    let factoryAddr = registryAddress(reg, "TPIXDEXFactory");
    let wtpixAddr = registryAddress(reg, "WTPIX");
    let usdtAddr = registryAddress(reg, plan.sale.payToken);
    let mock = null;
    if (DRY_RUN) {
        const wtpix = await (await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX")).deploy();
        const factory = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(deployer.address);
        const router = await (await ethers.getContractFactory("TPIXDEXRouter02")).deploy(await factory.getAddress(), await wtpix.getAddress());
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        [wtpixAddr, factoryAddr, routerAddr, usdtAddr] = await Promise.all([wtpix, factory, router, usdt].map((c) => c.getAddress()));
        await (await usdt.setBridge(deployer.address, true)).wait();
        await (await usdt.bridgeMint(deployer.address, 1000n * 10n ** 6n, ethers.id("dry-run-pools"))).wait();
        // พูลอ้างอิงราคา TPIX: 199.9 TPIX / 19.99 USDT แบบบนเชนจริง → $0.10
        await (await usdt.approve(routerAddr, ethers.MaxUint256)).wait();
        await (await router.addLiquidityETH(usdtAddr, 19_990_000n, 0, 0, deployer.address, ethers.MaxUint256, { value: ethers.parseEther("199.9") })).wait();
        tokenAddr = tokenAddr || await (await (await ethers.getContractFactory("FactoryERC20V2")).deploy("Dry Run " + plan.symbol, plan.symbol, plan.decimals,
            ethers.parseUnits(plan.totalSupply, plan.decimals), deployer.address, false, false, false, false, 0, false, 0, 0)).getAddress();
        mock = { usdt };
    }
    for (const [n, a] of [["TPIXDEXRouter02", routerAddr], ["TPIXDEXFactory", factoryAddr], ["WTPIX", wtpixAddr], [plan.sale.payToken, usdtAddr]]) {
        if (!(await hasCode(a))) throw new Error(`ไม่พบ ${n} บนเชน (${a})`);
    }
    const router = await ethers.getContractAt("TPIXDEXRouter02", routerAddr);
    const factory = await ethers.getContractAt("TPIXDEXFactory", factoryAddr);
    if ((await router.factory()).toLowerCase() !== factoryAddr.toLowerCase()) throw new Error("router.factory() ไม่ตรง registry");
    if ((await router.WETH()).toLowerCase() !== wtpixAddr.toLowerCase()) throw new Error("router.WETH() ไม่ตรง WTPIX ใน registry");

    // ── เหรียญ ──
    console.log("\n[1/4] ตรวจเหรียญและยอดในกระเป๋า ...");
    if (!(await hasCode(tokenAddr))) throw new Error(`TOKEN ${tokenAddr} ไม่มีโค้ดบนเชน`);
    const token = await ethers.getContractAt("FactoryERC20V2", tokenAddr);
    const [symbol, decimalsRaw, supply] = await Promise.all([token.symbol(), token.decimals(), token.totalSupply()]);
    const decimals = Number(decimalsRaw);
    if (symbol !== plan.symbol || decimals !== plan.decimals || supply !== ethers.parseUnits(plan.totalSupply, plan.decimals)) {
        throw new Error(`เหรียญไม่ตรงแผน: ${symbol} · ${decimals} ทศนิยม · supply ${fmt(supply, decimals)}`);
    }
    const usdt = await ethers.getContractAt("USDT_TPIX", usdtAddr);
    const usdtDec = Number(await usdt.decimals());

    // ── คำนวณยอดตามราคา presale ──
    const price = fraction(plan.sale.priceUsd);           // USD ต่อ 1 เหรียญ
    const one = 10n ** BigInt(decimals);
    const usdtIn = envAmount("POOL_USDT", plan.pools.usdt, usdtDec);
    const tpixIn = envAmount("POOL_TPIX", plan.pools.tpix, 18);
    // IDTC = USD ÷ ราคา  →  usdtIn/10^usdtDec × den/num × 10^decimals
    const idtcForUsdt = (usdtIn * price.den * one) / (price.num * 10n ** BigInt(usdtDec));

    let tpixUsd;
    if (process.env.TPIX_USD) {
        tpixUsd = fraction(process.env.TPIX_USD.trim());
    } else {
        const refPair = await factory.getPair(wtpixAddr, usdtAddr);
        if (refPair === ethers.ZeroAddress) throw new Error("ไม่มีพูล WTPIX/USDT ให้อ่านราคา TPIX — ตั้ง TPIX_USD เอง");
        const p = await ethers.getContractAt("TPIXDEXPair", refPair);
        const [[r0, r1], t0] = await Promise.all([p.getReserves(), p.token0()]);
        const [rW, rU] = t0.toLowerCase() === wtpixAddr.toLowerCase() ? [r0, r1] : [r1, r0];
        if (rW === 0n || rU === 0n) throw new Error("พูล WTPIX/USDT ว่าง — ตั้ง TPIX_USD เอง");
        tpixUsd = { num: rU * 10n ** 18n, den: rW * 10n ** BigInt(usdtDec) };   // USD ต่อ 1 TPIX
    }
    // IDTC = tpixIn/1e18 × tpixUsd ÷ ราคา × 10^decimals
    const idtcForTpix = (tpixIn * tpixUsd.num * price.den * one) / (10n ** 18n * tpixUsd.den * price.num);
    const tpixUsdText = Number(tpixUsd.num * 1_000_000n / tpixUsd.den) / 1e6;

    const pools = [
        { key: "USDT", native: false, counter: usdtAddr, counterIn: usdtIn, counterDec: usdtDec, idtcIn: idtcForUsdt, sym: "USDT" },
        { key: "TPIX", native: true, counter: wtpixAddr, counterIn: tpixIn, counterDec: 18, idtcIn: idtcForTpix, sym: "TPIX" },
    ].filter((p) => p.counterIn > 0n);
    if (!pools.length) throw new Error("POOL_USDT และ POOL_TPIX เป็น 0 ทั้งคู่ — ไม่มีอะไรให้ทำ");

    console.log(`      ราคาเปิด $${plan.sale.priceUsd} ต่อ ${plan.symbol} · TPIX = $${tpixUsdText}${process.env.TPIX_USD ? " (TPIX_USD)" : " (จากพูล WTPIX/USDT)"}`);
    for (const p of pools) console.log(`      ${plan.symbol}/${p.sym}: ${fmt(p.idtcIn, decimals)} ${plan.symbol} + ${fmt(p.counterIn, p.counterDec)} ${p.sym}`);

    const needIdtc = pools.reduce((a, p) => a + p.idtcIn, 0n);
    const [balIdtc, balUsdt, balTpix] = await Promise.all([token.balanceOf(deployer.address), usdt.balanceOf(deployer.address), ethers.provider.getBalance(deployer.address)]);
    if (balIdtc < needIdtc) throw new Error(`${plan.symbol} ในกระเป๋าไม่พอ: มี ${fmt(balIdtc, decimals)} ต้องใช้ ${fmt(needIdtc, decimals)}`);
    const pu = pools.find((p) => p.key === "USDT");
    if (pu && balUsdt < pu.counterIn) throw new Error(`USDT ในกระเป๋าไม่พอ: มี ${fmt(balUsdt, usdtDec)} ต้องใช้ ${fmt(pu.counterIn, usdtDec)}`);
    const pt = pools.find((p) => p.key === "TPIX");
    if (pt && balTpix < pt.counterIn) throw new Error(`TPIX ในกระเป๋าไม่พอ: มี ${fmt(balTpix, 18)} ต้องใช้ ${fmt(pt.counterIn, 18)}`);

    // ── ตรวจคู่ทุกตัวก่อนแตะเงิน ──
    console.log("\n[2/4] ตรวจคู่บน DEX ...");
    for (const p of pools) {
        p.state = await inspectPair(factory, tokenAddr, p.counter, [plan.symbol, p.sym]);
        const lockName = `${plan.symbol}_LP_LOCK_${p.key}`;
        if (p.state.live) {
            if (!DRY_RUN && (await hasCode(registryAddress(reg, lockName)))) {
                console.log(`      ${plan.symbol}/${p.sym} ${p.state.pair} เปิดแล้วและล็อก LP แล้ว — ข้าม`);
                p.skip = true;
                continue;
            }
            throw new Error(`${plan.symbol}/${p.sym} ${p.state.pair} มีสภาพคล่องอยู่แล้วโดยไม่มีสัญญาล็อกของเรา — มีคนเปิดคู่ก่อน ตรวจราคาก่อนทำอะไรต่อ`);
        }
        console.log(`      ${plan.symbol}/${p.sym}: ${p.state.pair ? `คู่ ${p.state.pair} ว่างอยู่` : "ยังไม่มีคู่ (router สร้างให้)"} ✓`);
    }
    const todo = pools.filter((p) => !p.skip);
    if (!todo.length) return printStatus(reg, plan);

    // ── เติมสภาพคล่อง ──
    console.log("\n[3/4] เติมสภาพคล่อง ...");
    const now = BigInt((await ethers.provider.getBlock("latest")).timestamp);
    const allowance = await token.allowance(deployer.address, routerAddr);
    const idtcNeeded = todo.reduce((a, p) => a + p.idtcIn, 0n);
    if (allowance < idtcNeeded) await (await token.approve(routerAddr, idtcNeeded)).wait();
    for (const p of todo) {
        const deadline = now + DEADLINE_S;
        if (p.native) {
            await (await router.addLiquidityETH(tokenAddr, p.idtcIn, p.idtcIn, p.counterIn, deployer.address, deadline, { value: p.counterIn })).wait();
        } else {
            if ((await usdt.allowance(deployer.address, routerAddr)) < p.counterIn) await (await usdt.approve(routerAddr, p.counterIn)).wait();
            await (await router.addLiquidity(tokenAddr, p.counter, p.idtcIn, p.counterIn, p.idtcIn, p.counterIn, deployer.address, deadline)).wait();
        }
        p.pair = await factory.getPair(tokenAddr, p.counter);
        const lp = await ethers.getContractAt("TPIXDEXPair", p.pair);
        p.lp = await lp.balanceOf(deployer.address);
        if (p.lp === 0n) throw new Error(`${plan.symbol}/${p.sym}: ไม่ได้ LP กลับมา`);
        console.log(`      ${plan.symbol}/${p.sym} ${p.pair} · ได้ LP ${fmt(p.lp, 18)}`);
        if (!DRY_RUN) saveEntry({ name: `${plan.symbol}_PAIR_${p.key}`, address: p.pair, category: "dex", sourceFile: "contracts/src/dex/amm/TPIXDEXPair.sol", description: `TPIX DEX pair ${plan.symbol}/${p.sym}`, verified: false, deployedAt: new Date().toISOString().slice(0, 10) });
    }

    // ── ล็อก LP ──
    console.log(`\n[4/4] ล็อก LP ${plan.pools.lpLock.cliffPeriods} งวด + ปลด ${plan.pools.lpLock.releasePeriods} งวด (งวดละ ${plan.vesting.periodSeconds} วินาที) · ผู้รับ ${beneficiary}`);
    for (const p of todo) {
        p.lock = await lockLp({
            reg, plan, regName: `${plan.symbol}_LP_LOCK_${p.key}`, label: `${plan.symbol}/${p.sym} LP — ${plan.pools.lpLock.label}`,
            lpAddr: p.pair, amount: p.lp, beneficiary, start: now,
        });
    }

    if (DRY_RUN) {
        console.log("\nซ้อมซื้อ–ขายกับพูลที่เปิด ...");
        const p = todo.find((x) => x.key === "USDT");
        if (p) {
            const before = await token.balanceOf(deployer.address);
            await (await router.swapExactTokensForTokens(10n ** 6n, 0, [usdtAddr, tokenAddr], deployer.address, ethers.MaxUint256)).wait();
            const got = (await token.balanceOf(deployer.address)) - before;
            console.log(`      ซื้อด้วย 1 USDT ได้ ${fmt(got, decimals)} ${plan.symbol} (ราคา presale ให้ ${fmt(one * price.den / price.num, decimals)})`);
            await (await token.approve(routerAddr, got)).wait();
            const u0 = await mock.usdt.balanceOf(deployer.address);
            await (await router.swapExactTokensForTokens(got, 0, [tokenAddr, usdtAddr], deployer.address, ethers.MaxUint256)).wait();
            console.log(`      ขายคืนได้ ${fmt((await mock.usdt.balanceOf(deployer.address)) - u0, usdtDec)} USDT ✅`);
            const v = await ethers.getContractAt("TrancheVesting", p.lock);
            const [at] = await v.nextUnlock();
            await network.provider.send("evm_setNextBlockTimestamp", [Number(at) - 60]);
            await network.provider.send("evm_mine");
            let early = false;
            try { await (await v.release()).wait(); } catch { early = true; }
            if (!early) throw new Error("ปลด LP ได้ก่อนเวลา");
            await network.provider.send("evm_setNextBlockTimestamp", [Number(at)]);
            await (await v.release()).wait();
            console.log(`      LP ปลดไม่ได้ก่อน ${iso(at)} และปลดได้เมื่อถึงเวลา ✅`);
        }
        console.log("\nซ้อมผ่านหมด — ของจริงใช้ --network tpix พร้อม TOKEN / LP_BENEFICIARY");
        return;
    }

    console.log("\n=== เสร็จแล้ว — ตั้งค่าที่หน้าเว็บ IDTC (หลังบ้าน → ตั้งค่า → ที่อยู่สัญญา) ===");
    for (const p of todo) console.log(`  pair_${p.key.toLowerCase()} = ${p.pair}   · ล็อก LP ${p.lock}`);
    console.log("  ตรวจ:   STATUS=1 npx hardhat run scripts/launch-pools.js --network tpix");
    console.log(`  verify: node scripts/verify-blockscout.js ${todo.map((p) => `${plan.symbol}_LP_LOCK_${p.key}`).join(" ")}`);
}

main().catch((e) => {
    console.error("\nล้มเหลว:", e.message);
    process.exitCode = 1;
});
