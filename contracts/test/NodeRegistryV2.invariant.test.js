const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { setBalance, setCode, takeSnapshot } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * NodeRegistryV2 — randomized invariant test (seeded, reproducible).
 *
 * Many actors register / claim / exit / withdraw-after-slash while the owner
 * slashes, changes uptime, tier terms, reward shares, APR caps, pause and the KYC
 * contract, funders top up the pool (fundRewardPool, plain receive(), forced ETH),
 * anyone advances the reward year, and time jumps from 1 s to 200 days.
 *
 * A shadow model mirrors the contract's integer math and predicts, for every
 * call, whether it must succeed or revert. After EVERY step it checks:
 *   - exact differential state: balance, totalStaked, distributed, funded,
 *     active counts, every node's status/stake and pendingReward()
 *   - solvency: balance >= totalStaked (= Σ stake of Active + Slashed nodes)
 *   - conservation: balance == Σ deposits − Σ principal returned − Σ rewards paid
 *                              + Σ funding (incl. forced ETH)
 *   - earned bound (independent of the accumulator): each actor's rewards
 *     paid + pending <= ∫ minStake × aprCap(t) / year over its active time,
 *     and Σ rewards <= ∫ emission(t) — nobody gets more than principal + earned
 *   - liveness: every Active node past its unlock can exit, every Slashed node
 *     can withdraw, every address can claim — whatever the owner configured
 * Each seed ends by unlocking everyone, funding the pool and draining it:
 * every actor must get back exactly deposits − slashed.
 *
 *   FUZZ_SEEDS=1,2,3,4,5 FUZZ_STEPS=500 npx hardhat test test/NodeRegistryV2.invariant.test.js
 */
const SEEDS = (process.env.FUZZ_SEEDS || "101,202").split(",").map((s) => Number(s.trim()));
const STEPS = Number(process.env.FUZZ_STEPS || 150);

const E18 = 10n ** 18n;
const BPS = 10000n;
const YEAR = 365n * 86400n;
const DAY = 86400n;
const EMISSION = [600_000_000n * E18, 500_000_000n * E18, 300_000_000n * E18];
const S = { INACTIVE: 0, ACTIVE: 1, SLASHED: 2 };
const TIERS = 4;

// runtime code for fake KYC contracts (london-safe, no PUSH0)
const KYC_YES = "0x600160005260206000f3";   // returns abi.encode(true)
const KYC_NO = "0x600060005260206000f3";    // returns abi.encode(false)
const KYC_REVERT = "0x60006000fd";          // reverts

