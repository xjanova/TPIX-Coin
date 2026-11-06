/**
 * Launchpad — LaunchpadFactory + PoolFeeder + FixedPriceSale + TrancheVesting on the real TPIX DEX contracts.
 *
 *   - one createLaunch: sale, feeder, vesting, and the pool opened at exactly the sale price, LP held by the feeder
 *   - purchases feed the pool at its own ratio; project share split once (never re-split on leftovers)
 *   - the band: a pushed pool price stops every feed (owner included) until arbitrage brings it back
 *   - a pair created first at a bad price blocks the launch; donated balances in an empty pair are skimmed
 *   - anti-rug: only Token Factory ERC20V2 tokens with mint / pause / blacklist / auto-burn off; LP ≥ 180 days;
 *     ≥ 50% of proceeds to the pool; ≥ 80% of supply in sale + reserve + vesting still locked at LP unlock
 *   - locks: LP, unpaired reserve, unsold sale tokens and unpaired proceeds all stay until lpUnlockTime
 *   - holders can sell back into the pool right after a feed
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { deployTokenFactory } = require("./helpers/deployTokenFactory");

const WTPIX_FQN = "src/sale/WTPIX_ERC20.sol:WTPIX";
const E18 = 10n ** 18n;
const B = 1_000_000_000n * E18;
const USDT = 10n ** 6n;
const NUM = 2n * E18; // tokens (wei) per micro-USDT = 2e18 / 3  →  $0.0000015 per token
const DEN = 3n;
const DAY = 86_400n;
const MONTH = 2_629_800n;
// mintable, burnable, pausable, blacklist, mintCap, autoBurn, autoBurnRateBps, burnFloor
const STANDARD = [false, false, false, false, 0, false, 0, 0];

const TRANCHES = [
    { amount: 220n * B, cliffPeriods: 12, releasePeriods: 12 },
    { amount: 220n * B, cliffPeriods: 24, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 36, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 48, releasePeriods: 12 },
];

/** no vesting: the sale + reserve alone must then hold ≥ 80% of the 1.1T supply */
const BIG_SALE = { saleCap: 500n * B, feederReserve: 400n * B };

