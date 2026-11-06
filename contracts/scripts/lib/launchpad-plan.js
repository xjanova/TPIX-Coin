/**
 * Turn a launch plan (scripts/launch-plans/<name>.json → "launchpad") into LaunchpadFactory.createLaunch()
 * arguments, and check the factory's anti-rug rules before anything is sent.
 *
 * Pure functions (BigInt in, BigInt out) — no chain access, so test/LaunchpadPlan.test.js covers every rule.
 * The numbers mirror src/launch/LaunchpadFactory.sol; the factory still checks them again on chain.
 *
 * Developed by Xman Studio
 */
const { parseUnits } = require("ethers");

const DAY = 86_400n;
const BPS = 10_000n;
const MIN_LP_LOCK_DAYS = 180n;
const MIN_POOL_SHARE_BPS = 5_000n;
const MIN_LOCKED_SUPPLY_BPS = 8_000n;
const MAX_BAND_BPS = 2_000n;
const MAX_TRANCHES = 12;

class PlanError extends Error {}

const gcd = (a, b) => (b === 0n ? a : gcd(b, a % b));

/**
 * "0.0000015" USD per token → tokens out = pay × num ÷ den, both in smallest units.
 * 1 pay unit (10^-payDec USD) buys 10^tokenDec / (price × 10^payDec) token units.
 */
function priceToRate(priceUsd, tokenDecimals, payDecimals) {
    const s = String(priceUsd).trim();
    if (!/^\d+(\.\d+)?$/.test(s)) throw new PlanError(`ราคาไม่ถูกต้อง: ${priceUsd}`);
    const [whole, frac = ""] = s.split(".");
    const priceNum = BigInt(whole + frac); // price = priceNum / 10^frac.length
    if (priceNum === 0n) throw new PlanError("ราคาต้องมากกว่า 0");
    let num = 10n ** BigInt(tokenDecimals) * 10n ** BigInt(frac.length);
    let den = priceNum * 10n ** BigInt(payDecimals);
    const g = gcd(num, den);
    num /= g;
    den /= g;
    return { num, den };
}

function units(value, decimals, label) {
    const s = String(value ?? "").trim();
    if (!/^\d+(\.\d+)?$/.test(s)) throw new PlanError(`${label} ไม่ถูกต้อง: ${value}`);
    try {
        return parseUnits(s, decimals);
    } catch {
        throw new PlanError(`${label} มีทศนิยมเกิน ${decimals} ตำแหน่ง: ${value}`);
    }
}

/** TrancheVesting.vestedAmount(timestamp) — same integer maths */
function vestedAt(vesting, timestamp) {
    let total = 0n;
    for (const t of vesting.tranches) {
        const cliffEnd = BigInt(vesting.start) + BigInt(t.cliffPeriods) * BigInt(vesting.period);
        if (BigInt(timestamp) <= cliffEnd) continue;
        const elapsed = (BigInt(timestamp) - cliffEnd) / BigInt(vesting.period);
        total += elapsed >= BigInt(t.releasePeriods) ? t.amount : (t.amount * elapsed) / BigInt(t.releasePeriods);
    }
    return total;
}

/** share of the supply in the sale, the reserve and vesting still locked when the LP unlocks (LaunchpadFactory._checkLocked) */
function lockedBps(params, vesting, totalSupply) {
    let locked = params.saleCap + params.feederReserve;
    if (vesting.tranches.length > 0) {
        const total = vesting.tranches.reduce((a, t) => a + t.amount, 0n);
        locked += total - vestedAt(vesting, params.lpUnlockTime);
    }
    return (locked * BPS) / totalSupply;
}

/**
 * @param plan       the whole plan file (needs symbol, decimals, totalSupply, sale.priceUsd, launchpad; vesting optional)
 * @param opts       { token, saleStart (unix BigInt), beneficiary, projectTreasury, payDecimals, now (unix BigInt), seedUsdt? }
 * @returns          { params, vesting, tokensNeeded, seedQuote, minPurchase, maxPerWallet, lockedBps, summary }
 */
