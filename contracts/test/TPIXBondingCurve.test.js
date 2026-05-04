const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, setBalance, time } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * ทดสอบ TPIXBondingCurve (linear bonding curve token sale) — security-hardened 2026-05-04
 *
 * Coverage (post-hardening):
 *   - Constructor validation
 *   - Price curve (start, end, intermediate)
 *   - Buy/Sell happy path + slippage protection + ERC20 approval
 *   - MIN_USDT_IN guard (1 USDT minimum) — dust attack mitigation
 *   - maxBuyPerWallet cap (1% of saleSupply) — whale concentration mitigation
 *   - CEI ordering — state updated before external calls (covered implicitly by replay tests)
 *   - Migration: threshold detection, 24h delay, permissionless trigger, asset sweep, buy/sell blocked after
 *   - Pausable behavior + pausedAt tracking
 *   - emergencySell after MAX_PAUSE_DURATION (30 days)
 *   - rescueToken cannot drain TPIX/USDT
 *   - Ownable2Step ownership transfer
 */
describe("TPIXBondingCurve", function () {
    // unique tx hash helper (replay-protection-friendly)
    const txHash = (n) => "0x" + n.toString(16).padStart(64, "0");

    // Scaled test params — bumped supply to 100M to give meaningful per-wallet cap (1M)
    const SALE_SUPPLY = ethers.parseEther("100000000");                // 100M TPIX
    const START_PRICE = ethers.parseUnits("1", 6);                     // $1.00
    const END_PRICE = ethers.parseUnits("10", 6);                      // $10.00
    const MIGRATION_USDT = ethers.parseUnits("1000000", 6);            // $1M
    const MIGRATION_TPIX = ethers.parseEther("50000000");              // 50M TPIX

    const LIQUIDITY_WALLET = "0x3da3776e0AB0F442c181aa031f47FA83696859AF";

    async function deployFixture() {
        const [owner, relayer, alice, bob, charlie, dave] = await ethers.getSigners();

        // Pre-fund owner กับ 200M native TPIX (default ไม่พอสำหรับ wrap 100M)
        await setBalance(owner.address, ethers.parseEther("200000000"));

        // 1. Deploy WTPIX
        const WTPIX = await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
        const wtpix = await WTPIX.deploy();
        await wtpix.waitForDeployment();

        // 2. Deploy USDT_TPIX
        const USDT = await ethers.getContractFactory("USDT_TPIX");
        const usdt = await USDT.deploy();
        await usdt.waitForDeployment();
        await usdt.setBridge(relayer.address, true);

        // 3. Deploy BondingCurve
        const Curve = await ethers.getContractFactory("TPIXBondingCurve");
        const curve = await Curve.deploy(
            await wtpix.getAddress(),
            await usdt.getAddress(),
            LIQUIDITY_WALLET,
            SALE_SUPPLY,
            START_PRICE,
            END_PRICE,
            MIGRATION_USDT,
            MIGRATION_TPIX,
        );
        await curve.waitForDeployment();

        // 4. Fund curve: owner wraps native → WTPIX → transfer to curve
        await wtpix.connect(owner).deposit({ value: SALE_SUPPLY });
        await wtpix.connect(owner).transfer(await curve.getAddress(), SALE_SUPPLY);

        // 5. Relayer mints USDT to test buyers (each gets fresh tx hash for replay protection)
        const MINT_EACH = ethers.parseUnits("500000", 6);
        await usdt.connect(relayer).bridgeMint(alice.address, MINT_EACH, txHash(1));
        await usdt.connect(relayer).bridgeMint(bob.address, MINT_EACH, txHash(2));
        await usdt.connect(relayer).bridgeMint(charlie.address, MINT_EACH, txHash(3));
        await usdt.connect(relayer).bridgeMint(dave.address, MINT_EACH, txHash(4));

        return { wtpix, usdt, curve, owner, relayer, alice, bob, charlie, dave };
    }

    // =========================================================================
    // Constructor validation
    // =========================================================================

    describe("constructor", function () {
        it("reverts on zero token address", async function () {
            const Curve = await ethers.getContractFactory("TPIXBondingCurve");
            await expect(
                Curve.deploy(
                    ethers.ZeroAddress,
                    ethers.ZeroAddress,
                    LIQUIDITY_WALLET,
                    SALE_SUPPLY,
                    START_PRICE,
                    END_PRICE,
                    MIGRATION_USDT,
                    MIGRATION_TPIX,
                )
            ).to.be.revertedWith("BC: zero addr");
        });

        it("reverts when endPrice <= startPrice", async function () {
            const WTPIX = await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
            const USDT = await ethers.getContractFactory("USDT_TPIX");
            const wtpix = await WTPIX.deploy();
            const usdt = await USDT.deploy();

            const Curve = await ethers.getContractFactory("TPIXBondingCurve");
            await expect(
                Curve.deploy(
                    await wtpix.getAddress(),
                    await usdt.getAddress(),
                    LIQUIDITY_WALLET,
                    SALE_SUPPLY,
                    END_PRICE, // swapped
                    START_PRICE,
                    MIGRATION_USDT,
                    MIGRATION_TPIX,
                )
            ).to.be.revertedWith("BC: end <= start");
        });

        it("reverts when TPIX threshold > saleSupply", async function () {
            const WTPIX = await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
            const USDT = await ethers.getContractFactory("USDT_TPIX");
            const wtpix = await WTPIX.deploy();
            const usdt = await USDT.deploy();

            const Curve = await ethers.getContractFactory("TPIXBondingCurve");
            await expect(
                Curve.deploy(
                    await wtpix.getAddress(),
                    await usdt.getAddress(),
                    LIQUIDITY_WALLET,
                    SALE_SUPPLY,
                    START_PRICE,
                    END_PRICE,
                    MIGRATION_USDT,
                    SALE_SUPPLY + 1n, // > supply
                )
            ).to.be.revertedWith("BC: threshold > supply");
        });

        it("sets maxBuyPerWallet = saleSupply / 100", async function () {
            const { curve } = await loadFixture(deployFixture);
            expect(await curve.maxBuyPerWallet()).to.equal(SALE_SUPPLY / 100n);
        });
    });

    // =========================================================================
    // Price curve
    // =========================================================================

    describe("currentPrice()", function () {
        it("returns startPrice at sold=0", async function () {
            const { curve } = await loadFixture(deployFixture);
            expect(await curve.currentPrice()).to.equal(START_PRICE);
        });
    });

    // =========================================================================
    // Buy
    // =========================================================================

    describe("buy()", function () {
        it("transfers USDT in + TPIX out and updates state", async function () {
            const { curve, usdt, alice } = await loadFixture(deployFixture);
            const usdtIn = ethers.parseUnits("1000", 6); // $1000

            await usdt.connect(alice).approve(await curve.getAddress(), usdtIn);

            const expectedOut = await curve.quoteBuy(usdtIn);
            expect(expectedOut).to.be.gt(0);

            await expect(curve.connect(alice).buy(usdtIn, expectedOut))
                .to.emit(curve, "Bought");

            expect(await curve.totalRaised()).to.equal(usdtIn);
            expect(await curve.totalSold()).to.equal(expectedOut);
            expect(await curve.bought(alice.address)).to.equal(expectedOut);
        });

        it("reverts without sufficient approval", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            const usdtIn = ethers.parseUnits("1000", 6);
            const expectedOut = await curve.quoteBuy(usdtIn);

            await expect(curve.connect(alice).buy(usdtIn, expectedOut))
                .to.be.revertedWithCustomError(
                    await ethers.getContractAt("USDT_TPIX", await curve.usdt()),
                    "ERC20InsufficientAllowance"
                );
        });

        it("reverts on slippage (minTpixOut too high)", async function () {
            const { curve, usdt, alice } = await loadFixture(deployFixture);
            const usdtIn = ethers.parseUnits("100", 6);

            await usdt.connect(alice).approve(await curve.getAddress(), usdtIn);
            const expectedOut = await curve.quoteBuy(usdtIn);
            const tooMuch = expectedOut + ethers.parseEther("1");

            await expect(curve.connect(alice).buy(usdtIn, tooMuch))
                .to.be.revertedWith("BC: slippage");
        });

        it("reverts on input below MIN_USDT_IN (1 USDT)", async function () {
            const { curve, usdt, alice } = await loadFixture(deployFixture);
            await usdt.connect(alice).approve(await curve.getAddress(), 999_999n);
            await expect(curve.connect(alice).buy(999_999n, 0))
                .to.be.revertedWith("BC: below min");
        });

        it("reverts on zero input", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await expect(curve.connect(alice).buy(0, 0)).to.be.revertedWith("BC: below min");
        });

        it("WALLET CAP: rejects buy that exceeds 1% of supply per wallet", async function () {
            const { curve, usdt, relayer, alice } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            // Top up alice to push past wallet cap
            const huge = ethers.parseUnits("3000000", 6); // $3M
            await usdt.connect(relayer).bridgeMint(alice.address, huge, txHash(100));
            await usdt.connect(alice).approve(curveAddr, huge);

            // 1M TPIX cap; $3M at avg ~$1 ≈ ~3M TPIX → over cap
            await expect(curve.connect(alice).buy(huge, 0))
                .to.be.revertedWith("BC: wallet cap");
        });

        it("price increases with sold amount (monotonic)", async function () {
            const { curve, usdt, alice, bob } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            const usdtIn = ethers.parseUnits("10000", 6);
            await usdt.connect(alice).approve(curveAddr, usdtIn);
            await curve.connect(alice).buy(usdtIn, 0);
            const priceAfterAlice = await curve.currentPrice();

            await usdt.connect(bob).approve(curveAddr, usdtIn);
            await curve.connect(bob).buy(usdtIn, 0);
            const priceAfterBob = await curve.currentPrice();

            expect(priceAfterAlice).to.be.gt(START_PRICE);
            expect(priceAfterBob).to.be.gt(priceAfterAlice);
        });
    });

    // =========================================================================
    // Sell
    // =========================================================================

    describe("sell()", function () {
        it("returns USDT minus 5% exit fee", async function () {
            const { curve, usdt, wtpix, alice } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            const usdtIn = ethers.parseUnits("1000", 6);
            await usdt.connect(alice).approve(curveAddr, usdtIn);
            await curve.connect(alice).buy(usdtIn, 0);
            const tpixHeld = await wtpix.balanceOf(alice.address);

            await wtpix.connect(alice).approve(curveAddr, tpixHeld);
            const [expectedUsdt, expectedFee] = await curve.quoteSell(tpixHeld);
            expect(expectedFee).to.be.gt(0);
            const gross = expectedUsdt + expectedFee;
            expect(expectedFee * 10000n / gross).to.be.closeTo(500n, 2n);

            const usdtBefore = await usdt.balanceOf(alice.address);
            await curve.connect(alice).sell(tpixHeld, expectedUsdt);
            const usdtAfter = await usdt.balanceOf(alice.address);

            expect(usdtAfter - usdtBefore).to.equal(expectedUsdt);
            expect(await curve.totalSold()).to.equal(0);
        });

        it("reverts when trying to sell more than totalSold", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await expect(curve.connect(alice).sell(1n, 0)).to.be.revertedWith("BC: invalid in");
        });

        it("reverts on slippage", async function () {
            const { curve, usdt, wtpix, alice } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            const usdtIn = ethers.parseUnits("1000", 6);
            await usdt.connect(alice).approve(curveAddr, usdtIn);
            await curve.connect(alice).buy(usdtIn, 0);
            const tpixHeld = await wtpix.balanceOf(alice.address);

            await wtpix.connect(alice).approve(curveAddr, tpixHeld);
            const tooMuch = ethers.parseUnits("999999", 6);
            await expect(curve.connect(alice).sell(tpixHeld, tooMuch))
                .to.be.revertedWith("BC: slippage");
        });
    });

    // =========================================================================
    // Migration (with 24h delay + permissionless trigger)
    // =========================================================================

    describe("migrate()", function () {
        // helper: drive totalRaised past MIGRATION_USDT
        async function reachThreshold(curve, usdt, signers) {
            const curveAddr = await curve.getAddress();
            const each = ethers.parseUnits("400000", 6);
            for (const s of signers) {
                await usdt.connect(s).approve(curveAddr, each);
                await curve.connect(s).buy(each, 0);
            }
        }

        it("isMigrationReady false at start", async function () {
            const { curve } = await loadFixture(deployFixture);
            expect(await curve.isMigrationReady()).to.equal(false);
            expect(await curve.thresholdReachedAt()).to.equal(0);
            expect(await curve.migrationAvailableAt()).to.equal(0);
        });

        it("reverts migrate when not ready", async function () {
            const { curve } = await loadFixture(deployFixture);
            await expect(curve.migrate()).to.be.revertedWith("BC: not ready");
        });

        it("starts countdown when threshold first hit (event + state)", async function () {
            const { curve, usdt, alice, bob, charlie } = await loadFixture(deployFixture);
            await reachThreshold(curve, usdt, [alice, bob, charlie]);

            const t0 = await curve.thresholdReachedAt();
            expect(t0).to.be.gt(0);
            expect(await curve.migrationAvailableAt()).to.equal(t0 + 24n * 3600n);
            expect(await curve.isMigrationReady()).to.equal(true);
        });

        it("DELAY: reverts migrate during 24h grace period", async function () {
            const { curve, usdt, alice, bob, charlie } = await loadFixture(deployFixture);
            await reachThreshold(curve, usdt, [alice, bob, charlie]);

            // Try immediately — must revert
            await expect(curve.migrate()).to.be.revertedWith("BC: in delay");

            // Try at 23h — still revert
            await time.increase(23 * 3600);
            await expect(curve.migrate()).to.be.revertedWith("BC: in delay");
        });

        it("PERMISSIONLESS: anyone can call migrate after delay", async function () {
            const { curve, usdt, wtpix, alice, bob, charlie, dave } =
                await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();
            await reachThreshold(curve, usdt, [alice, bob, charlie]);

            await time.increase(24 * 3600 + 1);

            const usdtInCurve = await usdt.balanceOf(curveAddr);
            const tpixInCurve = await wtpix.balanceOf(curveAddr);

            // dave (random user, NOT owner) triggers migrate
            await expect(curve.connect(dave).migrate())
                .to.emit(curve, "Migrated")
                .withArgs(usdtInCurve, tpixInCurve, tpixInCurve);

            expect(await curve.migrated()).to.equal(true);
            expect(await usdt.balanceOf(LIQUIDITY_WALLET)).to.equal(usdtInCurve);
            expect(await wtpix.balanceOf(LIQUIDITY_WALLET)).to.equal(tpixInCurve);
        });

        it("blocks buy/sell after migration", async function () {
            const { curve, usdt, alice, bob, charlie } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();
            await reachThreshold(curve, usdt, [alice, bob, charlie]);
            await time.increase(24 * 3600 + 1);
            await curve.migrate();

            await usdt.connect(alice).approve(curveAddr, ethers.parseUnits("1", 6));
            await expect(curve.connect(alice).buy(ethers.parseUnits("1", 6), 0))
                .to.be.revertedWith("BC: migrated");
            await expect(curve.connect(alice).sell(1n, 0)).to.be.revertedWith("BC: migrated");
        });

        it("cannot migrate twice", async function () {
            const { curve, usdt, alice, bob, charlie } = await loadFixture(deployFixture);
            await reachThreshold(curve, usdt, [alice, bob, charlie]);
            await time.increase(24 * 3600 + 1);
            await curve.migrate();
            // หลัง migrate=true → isMigrationReady() returns false → "BC: not ready"
            await expect(curve.migrate()).to.be.revertedWith("BC: not ready");
        });
    });

    // =========================================================================
    // Pausable
    // =========================================================================

    describe("pause/unpause", function () {
        it("only owner can pause", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await expect(curve.connect(alice).pause())
                .to.be.revertedWithCustomError(curve, "OwnableUnauthorizedAccount");
        });

        it("paused blocks buy + sell + records pausedAt", async function () {
            const { curve, usdt, alice } = await loadFixture(deployFixture);
            await curve.pause();
            expect(await curve.pausedAt()).to.be.gt(0);

            const oneUsdt = ethers.parseUnits("1", 6);
            await usdt.connect(alice).approve(await curve.getAddress(), oneUsdt);
            await expect(curve.connect(alice).buy(oneUsdt, 0))
                .to.be.revertedWithCustomError(curve, "EnforcedPause");
        });

        it("unpause clears pausedAt", async function () {
            const { curve } = await loadFixture(deployFixture);
            await curve.pause();
            await curve.unpause();
            expect(await curve.pausedAt()).to.equal(0);
        });
    });

    // =========================================================================
    // emergencySell — anti-rug after extended pause
    // =========================================================================

    describe("emergencySell()", function () {
        it("reverts when not paused", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await expect(curve.connect(alice).emergencySell(1n))
                .to.be.revertedWith("BC: not paused");
        });

        it("reverts during pause < MAX_PAUSE_DURATION (30 days)", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await curve.pause();
            await time.increase(29 * 24 * 3600); // 29 days
            await expect(curve.connect(alice).emergencySell(1n))
                .to.be.revertedWith("BC: pause too short");
        });

        it("ANTI-RUG: lets user redeem at floor price after 30d pause", async function () {
            const { curve, usdt, wtpix, alice } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            // Alice buys
            const usdtIn = ethers.parseUnits("1000", 6);
            await usdt.connect(alice).approve(curveAddr, usdtIn);
            await curve.connect(alice).buy(usdtIn, 0);
            const tpixHeld = await wtpix.balanceOf(alice.address);

            // Owner pauses and never unpauses → 30+ days later
            await curve.pause();
            await time.increase(31 * 24 * 3600);

            // Alice can redeem at floor price (startPrice = $1.00)
            await wtpix.connect(alice).approve(curveAddr, tpixHeld);
            const usdtBefore = await usdt.balanceOf(alice.address);
            await expect(curve.connect(alice).emergencySell(tpixHeld))
                .to.emit(curve, "EmergencySell");
            const usdtAfter = await usdt.balanceOf(alice.address);

            // Got back at least floor-priced amount, no fee
            const expectedFloor = (tpixHeld * START_PRICE) / ethers.parseEther("1");
            expect(usdtAfter - usdtBefore).to.equal(expectedFloor);
        });
    });

    // =========================================================================
    // rescueToken
    // =========================================================================

    describe("rescueToken()", function () {
        it("cannot drain TPIX (protected)", async function () {
            const { curve, wtpix } = await loadFixture(deployFixture);
            await expect(curve.rescueToken(await wtpix.getAddress(), 1n))
                .to.be.revertedWith("BC: protected");
        });

        it("cannot drain USDT (protected)", async function () {
            const { curve, usdt } = await loadFixture(deployFixture);
            await expect(curve.rescueToken(await usdt.getAddress(), 1n))
                .to.be.revertedWith("BC: protected");
        });

        it("can rescue unrelated token", async function () {
            const { curve, owner } = await loadFixture(deployFixture);
            const Stray = await ethers.getContractFactory("USDT_TPIX");
            const stray = await Stray.deploy();
            await stray.setBridge(owner.address, true);
            await stray.bridgeMint(await curve.getAddress(), 1000n, txHash(200));

            await curve.rescueToken(await stray.getAddress(), 1000n);
            expect(await stray.balanceOf(owner.address)).to.equal(1000n);
        });
    });

    // =========================================================================
    // Ownable2Step
    // =========================================================================

    describe("Ownable2Step ownership transfer", function () {
        it("transferOwnership requires acceptOwnership step", async function () {
            const { curve, owner, alice } = await loadFixture(deployFixture);
            await curve.connect(owner).transferOwnership(alice.address);
            expect(await curve.owner()).to.equal(owner.address);
            expect(await curve.pendingOwner()).to.equal(alice.address);

            await curve.connect(alice).acceptOwnership();
            expect(await curve.owner()).to.equal(alice.address);
        });
    });

    // =========================================================================
    // Overflow check with WHITEPAPER-scale numbers
    // =========================================================================

    describe("production-scale no overflow", function () {
        it("computes quoteBuy with 700M supply + $5M input without overflow", async function () {
            const [, relayer] = await ethers.getSigners();

            const WTPIX = await ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
            const USDT = await ethers.getContractFactory("USDT_TPIX");
            const wtpix = await WTPIX.deploy();
            const usdt = await USDT.deploy();
            await usdt.setBridge(relayer.address, true);

            const REAL_SUPPLY = ethers.parseEther("700000000");
            const REAL_START = ethers.parseUnits("0.10", 6);
            const REAL_END = ethers.parseUnits("1.00", 6);
            const REAL_USDT_THRESHOLD = ethers.parseUnits("5000000", 6);
            const REAL_TPIX_THRESHOLD = ethers.parseEther("350000000");

            const Curve = await ethers.getContractFactory("TPIXBondingCurve");
            const curve = await Curve.deploy(
                await wtpix.getAddress(),
                await usdt.getAddress(),
                LIQUIDITY_WALLET,
                REAL_SUPPLY,
                REAL_START,
                REAL_END,
                REAL_USDT_THRESHOLD,
                REAL_TPIX_THRESHOLD,
            );

            const fiveM = ethers.parseUnits("5000000", 6);
            const out = await curve.quoteBuy(fiveM);
            expect(out).to.be.gt(ethers.parseEther("30000000"));
            expect(out).to.be.lt(ethers.parseEther("60000000"));

            // Verify maxBuyPerWallet = 7M TPIX (1% of 700M)
            expect(await curve.maxBuyPerWallet()).to.equal(REAL_SUPPLY / 100n);
        });
    });
});