describe("Launchpad (LaunchpadFactory + PoolFeeder)", function () {
    async function createToken(tokenFactory, owner, flags = STANDARD, supply = 1_100n * B) {
        const tx = await tokenFactory.createERC20V2("Invest Energy-Development Coin", "IDTC", 18, supply, owner, ...flags);
        const rc = await tx.wait();
        const ev = rc.logs.map((l) => { try { return tokenFactory.interface.parseLog(l); } catch { return null; } })
            .find((e) => e && e.name === "TokenCreated");
        return ethers.getContractAt("FactoryERC20V2", ev.args.tokenAddress);
    }

    async function fixture() {
        const [deployer, creator, buyer, attacker, project] = await ethers.getSigners();
        const wtpix = await (await ethers.getContractFactory(WTPIX_FQN)).deploy();
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        const dexFactory = await (await ethers.getContractFactory("TPIXDEXFactory")).deploy(deployer.address);
        const router = await (await ethers.getContractFactory("TPIXDEXRouter02")).deploy(
            await dexFactory.getAddress(),
            await wtpix.getAddress()
        );
        const { tokenFactory } = await deployTokenFactory();
        const vd = await (await ethers.getContractFactory("LaunchVestingDeployer")).deploy();
        const lf = await (await ethers.getContractFactory("LaunchpadFactory")).deploy(
            await usdt.getAddress(),
            await router.getAddress(),
            await vd.getAddress(),
            await tokenFactory.getAddress()
        );
        const token = await createToken(tokenFactory, creator.address);

        await usdt.setBridge(deployer.address, true);
        for (const s of [creator, buyer, attacker]) await usdt.bridgeMint(s.address, 1_000_000n * USDT, ethers.id(`seed-${s.address}`));
        await usdt.setBridge(deployer.address, false);

        return { deployer, creator, buyer, attacker, project, usdt, dexFactory, router, lf, token, tokenFactory };
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

    async function approveFor(ctx, p, v) {
        const lfAddr = await ctx.lf.getAddress();
        const vestTotal = (v.tranches || []).reduce((a, t) => a + t.amount, 0n);
        const token = await ethers.getContractAt("IERC20", p.token);
        await token.connect(ctx.creator).approve(lfAddr, p.saleCap + p.feederReserve + vestTotal);
        if (p.seedQuote > 0n) await ctx.usdt.connect(ctx.creator).approve(lfAddr, p.seedQuote);
    }

    async function launch(ctx, over = {}, vest) {
        const p = await params(ctx, over);
        const v = vest === undefined ? vesting(ctx, p.startTime) : vest;
        await approveFor(ctx, p, v);
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
            const { sale, feeder, vesting: v } = await launch(ctx, { seedQuote: 0n, ...BIG_SALE }, NO_VESTING);
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
            await expect(lfAsCreator.createLaunch({ ...p, lpUnlockTime: p.endTime + 179n * DAY }, NO_VESTING))
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
            const v = vesting(ctx, p.startTime);
            await approveFor(ctx, p, v);
            await expect(ctx.lf.connect(ctx.creator).createLaunch(p, v))
                .to.be.revertedWithCustomError(ctx.lf, "PoolPriceOff");
        });

        it("skims tokens donated into an empty pair before seeding, so the seed sets exactly the sale price", async function () {
            const ctx = await loadFixture(fixture);
            await ctx.dexFactory.createPair(await ctx.token.getAddress(), await ctx.usdt.getAddress());
            const pair = await pairOf(ctx);
            await ctx.token.connect(ctx.creator).transfer(await pair.getAddress(), 5n * B); // donation, not minted
            await ctx.usdt.connect(ctx.attacker).transfer(await pair.getAddress(), 1n * USDT);
            const { feeder } = await launch(ctx);
            expect(await feeder.poolVsSaleBps()).to.be.closeTo(10_000n, 1n); // token side rounds down
            expect(await ctx.token.balanceOf(ctx.project.address)).to.equal(5n * B);
            expect(await ctx.usdt.balanceOf(ctx.project.address)).to.equal(1n * USDT);
        });
    });

    describe("anti-rug rules", function () {
        it("only accepts tokens made by the TPIX Token Factory", async function () {
            const ctx = await loadFixture(fixture);
            // same contract code, deployed by hand — not in the factory's register
            const loose = await (await ethers.getContractFactory("FactoryERC20V2")).deploy(
                "Fake IDTC", "IDTC", 18, 1_100n * B, ctx.creator.address, ...STANDARD
            );
            const fee = await (await ethers.getContractFactory("FeeOnTransferToken")).connect(ctx.creator).deploy(1_100n * B);
            for (const t of [loose, fee]) {
                const addr = await t.getAddress();
                expect(await ctx.lf.tokenCheck(addr)).to.equal(1n);
                const p = await params(ctx, { token: addr, seedQuote: 0n, ...BIG_SALE });
                await approveFor(ctx, p, NO_VESTING);
                await expect(ctx.lf.connect(ctx.creator).createLaunch(p, NO_VESTING))
                    .to.be.revertedWithCustomError(ctx.lf, "NotFactoryToken");
            }
            expect(await ctx.lf.tokenCheck(await ctx.token.getAddress())).to.equal(0n);
        });

        it("refuses tokens whose owner can mint, pause, blacklist, or that burn on transfer", async function () {
            const ctx = await loadFixture(fixture);
            const risky = [
                [true, false, false, false, 0, false, 0, 0], // mintable
                [false, false, true, false, 0, false, 0, 0], // pausable
                [false, false, false, true, 0, false, 0, 0], // blacklist (the honeypot switch)
                [false, true, false, false, 0, true, 100, 0], // auto-burn
            ];
            for (const flags of risky) {
                const t = await createToken(ctx.tokenFactory, ctx.creator.address, flags);
                const addr = await t.getAddress();
                expect(await ctx.lf.tokenCheck(addr)).to.equal(2n);
                const p = await params(ctx, { token: addr, seedQuote: 0n, ...BIG_SALE });
                await approveFor(ctx, p, NO_VESTING);
                await expect(ctx.lf.connect(ctx.creator).createLaunch(p, NO_VESTING))
                    .to.be.revertedWithCustomError(ctx.lf, "RiskyToken");
            }
            // burnable alone is harmless (holders burn their own)
            const burnable = await createToken(ctx.tokenFactory, ctx.creator.address, [false, true, false, false, 0, false, 0, 0]);
            expect(await ctx.lf.tokenCheck(await burnable.getAddress())).to.equal(0n);
        });

        it("needs at least half of every purchase to go into the pool", async function () {
            const ctx = await loadFixture(fixture);
            const p = await params(ctx, { poolShareBps: 4_999 });
            await expect(ctx.lf.connect(ctx.creator).createLaunch(p, vesting(ctx, p.startTime)))
                .to.be.revertedWithCustomError(ctx.lf, "BadConfig");
            await launch(ctx, { poolShareBps: 5_000 }); // the floor itself is fine
        });

        it("refuses when the creator would keep more than 20% of the supply unlocked", async function () {
            const ctx = await loadFixture(fixture);
            // no vesting: sale 100B + reserve 100B = 18.18% of 1.1T locked
            const p = await params(ctx);
            await approveFor(ctx, p, NO_VESTING);
            await expect(ctx.lf.connect(ctx.creator).createLaunch(p, NO_VESTING))
                .to.be.revertedWithCustomError(ctx.lf, "TooMuchUnlocked").withArgs(1_818n);
        });

        it("does not count vesting that is already free when the LP unlocks", async function () {
            const ctx = await loadFixture(fixture);
            const p = await params(ctx);
            // 770B "vested" over one month — all of it free long before the LP unlocks
            const quick = vesting(ctx, p.startTime, { tranches: [{ amount: 770n * B, cliffPeriods: 0, releasePeriods: 1 }] });
            await approveFor(ctx, p, quick);
            await expect(ctx.lf.connect(ctx.creator).createLaunch(p, quick))
                .to.be.revertedWithCustomError(ctx.lf, "TooMuchUnlocked");
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
            const { sale, feeder } = await launch(ctx, { poolShareBps: 5_000, feederReserve: reserve, saleCap: 200n * B });
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

        it("stops every feed — owner included — while the pool is out of band, and resumes once arbitrage brings it back", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 100n * USDT);
            const tokens = await ctx.token.balanceOf(ctx.buyer.address);
            await sell(ctx, ctx.buyer, tokens / 10n); // dumps the 10-USDT pool well below the band

            expect(await feeder.poolVsSaleBps()).to.be.gt(10_300n);
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "OutOfBand");
            await expect(feeder.connect(ctx.creator).feed()).to.be.revertedWithCustomError(feeder, "OutOfBand");
            expect(feeder.interface.getFunction("feedWithReference")).to.equal(null);

            // the pool is now cheaper than the sale: buyers take it from the pool until it is back in band
            for (let i = 0; i < 60 && (await feeder.poolVsSaleBps()) > 10_300n; i++) {
                await buyFromPool(ctx, ctx.attacker, USDT / 2n);
            }
            expect(await feeder.poolVsSaleBps()).to.be.lte(10_300n);
            await expect(feeder.feed()).to.emit(feeder, "Fed");
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

        it("buyFor: the payer pays, the buyer gets the tokens in the same tx, the wallet limit counts the buyer", async function () {
            const ctx = await loadFixture(fixture);
            const { sale, feeder } = await launch(ctx);
            await feeder.connect(ctx.creator).setSaleLimits(0n, (150n * USDT * NUM) / DEN); // 150 USDT worth per wallet
            await time.increaseTo((await sale.startTime()) + 1n);
            const agent = ctx.attacker; // stands in for the server's sale agent
            await ctx.usdt.connect(agent).approve(await sale.getAddress(), 1_000n * USDT);
            const payBefore = await ctx.usdt.balanceOf(agent.address);

            await expect(sale.connect(agent).buyFor(ctx.buyer.address, 100n * USDT))
                .to.emit(sale, "Purchased").withArgs(ctx.buyer.address, 100n * USDT, (100n * USDT * NUM) / DEN);
            expect(await ctx.token.balanceOf(ctx.buyer.address)).to.equal((100n * USDT * NUM) / DEN);
            expect(await ctx.token.balanceOf(agent.address)).to.equal(0n);
            expect(payBefore - (await ctx.usdt.balanceOf(agent.address))).to.equal(100n * USDT);
            expect(await sale.purchased(ctx.buyer.address)).to.equal((100n * USDT * NUM) / DEN);
            expect(await sale.purchased(agent.address)).to.equal(0n);

            // the limit is the buyer's, not the agent's: 100 + 100 > 150 for this buyer, another buyer is fine
            await expect(sale.connect(agent).buyFor(ctx.buyer.address, 100n * USDT))
                .to.be.revertedWithCustomError(sale, "WalletLimitExceeded");
            await sale.connect(agent).buyFor(ctx.project.address, 100n * USDT);
            await expect(sale.connect(agent).buyFor(ethers.ZeroAddress, 1n * USDT))
                .to.be.revertedWithCustomError(sale, "ZeroAddress");
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
            expect(await feeder.saleEndLimit()).to.equal(p.endTime);
            await expect(feeder.connect(ctx.attacker).pauseSale()).to.be.revertedWithCustomError(feeder, "OwnableUnauthorizedAccount");
        });

        it("unpaired proceeds and the reserve stay until the LP unlocks, the reserve only once no proceeds wait", async function () {
            const ctx = await loadFixture(fixture);
            const { p, sale, feeder } = await launch(ctx);
            await time.increaseTo((await sale.startTime()) + 1n);
            await buy(ctx, sale, ctx.buyer, 100n * USDT);
            const tokens = await ctx.token.balanceOf(ctx.buyer.address);
            await sell(ctx, ctx.buyer, tokens / 10n); // out of band: the 100 USDT cannot be fed by anyone
            await expect(feeder.feed()).to.be.revertedWithCustomError(feeder, "OutOfBand");

            await time.increaseTo(p.endTime);
            const f = feeder.connect(ctx.creator);
            await expect(f.withdrawReserve(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await expect(f.withdrawLeftoverQuote(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await time.increaseTo(p.lpUnlockTime);
            await expect(f.withdrawReserve(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "QuotePending");
            await expect(f.withdrawLeftoverQuote(ctx.creator.address)).to.emit(feeder, "ReserveWithdrawn");
            await expect(f.withdrawReserve(ctx.creator.address)).to.emit(feeder, "ReserveWithdrawn");
        });

        it("unsold sale tokens stay locked until the LP unlocks — pausing the sale does not free them", async function () {
            const ctx = await loadFixture(fixture);
            const { p, sale, feeder } = await launch(ctx);
            const f = feeder.connect(ctx.creator);
            await f.pauseSale(); // FixedPriceSale itself would allow withdrawUnsold while paused
            await expect(f.withdrawUnsold(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await time.increaseTo(p.endTime);
            await expect(f.withdrawUnsold(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await time.increaseTo(p.lpUnlockTime);
            await f.withdrawUnsold(ctx.creator.address);
            expect(await ctx.token.balanceOf(await sale.getAddress())).to.equal(0n);
        });
    });

    describe("locks", function () {
        it("holds the LP and the reserve until lpUnlockTime", async function () {
            const ctx = await loadFixture(fixture);
            const { p, feeder } = await launch(ctx);
            const f = feeder.connect(ctx.creator);
            await expect(f.withdrawLiquidity(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await expect(f.withdrawReserve(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");

            await time.increaseTo(p.endTime);
            await expect(f.withdrawReserve(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");
            await expect(f.withdrawLiquidity(ctx.creator.address)).to.be.revertedWithCustomError(feeder, "StillLocked");

            await time.increaseTo(p.lpUnlockTime);
            await expect(feeder.connect(ctx.attacker).withdrawLiquidity(ctx.attacker.address))
                .to.be.revertedWithCustomError(feeder, "OwnableUnauthorizedAccount");
            const reserve = await feeder.tokenReserve();
            await expect(f.withdrawReserve(ctx.creator.address)).to.emit(feeder, "ReserveWithdrawn").withArgs(ctx.creator.address, reserve, 0n);
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