function buildLaunch(plan, opts) {
    const lp = plan.launchpad;
    if (!lp) throw new PlanError(`แผน ${plan.symbol} ไม่มีหัวข้อ launchpad`);
    const dec = Number(plan.decimals);
    const payDec = Number(opts.payDecimals);
    if (!Number.isInteger(dec) || !Number.isInteger(payDec)) throw new PlanError("decimals ไม่ถูกต้อง");

    const { num, den } = priceToRate(plan.sale?.priceUsd, dec, payDec);
    const saleCap = units(lp.saleCap, dec, "saleCap");
    const feederReserve = units(lp.feederReserve, dec, "feederReserve");
    if (saleCap === 0n) throw new PlanError("saleCap ต้องมากกว่า 0");
    if (feederReserve === 0n) throw new PlanError("feederReserve ต้องมากกว่า 0");

    const durationDays = BigInt(lp.durationDays ?? 0);
    if (durationDays <= 0n) throw new PlanError("durationDays ต้องมากกว่า 0");
    const lockDays = BigInt(lp.lpLockDaysAfterEnd ?? 0);
    if (lockDays < MIN_LP_LOCK_DAYS) throw new PlanError(`ล็อก LP หลังจบการขายต้องอย่างน้อย ${MIN_LP_LOCK_DAYS} วัน (ตั้งไว้ ${lockDays})`);

    const poolShareBps = BigInt(lp.poolShareBps ?? 0);
    if (poolShareBps < MIN_POOL_SHARE_BPS || poolShareBps > BPS) throw new PlanError(`poolShareBps ต้องอยู่ระหว่าง ${MIN_POOL_SHARE_BPS}–${BPS} (ตั้งไว้ ${poolShareBps})`);
    const bandBps = BigInt(lp.bandBps ?? 0);
    if (bandBps > MAX_BAND_BPS) throw new PlanError(`bandBps เกิน ${MAX_BAND_BPS}`);

    const start = BigInt(opts.saleStart);
    if (start <= BigInt(opts.now)) throw new PlanError("วันเริ่มขายต้องอยู่ในอนาคต");
    const end = start + durationDays * DAY;
    const lpUnlockTime = end + lockDays * DAY;

    const minFeed = units(lp.minFeedUsdt ?? "1", payDec, "minFeedUsdt");
    if (minFeed === 0n) throw new PlanError("minFeedUsdt ต้องมากกว่า 0");
    const seedQuote = units(opts.seedUsdt ?? lp.seedUsdt ?? "0", payDec, "seedUsdt");
    const minPurchase = units(lp.minPurchaseUsdt ?? "0", payDec, "minPurchaseUsdt");
    const maxPerWallet = units(lp.maxPerWallet ?? "0", dec, "maxPerWallet");

    const params = {
        token: opts.token,
        rateNumerator: num,
        rateDenominator: den,
        saleCap,
        feederReserve,
        startTime: start,
        endTime: end,
        poolShareBps: Number(poolShareBps),
        bandBps: Number(bandBps),
        lpUnlockTime,
        projectTreasury: opts.projectTreasury,
        minFeed,
        seedQuote,
    };

    const tranches = (plan.vesting?.tranches || []).map((t, i) => {
        const amount = units(t.amount, dec, `vesting.tranches[${i}].amount`);
        if (amount === 0n || !(t.releasePeriods >= 1)) throw new PlanError(`vesting ก้อนที่ ${i + 1} ไม่ถูกต้อง`);
        return { amount, cliffPeriods: Number(t.cliffPeriods), releasePeriods: Number(t.releasePeriods) };
    });
    if (tranches.length > MAX_TRANCHES) throw new PlanError(`vesting มีได้ไม่เกิน ${MAX_TRANCHES} ก้อน`);
    const vesting = tranches.length
        ? { beneficiary: opts.beneficiary, start, period: BigInt(plan.vesting.periodSeconds), tranches, label: plan.vesting.label || plan.symbol }
        : { beneficiary: "0x0000000000000000000000000000000000000000", start: 0n, period: 0n, tranches: [], label: "" };
    if (tranches.length && !(vesting.period > 0n)) throw new PlanError("vesting.periodSeconds ต้องมากกว่า 0");

    const totalSupply = units(plan.totalSupply, dec, "totalSupply");
    const vestTotal = tranches.reduce((a, t) => a + t.amount, 0n);
    const tokensNeeded = saleCap + feederReserve + vestTotal;
    if (tokensNeeded > totalSupply) throw new PlanError("เหรียญที่ต้องใช้มากกว่าซัพพลายทั้งหมด");
    const locked = lockedBps(params, vesting, totalSupply);
    if (locked < MIN_LOCKED_SUPPLY_BPS) {
        throw new PlanError(`ล็อกได้แค่ ${Number(locked) / 100}% ของซัพพลายตอน LP ปลด — ต้องอย่างน้อย ${Number(MIN_LOCKED_SUPPLY_BPS) / 100}% (ลด lpLockDaysAfterEnd หรือเพิ่ม saleCap/feederReserve)`);
    }

    return {
        params,
        vesting,
        tokensNeeded,
        seedQuote,
        minPurchase,
        maxPerWallet,
        lockedBps: locked,
        freeAfter: totalSupply - tokensNeeded,
        totalSupply,
    };
}

module.exports = { PlanError, priceToRate, vestedAt, lockedBps, buildLaunch, DAY };