function mulberry32(a) {
    return function () {
        a |= 0; a = (a + 0x6d2b79f5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
const min = (a, b) => (a < b ? a : b);

class Model {
    constructor(t0) {
        const mk = (minStake, maxNodes, lockDays, slash, share, cap) => ({
            minStake, maxNodes, lockDays, slash, share, cap,
            active: 0n, acc: 0n, last: t0,
            capN: 0n,  // ∫ minStake·capBps dt   (divide by BPS·YEAR) — independent earned bound
            emN: 0n,   // ∫ rps·share dt          (divide by BPS)      — emission bound
        });
        this.tiers = [
            mk(1_000_000n * E18, 100n, 90n, 1000n, 3500n, 1200n),
            mk(100_000n * E18, 500n, 30n, 500n, 3000n, 900n),
            mk(10_000n * E18, 0n, 7n, 0n, 1500n, 600n),
            mk(10_000_000n * E18, 21n, 180n, 1500n, 2000n, 2000n),
        ];
        this.boundLast = t0;
        this.start = t0;
        this.year = 0n;
        this.oracle = "0x0000000000000000000000000000000000000000";
        this.rps = EMISSION[0] / YEAR;
        this.pool = 1_400_000_000n * E18;
        this.distributed = 0n;
        this.funded = 0n;
        this.totalStaked = 0n;
        this.balance = 0n;
        this.paused = false;
        this.kyc = "none";
        this.nodes = new Map();
        this.acct = new Map();
    }
    node(a) {
        if (!this.nodes.has(a)) this.nodes.set(a, { status: S.INACTIVE, tier: 0, staked: 0n, unlockAt: 0n, uptime: 0n, debt: 0n, pending: 0n, slashCap: 0n, capStart: 0n });
        return this.nodes.get(a);
    }
    acc(a) {
        if (!this.acct.has(a)) this.acct.set(a, { deposited: 0n, back: 0n, rewards: 0n, slashed: 0n, boundN: 0n });
        return this.acct.get(a);
    }
    // ── independent bounds, integrated with the parameters in force ──
    advance(ts) {
        if (ts <= this.boundLast) return;
        const dt = ts - this.boundLast;
        for (const tc of this.tiers) {
            tc.capN += tc.minStake * tc.cap * dt;
            tc.emN += this.rps * tc.share * dt;
        }
        this.boundLast = ts;
    }
    // ── mirror of the contract ──
    perNode(t, n) {
        if (n === 0n || this.rps === 0n) return 0n;
        const tc = this.tiers[t];
        if (tc.share === 0n) return 0n;
        const tierPerSec = (this.rps * tc.share) / BPS;
        const share = (tierPerSec * E18) / n;
        const cap = (tc.minStake * tc.cap * E18) / (BPS * YEAR);
        return min(share, cap);
    }
    sync(t, ts) {
        const tc = this.tiers[t];
        if (ts <= tc.last) return;
        const r = this.perNode(t, tc.active);
        if (r > 0n) tc.acc += r * (ts - tc.last);
        tc.last = ts;
    }
    syncAll(ts) { for (let t = 0; t < TIERS; t++) this.sync(t, ts); }
    settle(a, ts) {
        const n = this.node(a);
        if (n.status !== S.ACTIVE) return 0n;
        this.sync(n.tier, ts);
        const acc = this.tiers[n.tier].acc;
        let earned = 0n;
        if (acc > n.debt) {
            earned = (((acc - n.debt) / E18) * n.uptime) / BPS;
            n.pending += earned;
        }
        n.debt = acc;
        return earned;
    }
    avail() {
        const free = this.balance > this.totalStaked ? this.balance - this.totalStaked : 0n;
        const left = this.pool > this.distributed ? this.pool - this.distributed : 0n;
        return min(free, left);
    }
    payout(a) {
        const n = this.node(a);
        if (n.pending === 0n) return 0n;
        const amt = min(n.pending, this.avail());
        if (amt === 0n) return 0n;
        n.pending -= amt;
        this.distributed += amt;
        this.balance -= amt;
        this.acc(a).rewards += amt;
        return amt;
    }
    closeLife(a) {
        const n = this.node(a);
        this.acc(a).boundN += this.tiers[n.tier].capN - n.capStart;
    }
    pendingView(a, ts) {
        const n = this.node(a);
        let owed = n.pending;
        if (n.status !== S.ACTIVE) return owed;
        const tc = this.tiers[n.tier];
        let acc = tc.acc;
        if (ts > tc.last) acc += this.perNode(n.tier, tc.active) * (ts - tc.last);
        if (acc > n.debt) owed += (((acc - n.debt) / E18) * n.uptime) / BPS;
        return owed;
    }
    // bound numerator (scaled by BPS·YEAR) for an actor at time ts (bounds already advanced to ts)
    boundN(a) {
        const n = this.node(a);
        let b = this.acc(a).boundN;
        if (n.status === S.ACTIVE) b += this.tiers[n.tier].capN - n.capStart;
        return b;
    }
}

describe("NodeRegistryV2 — randomized invariants", function () {
    this.timeout(0);
    let snap;
    before(async function () { snap = await takeSnapshot(); });
    after(async function () { await snap.restore(); });

    for (const seed of SEEDS) {
        it(`seed ${seed}: ${STEPS} random steps keep solvency, bounds and liveness`, async function () {
            const local = await takeSnapshot();
            try {
                await runSeed(seed);
            } finally {
                await local.restore();
            }
        });
    }
});

async function runSeed(seed) {
    const rnd = mulberry32(seed);
    const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
    const chance = (p) => rnd() < p;

    const signers = await ethers.getSigners();
    const [owner, funder] = signers;
    const eoas = signers.slice(2, 8);
    for (const s of [owner, funder, ...eoas]) await setBalance(s.address, 10n ** 9n * E18 * 10n);

    const Registry = await ethers.getContractFactory("NodeRegistryV2");
    const registry = await Registry.deploy();
    await registry.waitForDeployment();
    const regAddr = await registry.getAddress();
    const Probe = await ethers.getContractFactory("RegistryReentrancyProbe");
    const probe = await Probe.deploy(regAddr);
    await probe.waitForDeployment();
    const probeAddr = await probe.getAddress();
    await setBalance(probeAddr, 0n);

    const kycAddrs = {
        yes: "0x00000000000000000000000000000000000c0de1",
        no: "0x00000000000000000000000000000000000c0de2",
        revert: "0x00000000000000000000000000000000000c0de3",
    };
    await setCode(kycAddrs.yes, KYC_YES);
    await setCode(kycAddrs.no, KYC_NO);
    await setCode(kycAddrs.revert, KYC_REVERT);

    const deployBlock = await ethers.provider.getBlock("latest");
    const m = new Model(BigInt(deployBlock.timestamp));
    let now = BigInt(deployBlock.timestamp);
    // actors: 6 EOAs + 1 contract operator that tries reentrancy (never slashed: it has no withdrawSlashed)
    const actors = [...eoas.map((s) => ({ addr: s.address, signer: s, probe: false })), { addr: probeAddr, signer: eoas[0], probe: true }];
    const iface = registry.interface;
    let forcedEth = 0n;
    const stats = { ok: 0, reverted: 0, actions: {} };

    const ctx = () => `seed ${seed} step ${stepNo}`;
    let stepNo = 0;

    // eth_call timestamp probe: creation code that returns block.timestamp
    async function callTs() {
        const r = await ethers.provider.call({ data: "0x4260005260206000f3" });
        return BigInt(r);
    }

    async function exec(label, send, { dt = 1n } = {}) {
        const ts = now + dt;
        await network.provider.send("evm_setNextBlockTimestamp", [Number(ts)]);
        const before = await ethers.provider.getBlockNumber();
        let ok = true, receipt = null, err = null;
        try {
            const tx = await send({ gasLimit: 3_000_000 });
            receipt = await tx.wait();
        } catch (e) { ok = false; err = e; }
        const after = await ethers.provider.getBlockNumber();
        if (after === before + 1) now = ts;
        else if (after !== before) throw new Error(`${ctx()} ${label}: mined ${after - before} blocks`);
        stats.actions[label] = stats.actions[label] || { ok: 0, rev: 0 };
        stats.actions[label][ok ? "ok" : "rev"]++;
        ok ? stats.ok++ : stats.reverted++;
        return { ok, receipt, err, ts };
    }

    function events(receipt, name) {
        if (!receipt) return [];
        return receipt.logs
            .filter((l) => l.address.toLowerCase() === regAddr.toLowerCase())
            .map((l) => { try { return iface.parseLog(l); } catch { return null; } })
            .filter((e) => e && e.name === name);
    }

    function expectOutcome(label, predicted, res) {
        if (predicted !== res.ok) {
            const reason = res.err ? (res.err.shortMessage || res.err.message || "").slice(0, 300) : "succeeded";
            throw new Error(`${ctx()} ${label}: predicted ${predicted ? "success" : "revert"} but got ${res.ok ? "success" : "revert"} (${reason})`);
        }
    }

    // ── actions ───────────────────────────────────────────────────────────
    async function doRegister(a) {
        const t = Math.floor(rnd() * TIERS);
        const tc = m.tiers[t];
        const kind = rnd();
        const value = kind < 0.94 ? tc.minStake : kind < 0.97 ? tc.minStake + 1n : tc.minStake - 1n;
        const epLen = chance(0.9) ? 17 : pick([1, 100, 0, 101]);
        const ep = "x".repeat(epLen);
        const n = m.node(a.addr);
        const predicted = !m.paused && n.status === S.INACTIVE && n.pending === 0n && value === tc.minStake &&
            epLen >= 1 && epLen <= 100 && !(tc.maxNodes > 0n && tc.active >= tc.maxNodes) &&
            (t !== 3 || m.kyc === "yes");
        const res = await exec("register", (o) => a.probe
            ? probe.connect(a.signer).register(t, ep, { ...o, value })
            : registry.connect(a.signer).registerNode(t, ep, { ...o, value }));
        expectOutcome(`register(${t})`, predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        m.sync(t, res.ts);
        // มี uptime oracle = เริ่ม 0% จนกว่าจะพิสูจน์ว่ารันจริง · ไม่มี = 100%
        const uptime = m.oracle === ethers.ZeroAddress ? BPS : 0n;
        Object.assign(n, { status: S.ACTIVE, tier: t, staked: value, unlockAt: res.ts + tc.lockDays * DAY, uptime, debt: tc.acc, pending: 0n, slashCap: tc.slash, capStart: tc.capN });
        tc.active++;
        m.totalStaked += value;
        m.balance += value;
        m.acc(a.addr).deposited += value;
    }

    async function doClaim(a) {
        const res = await exec("claim", (o) => a.probe ? probe.connect(a.signer).claim(o) : registry.connect(a.signer).claimRewards(o));
        expectOutcome("claim", true, res);
        m.advance(res.ts);
        const earned = m.settle(a.addr, res.ts);
        const paid = m.payout(a.addr);
        checkEvents(res.receipt, a.addr, earned, paid);
        if (paid > 0n) stats.paidClaims = (stats.paidClaims || 0) + 1;
        if (m.node(a.addr).pending > 0n) stats.shortClaims = (stats.shortClaims || 0) + 1;  // pool could not cover
    }

    function checkEvents(receipt, addr, earned, paid) {
        const acc = events(receipt, "RewardAccrued").filter((e) => e.args[0] === addr);
        const clm = events(receipt, "RewardClaimed").filter((e) => e.args[0] === addr);
        expect(acc.reduce((s, e) => s + e.args[1], 0n), `${ctx()} accrued`).to.equal(earned);
        expect(clm.reduce((s, e) => s + e.args[1], 0n), `${ctx()} claimed`).to.equal(paid);
    }

    async function doExit(a) {
        const n = m.node(a.addr);
        const predicted = n.status === S.ACTIVE && now + 1n >= n.unlockAt;
        const res = await exec("exit", (o) => a.probe ? probe.connect(a.signer).exit(o) : registry.connect(a.signer).deregisterNode(o));
        expectOutcome("deregister", predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        const earned = m.settle(a.addr, res.ts);
        const paid = m.payout(a.addr);
        checkEvents(res.receipt, a.addr, earned, paid);
        const stake = n.staked;
        m.closeLife(a.addr);
        n.status = S.INACTIVE; n.staked = 0n;
        m.sync(n.tier, res.ts);
        m.tiers[n.tier].active--;
        m.totalStaked -= stake;
        m.balance -= stake;
        m.acc(a.addr).back += stake;
        const ev = events(res.receipt, "NodeDeregistered");
        expect(ev.length, ctx()).to.equal(1);
        expect(ev[0].args[1], ctx()).to.equal(stake);
    }

    async function doWithdrawSlashed(a) {
        if (a.probe) return;
        const n = m.node(a.addr);
        const predicted = n.status === S.SLASHED && n.staked > 0n;
        const res = await exec("withdrawSlashed", (o) => registry.connect(a.signer).withdrawSlashedStake(o));
        expectOutcome("withdrawSlashed", predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        const stake = n.staked;
        n.staked = 0n; n.status = S.INACTIVE;
        m.totalStaked -= stake; m.balance -= stake;
        m.acc(a.addr).back += stake;
    }

    async function doSlash(a) {
        if (a.probe) return;
        const n = m.node(a.addr);
        const byOwner = !chance(0.1);
        const predicted = byOwner && n.status === S.ACTIVE;
        const res = await exec("slash", (o) => registry.connect(byOwner ? owner : a.signer).slashNode(a.addr, "fuzz", o));
        expectOutcome("slash", predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        m.settle(a.addr, res.ts);
        const tc = m.tiers[n.tier];
        const pct = min(tc.slash, n.slashCap);
        const amt = (n.staked * pct) / BPS;
        n.staked -= amt; n.status = S.SLASHED;
        m.totalStaked -= amt;
        m.closeLife(a.addr);
        m.sync(n.tier, res.ts);
        tc.active--;
        m.pool += amt;
        m.acc(a.addr).slashed += amt;
        expect(events(res.receipt, "NodeSlashed")[0].args[1], ctx()).to.equal(amt);
    }

    // ผู้เรียก: owner · oracle (ตามที่อยู่ที่ตั้งไว้ล่าสุด — อาจถูกถอดแล้ว) · คนนอก
    function uptimeCaller(a) {
        const r = rnd();
        if (r < 0.5) return owner;
        if (r < 0.9) return pick(eoas);
        return a.signer;
    }
    const mayReportUptime = (s) => s.address === owner.address ||
        (m.oracle !== ethers.ZeroAddress && s.address === m.oracle);

    async function doUptime(a) {
        const n = m.node(a.addr);
        const u = BigInt(pick([0, 5000, 9000, 9999, 10000, 10001]));
        const who = uptimeCaller(a);
        const predicted = mayReportUptime(who) && n.status === S.ACTIVE && u <= BPS;
        const res = await exec("uptime", (o) => registry.connect(who).updateUptime(a.addr, u, o));
        expectOutcome("uptime", predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        m.settle(a.addr, res.ts);
        n.uptime = u;
    }

    async function doUptimeBatch() {
        const who = uptimeCaller(actors[0]);
        const size = pick([0, 1, 2, 3, actors.length]);
        const list = Array.from({ length: size }, () => pick(actors));
        const ups = list.map(() => BigInt(pick([0, 3000, 10000, 10000, 10001])));
        const predicted = mayReportUptime(who) && ups.every((u) => u <= BPS);
        const res = await exec("uptimeBatch", (o) => registry.connect(who).updateUptimeBatch(list.map((a) => a.addr), ups, o));
        expectOutcome("updateUptimeBatch", predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        // ทีละรายการตามลำดับ (ที่อยู่ซ้ำในชุด = ค่าหลังสุดชนะ) · โหนดที่ไม่ active ถูกข้าม
        list.forEach((a, i) => {
            const n = m.node(a.addr);
            if (n.status !== S.ACTIVE) return;
            m.settle(a.addr, res.ts);
            n.uptime = ups[i];
        });
    }

    async function doFund() {
        // mostly small top-ups so the pool is often short of what is owed (partial payouts,
        // exits with IOUs, re-register blocked by pendingUnclaimed) — the risky regime
        const amount = pick([0n, 1n, E18, 100n * E18, 1000n * E18, 1000n * E18, 10_000n * E18, 10_000n * E18, 50_000n * E18, 100_000n * E18, 1_000_000n * E18]);
        const way = rnd();
        if (way < 0.1) {
            // forced ETH (selfdestruct-style): no receive(), no event, still pool money
            if (amount === 0n) return;
            const bal = await ethers.provider.getBalance(regAddr);
            await setBalance(regAddr, bal + amount);
            m.balance += amount;
            forcedEth += amount;
            return;
        }
        const plain = way < 0.5;
        const res = await exec(plain ? "fundPlain" : "fund", (o) => plain
            ? funder.sendTransaction({ to: regAddr, value: amount, ...o })
            : registry.connect(funder).fundRewardPool({ ...o, value: amount }));
        expectOutcome(plain ? "receive" : "fundRewardPool", plain || amount > 0n, res);
        if (!res.ok) return;
        m.advance(res.ts);
        m.balance += amount;
        m.funded += amount;
    }

    async function doAdvanceYear() {
        const caller = pick([owner, funder, ...eoas]);
        const ts = now + 1n;
        const predicted = m.year < 3n && ts >= m.start + (m.year + 1n) * YEAR;
        const res = await exec("advanceYear", (o) => registry.connect(caller).advanceRewardYear(o));
        expectOutcome("advanceRewardYear", predicted, res);
        if (!res.ok) return;
        m.advance(res.ts);
        m.syncAll(res.ts);
        m.year++;
        m.rps = m.year < 3n ? EMISSION[Number(m.year)] / YEAR : 0n;
    }

    async function doOwnerConfig() {
        const byOwner = !chance(0.08);
        const who = byOwner ? owner : pick(eoas);
        const r = rnd();
        if (r < 0.35) {
            const t = Math.floor(rnd() * TIERS);
            const tc = m.tiers[t];
            const minStake = chance(0.6) ? tc.minStake : pick([1n, E18, 1000n * E18, 10_000n * E18, 1_000_000n * E18, 3n * 10n ** 25n]);
            const maxNodes = BigInt(pick([0, 1, 2, 3, 5, 100]));
            const lockDays = BigInt(pick([0, 1, 7, 30, 90, 180, 181, 365, 36500]));
            const slash = BigInt(pick([0, 1, 500, 1500, 1501, 5000]));
            const predicted = byOwner && slash <= 1500n && minStake > 0n && lockDays <= 180n &&
                (minStake === tc.minStake || tc.active === 0n);
            const res = await exec("updateTierConfig", (o) => registry.connect(who).updateTierConfig(t, minStake, maxNodes, lockDays, slash, tc.share, o));
            expectOutcome("updateTierConfig", predicted, res);
            if (!res.ok) return;
            m.advance(res.ts);
            m.syncAll(res.ts);
            Object.assign(tc, { minStake, maxNodes, lockDays, slash });
        } else if (r < 0.55) {
            const cuts = [0, 1, 2].map(() => Math.floor(rnd() * 10001)).sort((x, y) => x - y);
            let shares = [cuts[0], cuts[1] - cuts[0], cuts[2] - cuts[1], 10000 - cuts[2]].map(BigInt);
            // tiny shares make the emission split (not the APR cap) the binding limit
            if (chance(0.35)) shares = pick([[1n, 1n, 1n, 9997n], [9997n, 1n, 1n, 1n], [0n, 0n, 10000n, 0n], [2n, 3n, 5n, 9990n]]);
            const bad = chance(0.05);
            if (bad) shares[0] += 1n;
            const res = await exec("setRewardShares", (o) => registry.connect(who).setRewardShares(...shares, o));
            expectOutcome("setRewardShares", byOwner && !bad, res);
            if (!res.ok) return;
            m.advance(res.ts);
            m.syncAll(res.ts);
            shares.forEach((s, i) => { m.tiers[i].share = s; });
        } else if (r < 0.75) {
            const t = Math.floor(rnd() * TIERS);
            const bps = BigInt(pick([0, 1, 100, 600, 2000, 5000, 5001]));
            const res = await exec("setTierAprCap", (o) => registry.connect(who).setTierAprCap(t, bps, o));
            expectOutcome("setTierAprCap", byOwner && bps >= 1n && bps <= 5000n, res);
            if (!res.ok) return;
            m.advance(res.ts);
            m.sync(t, res.ts);
            m.tiers[t].cap = bps;
        } else if (r < 0.88) {
            const p = chance(0.25);
            const res = await exec("setPaused", (o) => registry.connect(who).setRegistrationPaused(p, o));
            expectOutcome("setRegistrationPaused", byOwner, res);
            if (!res.ok) return;
            m.advance(res.ts);
            m.paused = p;
        } else if (r < 0.94) {
            const oracle = pick([ethers.ZeroAddress, ...eoas.map((s) => s.address)]);
            const res = await exec("setOracle", (o) => registry.connect(who).setUptimeOracle(oracle, o));
            expectOutcome("setUptimeOracle", byOwner, res);
            if (!res.ok) return;
            m.advance(res.ts);
            m.oracle = oracle;
        } else {
            const k = pick(["yes", "yes", "yes", "no", "revert", "none"]);
            const addr = k === "none" ? ethers.ZeroAddress : kycAddrs[k];
            const res = await exec("setKYC", (o) => registry.connect(who).setKYCContract(addr, o));
            expectOutcome("setKYCContract", byOwner, res);
            if (!res.ok) return;
            m.advance(res.ts);
            m.kyc = k;
        }
    }

    async function doTravel() {
        // ~95 jumps × ~12 days ≈ 3+ years per 500 steps: crosses every reward-year boundary
        const dt = BigInt(pick([1, 60, 3600, 86400, 86400 * 3, 86400 * 7, 86400 * 7, 86400 * 14, 86400 * 30, 86400 * 60]));
        now += dt;
        await network.provider.send("evm_mine", [Number(now)]);
    }

    // ── invariant checks ────────────────────────────────────────────────────
    async function checkAll() {
        const T = await callTs();
        const bal = await ethers.provider.getBalance(regAddr);
        expect(bal, `${ctx()} balance`).to.equal(m.balance);
        expect(await registry.totalStaked(), `${ctx()} totalStaked`).to.equal(m.totalStaked);
        expect(bal >= m.totalStaked, `${ctx()} SOLVENCY balance < totalStaked`).to.equal(true);
        expect(await registry.totalRewardsDistributed(), `${ctx()} distributed`).to.equal(m.distributed);
        expect(await registry.totalRewardFunded(), `${ctx()} funded`).to.equal(m.funded);
        expect(await registry.availableRewardFunds(), `${ctx()} avail`).to.equal(m.avail());

        let sumStake = 0n, sumDeposit = 0n, sumBack = 0n, sumRewards = 0n, sumPending = 0n, active = 0n;
        for (let t = 0; t < TIERS; t++) {
            const info = await registry.getTierInfo(t);
            expect(info.activeNodes, `${ctx()} tier ${t} active`).to.equal(m.tiers[t].active);
            active += m.tiers[t].active;
        }
        expect(await registry.totalActiveNodes(), `${ctx()} totalActive`).to.equal(active);

        // bounds are integrated up to T for the check (copy-free: advance is monotone and
        // every later tx advances from here with the same parameters)
        m.advance(T);
        let emissionN = 0n;
        for (const tc of m.tiers) emissionN += tc.emN;

        for (const a of actors) {
            const n = m.node(a.addr);
            const info = await registry.getNodeInfo(a.addr);
            expect(Number(info.status), `${ctx()} status ${a.addr}`).to.equal(n.status);
            expect(info.stakedAmount, `${ctx()} staked ${a.addr}`).to.equal(n.staked);
            if (n.status === S.ACTIVE || n.status === S.SLASHED) sumStake += n.staked;

            const pend = await registry.pendingReward(a.addr);
            expect(pend, `${ctx()} pendingReward ${a.addr}`).to.equal(m.pendingView(a.addr, T));

            const ac = m.acc(a.addr);
            sumDeposit += ac.deposited; sumBack += ac.back; sumRewards += ac.rewards; sumPending += pend;
            // principal side: never more than deposited − slashed
            expect(ac.back <= ac.deposited - ac.slashed, `${ctx()} principal overpaid ${a.addr}`).to.equal(true);
            // reward side: paid + pending <= ∫ minStake·aprCap dt / year (independent of the accumulator)
            expect((ac.rewards + pend) * BPS * YEAR <= m.boundN(a.addr), `${ctx()} rewards above APR-cap bound ${a.addr}`).to.equal(true);

            // liveness — a staker can always get out, whatever the owner did
            const reg = a.probe ? null : registry.connect(a.signer);
            if (a.probe) await probe.connect(a.signer).claim.staticCall();
            else await reg.claimRewards.staticCall();
            if (n.status === S.ACTIVE && T >= n.unlockAt) {
                if (a.probe) await probe.connect(a.signer).exit.staticCall();
                else await reg.deregisterNode.staticCall();
            }
            if (n.status === S.SLASHED && !a.probe) await reg.withdrawSlashedStake.staticCall();
        }
        expect(sumStake, `${ctx()} Σ stake == totalStaked`).to.equal(m.totalStaked);
        expect((sumRewards + sumPending) * BPS <= emissionN, `${ctx()} rewards above emission`).to.equal(true);
        // conservation of TPIX
        expect(bal, `${ctx()} conservation`).to.equal(sumDeposit - sumBack - sumRewards + m.funded + forcedEth);
    }

    // ── main loop ───────────────────────────────────────────────────────────
    await checkAll();
    for (stepNo = 1; stepNo <= STEPS; stepNo++) {
        const a = pick(actors);
        const st = m.node(a.addr).status;
        const r = rnd();
        if (r < 0.62) {
            // actor-driven, biased by state so most calls are meaningful (some still must revert)
            const q = rnd();
            if (st === S.INACTIVE) {
                if (q < 0.75) await doRegister(a);
                else if (q < 0.9) await doClaim(a);
                else await doExit(a);
            } else if (st === S.ACTIVE) {
                if (q < 0.33) await doClaim(a);
                else if (q < 0.66) await doExit(a);
                else if (q < 0.8) await doUptime(a);
                else if (q < 0.92) await doSlash(a);
                else await doRegister(a);
            } else {
                if (q < 0.7 && !a.probe) await doWithdrawSlashed(a);
                else if (q < 0.85) await doClaim(a);
                else await doRegister(a);
            }
        }
        else if (r < 0.655) await doFund();
        else if (r < 0.74) await doAdvanceYear();
        else if (r < 0.785) await doOwnerConfig();
        else if (r < 0.81) await doUptimeBatch();
        else await doTravel();
        await checkAll();
    }

    // ── drain: unlock everyone, fund generously, everyone gets out ──────────
    stepNo = STEPS + 1;
    now += 400n * DAY;
    await network.provider.send("evm_mine", [Number(now)]);
    {
        const big = 3_000_000_000n * E18;
        const res = await exec("fund", (o) => registry.connect(funder).fundRewardPool({ ...o, value: big }));
        expectOutcome("final fund", true, res);
        m.advance(res.ts); m.balance += big; m.funded += big;
    }
    for (const a of actors) {
        const n = m.node(a.addr);
        if (n.status === S.ACTIVE) await doExit(a);
        if (n.status === S.SLASHED && !a.probe) await doWithdrawSlashed(a);
        await doClaim(a);
        await checkAll();
    }
    for (const a of actors) {
        const ac = m.acc(a.addr);
        expect(m.node(a.addr).status, `${ctx()} drained status`).to.not.equal(S.ACTIVE);
        expect(ac.back, `${ctx()} every actor gets deposits − slashed back`).to.equal(ac.deposited - ac.slashed);
        // all earned rewards are paid once the pool is funded — unless the 1.4B(+slashed)
        // emission schedule itself is used up, which the contract enforces on purpose
        if (m.distributed < m.pool) {
            expect(await registry.pendingReward(a.addr), `${ctx()} nothing left owed`).to.equal(0n);
        }
    }
    expect(await registry.totalStaked(), ctx()).to.equal(0n);

    console.log(`      seed ${seed}: ${STEPS} steps, ${stats.ok} tx ok / ${stats.reverted} reverted as predicted, ` +
        `year ${m.year}, forced ${ethers.formatEther(forcedEth)} TPIX, paid ${ethers.formatEther(m.distributed)} TPIX, ` +
        `claims paying ${stats.paidClaims || 0}, claims short of pool ${stats.shortClaims || 0}`);
    console.log("        " + Object.entries(stats.actions).map(([k, v]) => `${k} ${v.ok}/${v.rev}`).join(" · "));
}
