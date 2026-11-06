/**
 * scripts/lib/launchpad-plan.js — the launch plan → createLaunch() arguments, checked before anything is sent.
 *
 *   - the IDTC plan gives the price the whitepaper promises (1 USDT = 666,666.67 IDTC) and passes every rule
 *   - each anti-rug rule is refused locally with a Thai reason, before the owner signs anything
 *   - the local "locked at LP unlock" figure equals what LaunchpadFactory computes on chain, on both sides
 *     of the 80% line (so the pre-check never passes a launch the factory would revert, or the reverse)
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { deployTokenFactory } = require("./helpers/deployTokenFactory");
const { buildLaunch, priceToRate, vestedAt, lockedBps, PlanError } = require("../scripts/lib/launchpad-plan");
const idtc = require("../scripts/launch-plans/idtc.json");

const NOW = 1_800_000_000n;
const A = "0x00000000000000000000000000000000000000a1";
const opts = (over = {}) => ({ token: A, saleStart: NOW + 3_600n, beneficiary: A, projectTreasury: A, payDecimals: 6, now: NOW, ...over });
const withLp = (over) => ({ ...idtc, launchpad: { ...idtc.launchpad, ...over } });

describe("launchpad plan (scripts/lib/launchpad-plan.js)", function () {
    it("prices IDTC at $0.0000015 — 1 USDT buys 666,666.666666 IDTC", function () {
        const { num, den } = priceToRate("0.0000015", 18, 6);
        expect(num).to.equal(2n * 10n ** 18n);
        expect(den).to.equal(3n);
        expect((10n ** 6n * num) / den).to.equal(666_666_666_666_666_666_666_666n);
        expect(() => priceToRate("0", 18, 6)).to.throw(PlanError);
        expect(() => priceToRate("abc", 18, 6)).to.throw(PlanError);
    });

    it("builds the IDTC launch the owner decided: 100B sale, 90 days, 100% to pool, 10 USDT seed, LP 1 year", function () {
        const L = buildLaunch(idtc, opts());
        const p = L.params;
        const B = 10n ** 9n * 10n ** 18n;
        expect(p.saleCap).to.equal(100n * B);
        expect(p.feederReserve).to.equal(100n * B);
        expect(p.endTime - p.startTime).to.equal(90n * 86_400n);
        expect(p.lpUnlockTime - p.endTime).to.equal(365n * 86_400n);
        expect(p.poolShareBps).to.equal(10_000);
        expect(L.seedQuote).to.equal(10n * 10n ** 6n);
        expect(L.minPurchase).to.equal(10n ** 6n);
        expect(L.vesting.start).to.equal(p.startTime);
        expect(L.tokensNeeded).to.equal(970n * B);
        expect(L.freeAfter).to.equal(130n * B);
        expect(L.lockedBps).to.be.gte(8_000n);
    });

    it("the owner's decided dates and wallets (2026-11-06): sale 1 Dec 2026 10:00 → 1 Mar 2027, LP free 29 Feb 2028", function () {
        const lp = idtc.launchpad;
        const start = BigInt(Date.parse(lp.saleStart) / 1000);
        expect(new Date(Number(start) * 1000).toISOString()).to.equal("2026-12-01T03:00:00.000Z");
        expect(ethers.getAddress(lp.beneficiary)).to.equal(lp.beneficiary);
        expect(ethers.getAddress(lp.projectTreasury)).to.equal(lp.projectTreasury);

        const L = buildLaunch(idtc, opts({ saleStart: start, beneficiary: lp.beneficiary, projectTreasury: lp.projectTreasury, now: start - 86_400n }));
        const iso = (t) => new Date(Number(t) * 1000).toISOString();
        expect(iso(L.params.endTime)).to.equal("2027-03-01T03:00:00.000Z");
        expect(iso(L.params.lpUnlockTime)).to.equal("2028-02-29T03:00:00.000Z");
        expect(L.lockedBps).to.equal(8_484n);
        expect(L.params.bandBps).to.equal(500); // ±5% (owner, 2026-11-06)
        expect(L.minPurchase).to.equal(10n ** 6n);
        expect(L.maxPerWallet).to.equal(0n);
    });

    it("SEED_USDT overrides the plan — 0 leaves the pool for the first purchase", function () {
        expect(buildLaunch(idtc, opts({ seedUsdt: "0" })).seedQuote).to.equal(0n);
        expect(() => buildLaunch(idtc, opts({ seedUsdt: "1.0000001" }))).to.throw(PlanError, /ทศนิยม/);
    });

    it("refuses each anti-rug rule before anything is signed", function () {
        expect(() => buildLaunch(withLp({ lpLockDaysAfterEnd: 179 }), opts())).to.throw(PlanError, /180/);
        expect(() => buildLaunch(withLp({ poolShareBps: 4_999 }), opts())).to.throw(PlanError, /poolShareBps/);
        expect(() => buildLaunch(withLp({ bandBps: 2_001 }), opts())).to.throw(PlanError, /bandBps/);
        expect(() => buildLaunch(withLp({ feederReserve: "0" }), opts())).to.throw(PlanError, /feederReserve/);
        expect(() => buildLaunch(idtc, opts({ saleStart: NOW }))).to.throw(PlanError, /อนาคต/);
        // LP locked 3 years after the sale: vesting tranches 1–2 have unlocked by then → < 80% locked
        expect(() => buildLaunch(withLp({ lpLockDaysAfterEnd: 1_095 }), opts())).to.throw(PlanError, /80%/);
        const { launchpad, ...noSection } = idtc;
        expect(() => buildLaunch(noSection, opts())).to.throw(PlanError, /launchpad/);
    });

    it("vestedAt follows TrancheVesting: nothing before the cliff, then one release period at a time", function () {
        const v = { start: 0n, period: 10n, tranches: [{ amount: 1_200n, cliffPeriods: 12, releasePeriods: 12 }] };
        expect(vestedAt(v, 120n)).to.equal(0n);
        expect(vestedAt(v, 129n)).to.equal(0n);
        expect(vestedAt(v, 130n)).to.equal(100n);
        expect(vestedAt(v, 240n)).to.equal(1_200n);
        expect(vestedAt(v, 10_000n)).to.equal(1_200n);
    });

    describe("agrees with LaunchpadFactory on chain", function () {
        async function deploy() {
            const [creator] = await ethers.getSigners();
            const wtpix = await (await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX")).deploy();
            const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
            const dex = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(creator.address);
            const router = await (await ethers.getContractFactory("TPIXDEXRouter02")).deploy(await dex.getAddress(), await wtpix.getAddress());
            const { tokenFactory } = await deployTokenFactory();
            const vd = await (await ethers.getContractFactory("LaunchVestingDeployer")).deploy();
            const lf = await (await ethers.getContractFactory("LaunchpadFactory")).deploy(
                await usdt.getAddress(), await router.getAddress(), await vd.getAddress(), await tokenFactory.getAddress()
            );
            const supply = ethers.parseUnits(idtc.totalSupply, 18);
            const rc = await (await tokenFactory.createERC20V2("IDTC", "IDTC", 18, supply, creator.address, false, false, false, false, 0, false, 0, 0)).wait();
            const ev = rc.logs.map((l) => { try { return tokenFactory.interface.parseLog(l); } catch { return null; } }).find((e) => e?.name === "TokenCreated");
            const token = await ethers.getContractAt("FactoryERC20V2", ev.args.tokenAddress);
            await token.approve(await lf.getAddress(), supply);
            return { creator, lf, token };
        }

        const build = async (ctx, now, lockDays) =>
            buildLaunch(withLp({ lpLockDaysAfterEnd: lockDays, seedUsdt: "0" }), opts({
                token: await ctx.token.getAddress(), now, saleStart: now + 600n,
                beneficiary: ctx.creator.address, projectTreasury: ctx.creator.address,
            }));

        it("a plan the pre-check passes is accepted by the factory", async function () {
            const ctx = await deploy();
            const L = await build(ctx, BigInt(await time.latest()), 365);
            await expect(ctx.lf.createLaunch.staticCall(L.params, L.vesting)).to.not.be.reverted;
        });

        it("past the 80% line both refuse — and the factory reports the same locked share the pre-check computes", async function () {
            const ctx = await deploy();
            const now = BigInt(await time.latest());
            await expect(build(ctx, now, 1_095)).to.be.rejectedWith(PlanError, /80%/);
            // same launch with only the LP unlock stretched to 3 years after the sale, sent past the pre-check
            const ok = await build(ctx, now, 365);
            const longer = { ...ok.params, lpUnlockTime: ok.params.endTime + 1_095n * 86_400n };
            const expected = lockedBps(longer, ok.vesting, ok.totalSupply);
            expect(expected).to.be.lt(8_000n);
            await expect(ctx.lf.createLaunch.staticCall(longer, ok.vesting))
                .to.be.revertedWithCustomError(ctx.lf, "TooMuchUnlocked").withArgs(expected);
        });
    });
});
