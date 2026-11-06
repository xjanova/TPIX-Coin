/**
 * Launchpad — LaunchpadFactory + PoolFeeder + FixedPriceSale + TrancheVesting on the real TPIX DEX contracts.
 *
 *   - one createLaunch: sale, feeder, vesting, and the pool opened at exactly the sale price, LP held by the feeder
 *   - purchases feed the pool at its own ratio; project share split once (never re-split on leftovers)
 *   - the band: a pushed pool price stops permissionless feeds; only the owner may feed against a stated price
 *   - a pair created first at a bad price blocks the launch; donated balances in an empty pair are skimmed
 *   - locks: LP until lpUnlockTime, reserve until the sale ends; protected tokens cannot be "recovered"
 *   - holders can sell back into the pool right after a feed
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const WTPIX_FQN = "src/sale/WTPIX_ERC20.sol:WTPIX";
const E18 = 10n ** 18n;
const B = 1_000_000_000n * E18;
const USDT = 10n ** 6n;
const NUM = 2n * E18; // tokens (wei) per micro-USDT = 2e18 / 3  →  $0.0000015 per token
const DEN = 3n;
const DAY = 86_400n;
const MONTH = 2_629_800n;
const STANDARD = [false, false, false, false, 0, false, 0, 0];

const TRANCHES = [
    { amount: 220n * B, cliffPeriods: 12, releasePeriods: 12 },
    { amount: 220n * B, cliffPeriods: 24, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 36, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 48, releasePeriods: 12 },
];

describe("Launchpad (LaunchpadFactory + PoolFeeder)", function () {
    async function fixture() {
        const [deployer, creator, buyer, attacker, project] = await ethers.getSigners();
        const wtpix = await (await ethers.getContractFactory(WTPIX_FQN)).deploy();
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        const dexFactory = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(deployer.address);
        const router = await (await ethers.getContractFactory("TPIXDEXRouter02")).deploy(
            await dexFactory.getAddress(),
            await wtpix.getAddress()
        );
        const vd = await (await ethers.getContractFactory("LaunchVestingDeployer")).deploy();
        const lf = await (await ethers.getContractFactory("LaunchpadFactory")).deploy(
            await usdt.getAddress(),
            await router.getAddress(),
            await vd.getAddress()
        );
        const token = await (await ethers.getContractFactory("FactoryERC20V2")).deploy(
            "Invest Energy-Development Coin", "IDTC", 18, 1_100n * B, creator.address, ...STANDARD
        );

        await usdt.setBridge(deployer.address, true);
        for (const s of [creator, buyer, attacker]) await usdt.bridgeMint(s.address, 1_000_000n * USDT, ethers.id(`seed-${s.address}`));
        await usdt.setBridge(deployer.address, false);

        return { deployer, creator, buyer, attacker, project, usdt, dexFactory, router, lf, token };
    }

    async function params(ctx, over = {}) {
        const now = BigInt(await time.latest());
        const start = now + 60n;
        const end = start + 90n * DAY;
        return {
            token: await ctx.token.getAddress(),
            rateNumerator: NUM,
            rateDenominator: DEN,
            saleCap: 100n * B,
            feederReserve: 100n * B,
            startTime: start,
            endTime: end,
            poolShareBps: 10_000,
            bandBps: 0,
            lpUnlockTime: end + 365n * DAY,
            projectTreasury: ctx.project.address,
            minFeed: 1n * USDT,
            seedQuote: 10n * USDT,
            ...over,
        };
    }

    function vesting(ctx, start, over = {}) {
        return { beneficiary: ctx.creator.address, start, period: MONTH, tranches: TRANCHES, label: "IDTC — ล็อก 70%", ...over };
    }

    const NO_VESTING = { beneficiary: ethers.ZeroAddress, start: 0, period: 0, tranches: [], label: "" };

    async function launch(ctx, over = {}, vest) {
        const p = await params(ctx, over);
        const v = vest === undefined ? vesting(ctx, p.startTime) : vest;
        const lfAddr = await ctx.lf.getAddress();
        const vestTotal = (v.tranches || []).reduce((a, t) => a + t.amount, 0n);
        await ctx.token.connect(ctx.creator).approve(lfAddr, p.saleCap + p.feederReserve + vestTotal);
        if (p.seedQuote > 0n) await ctx.usdt.connect(ctx.creator).approve(lfAddr, p.seedQuote);
        const tx = await ctx.lf.connect(ctx.creator).createLaunch(p, v);
        const rc = await tx.wait();
        const ev = rc.logs.map((l) => { try { return ctx.lf.interface.parseLog(l); } catch { return null; } })
            .find((e) => e && e.name === "LaunchCreated");
        const sale = await ethers.getContractAt("FixedPriceSale", ev.args.sale);
        const feeder = await ethers.getContractAt("PoolFeeder", ev.args.feeder);
        const vest2 = ev.args.vesting === ethers.ZeroAddress ? null : await ethers.getContractAt("TrancheVesting", ev.args.vesting);
        return { p, sale, feeder, vesting: vest2, ev };
    }

    async function pairOf(ctx) {
        const addr = await ctx.dexFactory.getPair(await ctx.token.getAddress(), await ctx.usdt.getAddress());
        return addr === ethers.ZeroAddress ? null : ethers.getContractAt("TPIXDEXPair", addr);
    }

    async function buy(ctx, sale, signer, amount) {
        await ctx.usdt.connect(signer).approve(await sale.getAddress(), amount);
        return sale.connect(signer).buy(amount);
    }

    /** sell `tokens` of the child token for USDT through the router */
    async function sell(ctx, signer, tokens) {
        const r = await ctx.router.getAddress();
        await ctx.token.connect(signer).approve(r, tokens);
        return ctx.router.connect(signer).swapExactTokensForTokens(
            tokens, 0, [await ctx.token.getAddress(), await ctx.usdt.getAddress()], signer.address, (await time.latest()) + 600
        );
    }

    async function buyFromPool(ctx, signer, usdtIn) {
        const r = await ctx.router.getAddress();
        await ctx.usdt.connect(signer).approve(r, usdtIn);
        return ctx.router.connect(signer).swapExactTokensForTokens(
            usdtIn, 0, [await ctx.usdt.getAddress(), await ctx.token.getAddress()], signer.address, (await time.latest()) + 600
        );
    }

    describe("createLaunch", function () {
        it("deploys sale + feeder + vesting, funds them, and opens the pool at exactly the sale price", async function () {
            const ctx = await loadFixture(fixture);
            const { p, sale, feeder, vesting: v, ev } = await launch(ctx);

            expect(await sale.owner()).to.equal(await feeder.getAddress());
            expect(await feeder.sale()).to.equal(await sale.getAddress());
            expect(await feeder.owner()).to.equal(ctx.creator.address);
            expect(await sale.treasury()).to.equal(await feeder.getAddress());
            expect(await ctx.token.balanceOf(await sale.getAddress())).to.equal(p.saleCap);
            expect(await v.totalAllocation()).to.equal(770n * B);
            expect(await ctx.token.balanceOf(await v.getAddress())).to.equal(770n * B);
            expect(await ctx.token.balanceOf(ctx.creator.address)).to.equal(130n * B);
            expect(await feeder.tokenReserve()).to.equal(100n * B - (10n * USDT * NUM) / DEN);

            const pair = await pairOf(ctx);
            const [tr, qr] = await feeder.poolReserves();
            expect(qr).to.equal(10n * USDT);
            expect(tr).to.equal((10n * USDT * NUM) / DEN);
            expect(await feeder.poolVsSaleBps()).to.be.closeTo(10_000n, 1n); // token side rounds down
            const lp = await pair.balanceOf(await feeder.getAddress());
            expect(lp).to.be.gt(0n);
            expect(await pair.balanceOf(ctx.creator.address)).to.equal(0n);

            expect(await ctx.lf.launchCount()).to.equal(1n);
            const L = await ctx.lf.launchAt(0);
            expect(L.sale).to.equal(ev.args.sale);
            expect(L.vesting).to.equal(ev.args.vesting);
            expect(await ctx.lf.launchIdOfSale(ev.args.sale)).to.equal(1n);
        });

        it("works without vesting and without a seed (first purchase opens the pool)", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder, vesting: v } = await launch(ctx, { seedQuote: 0n }, NO_VESTING);
            expect(v).to.equal(null);
            expect(await pairOf(ctx)).to.equal(null);
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 100n * USDT);
            await feeder.feed();
            expect(await feeder.poolVsSaleBps()).to.be.closeTo(10_000n, 1n); // token side rounds down
            const [, qr] = await feeder.poolReserves();
            expect(qr).to.equal(100n * USDT);
        });

        it("rejects bad configs", async function () {
            const ctx = await loadFixture(fixture);
            const lfAsCreator = ctx.lf.connect(ctx.creator);
            const p = await params(ctx);
            await expect(lfAsCreator.createLaunch({ ...p, lpUnlockTime: p.endTime + 29n * DAY }, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "BadConfig");
            await expect(lfAsCreator.createLaunch({ ...p, token: await ctx.usdt.getAddress() }, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "BadConfig");
            await expect(lfAsCreator.createLaunch({ ...p, feederReserve: 0n }, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "BadConfig");
            await expect(lfAsCreator.createLaunch({ ...p, projectTreasury: ethers.ZeroAddress }, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "ZeroAddress");
            await expect(lfAsCreator.createLaunch({ ...p, bandBps: 2001 }, NO_VESTING))
                .to.be.revertedWithCustomError(await ethers.getContractFactory("PoolFeeder"), "BadConfig");
        });

        it("rejects tokens that take a fee on transfer", async function () {
            const ctx = await loadFixture(fixture);
            const fee = await (await ethers.getContractFactory("FeeOnTransferToken")).connect(ctx.creator).deploy(1_000n * B);
            const p = await params(ctx, { token: await fee.getAddress(), seedQuote: 0n });
            await fee.connect(ctx.creator).approve(await ctx.lf.getAddress(), p.saleCap + p.feederReserve);
            await expect(ctx.lf.connect(ctx.creator).createLaunch(p, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "FeeOnTransfer");
        });

        it("refuses to launch into a pair someone opened first at a bad price", async function () {
            const ctx = await loadFixture(fixture);
            // attacker got a few tokens and opens the pair 10x cheaper than the sale price
            await ctx.token.connect(ctx.creator).transfer(ctx.attacker.address, 1n * B);
            const r = await ctx.router.getAddress();
            await ctx.token.connect(ctx.attacker).approve(r, 1n * B);
            await ctx.usdt.connect(ctx.attacker).approve(r, 150n * USDT);
            await ctx.router.connect(ctx.attacker).addLiquidity(
                await ctx.token.getAddress(), await ctx.usdt.getAddress(), 1n * B, 150n * USDT, 0, 0, ctx.attacker.address, (await time.latest()) + 600
            );
            const p = await params(ctx);
            await ctx.token.connect(ctx.creator).approve(await ctx.lf.getAddress(), p.saleCap + p.feederReserve);
            await ctx.usdt.connect(ctx.creator).approve(await ctx.lf.getAddress(), p.seedQuote);
            await expect(ctx.lf.connect(ctx.creator).createLaunch(p, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "PoolPriceOff");
        });

        it("skims tokens donated into an empty pair before seeding, so the seed sets exactly the sale price", async function () {
            const ctx = await loadFixture(fixture);
            await ctx.dexFactory.createPair(await ctx.token.getAddress(), await ctx.usdt.getAddress());
            const pair = await pairOf(ctx);
            await ctx.token.connect(ctx.creator).transfer(await pair.getAddress(), 5n * B); // donation, not minted
            await ctx.usdt.connect(ctx.attacker).transfer(await pair.getAddress(), 1n * USDT);
            const { feeder } = await launch(ctx, {}, NO_VESTING);
            expect(await feeder.poolVsSaleBps()).to.be.closeTo(10_000n, 1n); // token side rounds down
            expect(await ctx.token.balanceOf(ctx.project.address)).to.equal(5n * B);
            expect(await ctx.usdt.balanceOf(ctx.project.address)).to.equal(1n * USDT);
        });
    });

    describe("feed", function () {
        it("adds each purchase to the pool at the pool ratio, LP stays in the feeder", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            const pair = await pairOf(ctx);
            await time.increaseTo((await sale.startTime()) + 1n);

            const lp0 = await pair.balanceOf(await feeder.getAddress());
            await buy(ctx, sale, ctx.buyer, 500n * USDT);
            expect(await ctx.usdt.balanceOf(await feeder.getAddress())).to.equal(500n * USDT);
            await expect(feeder.connect(ctx.attacker).feed()).to.emit(feeder, "Fed"); // anyone may call
            const [tr, qr] = await feeder.poolReserves();
            expect(qr).to.equal(510n * USDT);
            expect(await feeder.poolVsSaleBps()).to.be.closeTo(10_000n, 1n); // token side rounds down
            expect(tr).to.be.closeTo((510n * USDT * NUM) / DEN, 10n ** 6n); // wei-level rounding
            expect(await pair.balanceOf(await feeder.getAddress())).to.be.gt(lp0);
            expect(await ctx.usdt.balanceOf(await feeder.getAddress())).to.equal(0n);
            expect(await feeder.pendingPool()).to.equal(0n);
            expect(await feeder.totalQuoteToPool()).to.equal(510n * USDT);
        });

        it("splits the project share once, even when the pool part has to wait for reserve", async function () {
            const ctx = await loadFixture(fixture);
            // reserve pairs only ~200 USDT at the sale price, half of the proceeds go to the project
            const reserve = (210n * USDT * NUM) / DEN;
            const { sale, feeder } = await launch(ctx, { poolShareBps: 5_000, feederReserve: reserve }, NO_VESTING);
            await time.increaseTo((await sale.startTime()) + 1n);
            const projectBefore = await ctx.usdt.balanceOf(ctx.project.address); // 5 USDT from the seed split

            await buy(ctx, sale, ctx.buyer, 1_000n * USDT);
            await feeder.feed();
            // 500 to the project, 500 set aside, only ~200 could be paired
            expect((await ctx.usdt.balanceOf(ctx.project.address)) - projectBefore).to.equal(500n * USDT);
            const pending = await feeder.pendingPool();
            expect(pending).to.be.gt(290n * USDT);
            expect(await feeder.tokenReserve()).to.be.lt(10n ** 12n);

            // feeding again moves nothing more to the project — leftovers are not re-split
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "NothingToFeed");
            expect((await ctx.usdt.balanceOf(ctx.project.address)) - projectBefore).to.equal(500n * USDT);

            // a new purchase: only ITS half goes to the project
            await buy(ctx, sale, ctx.buyer, 100n * USDT);
            await feeder.feed();
            expect((await ctx.usdt.balanceOf(ctx.project.address)) - projectBefore).to.equal(550n * USDT);
            expect(await feeder.pendingPool()).to.equal(pending + 50n * USDT);
        });

        it("stops permissionless feeds when the pool price leaves the band; the owner feeds against a stated price", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 100n * USDT);
            const tokens = await ctx.token.balanceOf(ctx.buyer.address);
            await sell(ctx, ctx.buyer, tokens / 10n); // dumps the 10-USDT pool well below the band

            const vs = await feeder.poolVsSaleBps();
            expect(vs).to.be.gt(10_300n);
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "OutOfBand");
            await expect(feeder.connect(ctx.attacker).feedWithReference(1, 1))
                .to.be.revertedWithCustomError(feeder, "OwnableUnauthorizedAccount");

            const [tr, qr] = await feeder.poolReserves();
            await expect(feeder.connect(ctx.creator).feedWithReference(tr, qr)).to.emit(feeder, "Fed");
            expect(await feeder.pendingPool()).to.be.lte(1n); // rounding dust only
        });

        it("keeps the band within ±3% by default", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx, { seedQuote: 1_000n * USDT });
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 50n * USDT);
            await buyFromPool(ctx, ctx.attacker, 10n * USDT); // ~2% move: still inside
            expect(await feeder.poolVsSaleBps()).to.be.gt(9_700n);
            await expect(feeder.feed()).to.emit(feeder, "Fed");

            await buy(ctx, sale, ctx.buyer, 50n * USDT);
            await buyFromPool(ctx, ctx.attacker, 40n * USDT); // pushes past −3%
            expect(await feeder.poolVsSaleBps()).to.be.lt(9_700n);
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "OutOfBand");
        });

        it("lets a holder sell back into the pool right after a feed", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 1_000n * USDT);
            await feeder.feed();
            const before = await ctx.usdt.balanceOf(ctx.buyer.address);
            const sellAmt = (await ctx.token.balanceOf(ctx.buyer.address)) / 10n; // 100 USDT worth at sale price
            await sell(ctx, ctx.buyer, sellAmt);
            const got = (await ctx.usdt.balanceOf(ctx.buyer.address)) - before;
            expect(got).to.be.gt(89n * USDT); // 0.3% fee + ~9% impact in a 1,010-USDT pool
        });

        it("ignores dust below minFeed", async function () {
            const ctx = await loadFixture(fixture);
            const { feeder } = await launch(ctx);
            await ctx.usdt.connect(ctx.buyer).transfer(await feeder.getAddress(), 1n);
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "NothingToFeed");
        });
    });

    describe("proceeds cannot be redirected", function () {
        it("the creator can neither repoint the sale treasury nor take over the sale", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            await expect(sale.connect(ctx.creator).setTreasury(ctx.creator.address))
                .to.be.revertedWithCustomError(sale, "OwnableUnauthorizedAccount");
            await expect(sale.connect(ctx.creator).transferOwnership(ctx.creator.address))
                .to.be.revertedWithCustomError(sale, "OwnableUnauthorizedAccount");
            expect(feeder.interface.getFunction("setTreasury")).to.equal(null);
            expect(feeder.interface.getFunction("transferSaleOwnership")).to.equal(null);
            expect(feeder.interface.getFunction("setMinFeed")).to.equal(null);
        });

        it("bindSale runs once, only by the deployer", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            await expect(feeder.connect(ctx.creator).bindSale(await sale.getAddress()))
                .to.be.revertedWithCustomError(feeder, "NotBinder");
            await expect(ctx.lf.connect(ctx.creator).createLaunch(await params(ctx, { minFeed: 0n, seedQuote: 0n }), NO_VESTING))
                .to.be.revertedWithCustomError(feeder, "BadConfig");
        });

        it("the creator drives pause / limits / window through the feeder, but cannot extend the sale", async function () {
            const ctx = await loadFixture(fixture);
            const { p, sale, feeder } = await launch(ctx);
            const f = feeder.connect(ctx.creator);
            await f.pauseSale();
            expect(await sale.paused()).to.equal(true);
            await f.unpauseSale();
            await f.setSaleLimits(5n * USDT, 0n);
            expect(await sale.minPurchase()).to.equal(5n * USDT);
            await expect(f.setSaleWindow(p.startTime, p.endTime + 1n)).to.be.revertedWithCustomError(feeder, "BadConfig");
            await f.setSaleWindow(p.startTime, p.endTime - DAY);
            expect(await sale.endTime()).to.equal(p.endTime - DAY);
            await expect(feeder.connect(ctx.attacker).pauseSale()).to.be.revertedWithCustomError(feeder, "OwnableUnauthorizedAccount");
        });

        it("the reserve cannot leave while proceeds wait for the pool; leftovers only after the LP unlock", async function () {
            const ctx = await loadFixture(fixture);
            const { p, sale, feeder } = await launch(ctx);
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 100n * USDT);
            const tokens = await ctx.token.balanceOf(ctx.buyer.address);
            await sell(ctx, ctx.buyer, tokens / 10n); // out of band: the 100 USDT cannot be fed by anyone
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "OutOfBand");

            await time.increaseTo(p.endTime);
            const f = feeder.connect(ctx.creator);
            await expect(f.withdrawReserve(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "QuotePending");
            await expect(f.withdrawLeftoverQuote(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await time.increaseTo(p.lpUnlockTime);
            await expect(f.withdrawLeftoverQuote(ctx.creator.address)).to.emit(feeder, "ReserveWithdrawn");
            await expect(f.withdrawReserve(ctx.creator.address)).to.emit(feeder, "ReserveWithdrawn");
        });

        it("withdrawUnsold goes through the feeder after the sale", async function () {
            const ctx = await loadFixture(fixture);
            const { p, sale, feeder } = await launch(ctx);
            await time.increaseTo(p.endTime);
            await feeder.connect(ctx.creator).withdrawUnsold(ctx.creator.address);
            expect(await ctx.token.balanceOf(await sale.getAddress())).to.equal(0n);
        });
    });

    describe("locks", function () {
        it("holds the LP until lpUnlockTime and the reserve until the sale ends", async function () {
            const ctx = await loadFixture(fixture);
            const { p, feeder } = await launch(ctx);
            const f = feeder.connect(ctx.creator);
            await expect(f.withdrawLiquidity(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await expect(f.withdrawReserve(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");

            await time.increaseTo(p.endTime);
            const reserve = await feeder.tokenReserve();
            await expect(f.withdrawReserve(ctx.creator.address)).to.emit(feeder, "ReserveWithdrawn").withArgs(ctx.creator.address, reserve, 0n);
            await expect(f.withdrawLiquidity(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");

            await time.increaseTo(p.lpUnlockTime);
            await expect(feeder.connect(ctx.attacker).withdrawLiquidity(ctx.attacker.address))
                .to.be.revertedWithCustomError(feeder, "OwnableUnauthorizedAccount");
            await expect(f.withdrawLiquidity(ctx.creator.address)).to.emit(feeder, "LiquidityWithdrawn");
            const pair = await pairOf(ctx);
            expect(await pair.balanceOf(ctx.creator.address)).to.be.gt(0n);
        });

        it("never recovers the token, the quote or the LP", async function () {
            const ctx = await loadFixture(fixture);
            const { feeder } = await launch(ctx);
            const f = feeder.connect(ctx.creator);
            const pair = await pairOf(ctx);
            for (const t of [await ctx.token.getAddress(), await ctx.usdt.getAddress(), await pair.getAddress()]) {
                await expect(f.recoverToken(t, ctx.creator.address)).to.be.revertedWithCustomError(feeder, "ProtectedToken");
            }
        });

        it("vesting releases nothing before the first cliff", async function () {
            const ctx = await loadFixture(fixture);
            const { vesting: v } = await launch(ctx);
            await time.increase(11n * MONTH);
            expect(await v.releasable()).to.equal(0n);
            expect(await v.beneficiary()).to.equal(ctx.creator.address);
        });
    });
});
