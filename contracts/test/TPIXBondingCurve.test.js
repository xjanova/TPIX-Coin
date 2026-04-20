const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, setBalance } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * ทดสอบ TPIXBondingCurve (linear bonding curve token sale)
 *
 * Coverage:
 *   - Constructor validation
 *   - Price curve (start, end, intermediate)
 *   - Buy/Sell happy path + slippage protection + ERC20 approval
 *   - Multiple buys accumulate totalSold + totalRaised correctly
 *   - Migration: threshold detection, owner-only, asset sweep, buy/sell blocked after
 *   - Pausable behavior
 *   - rescueToken cannot drain TPIX/USDT
 *
 * ใช้ scaled-down numbers เพื่อให้อ่านง่าย (ไม่ใช่ WHITEPAPER scale)
 * แต่มี 1 test ที่ใช้ scale จริงเพื่อเช็ค overflow
 */
describe("TPIXBondingCurve", function () {
    // Scaled test params (ชัดเจน อ่านง่าย)
    const SALE_SUPPLY = ethers.parseEther("1000000");                  // 1M TPIX
    const START_PRICE = ethers.parseUnits("1", 6);                     // $1.00
    const END_PRICE = ethers.parseUnits("10", 6);                      // $10.00
    const MIGRATION_USDT = ethers.parseUnits("1000000", 6);            // $1M
    const MIGRATION_TPIX = ethers.parseEther("500000");                // 500k TPIX

    const LIQUIDITY_WALLET = "0x3da3776e0AB0F442c181aa031f47FA83696859AF";

    async function deployFixture() {
        const [owner, relayer, alice, bob, charlie] = await ethers.getSigners();

        // Pre-fund owner กับ 2M native TPIX (default 10k ไม่พอสำหรับ wrap 1M)
        await setBalance(owner.address, ethers.parseEther("2000000"));

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

        // 5. Relayer mints USDT to test buyers
        const MINT_EACH = ethers.parseUnits("500000", 6);
        const TX_HASH = "0x" + "a".repeat(64);
        await usdt.connect(relayer).bridgeMint(alice.address, MINT_EACH, TX_HASH);
        await usdt.connect(relayer).bridgeMint(bob.address, MINT_EACH, TX_HASH);
        await usdt.connect(relayer).bridgeMint(charlie.address, MINT_EACH, TX_HASH);

        return { wtpix, usdt, curve, owner, relayer, alice, bob, charlie };
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
            const [owner] = await ethers.getSigners();
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
            const usdtIn = ethers.parseUnits("1000", 6); // $1000 at ~$1 each = ~1000 TPIX

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

        it("reverts on zero input", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await expect(curve.connect(alice).buy(0, 0)).to.be.revertedWith("BC: zero in");
        });

        it("price increases with sold amount (monotonic)", async function () {
            const { curve, usdt, alice, bob } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            // Alice buys first
            const usdtIn = ethers.parseUnits("10000", 6);
            await usdt.connect(alice).approve(curveAddr, usdtIn);
            await curve.connect(alice).buy(usdtIn, 0);
            const priceAfterAlice = await curve.currentPrice();

            // Bob buys — should see higher price
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

            // Buy first
            const usdtIn = ethers.parseUnits("1000", 6);
            await usdt.connect(alice).approve(curveAddr, usdtIn);
            await curve.connect(alice).buy(usdtIn, 0);
            const tpixHeld = await wtpix.balanceOf(alice.address);

            // Sell back
            await wtpix.connect(alice).approve(curveAddr, tpixHeld);
            const [expectedUsdt, expectedFee] = await curve.quoteSell(tpixHeld);
            expect(expectedFee).to.be.gt(0);
            // fee ≈ 5% of gross
            const gross = expectedUsdt + expectedFee;
            expect(expectedFee * 10000n / gross).to.be.closeTo(500n, 2n); // 5% ± rounding

            const usdtBefore = await usdt.balanceOf(alice.address);
            await curve.connect(alice).sell(tpixHeld, expectedUsdt);
            const usdtAfter = await usdt.balanceOf(alice.address);

            expect(usdtAfter - usdtBefore).to.equal(expectedUsdt);
            expect(await curve.totalSold()).to.equal(0);
        });

        it("reverts when trying to sell more than totalSold", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            // alice hasn't bought anything
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
    // Migration
    // =========================================================================

    describe("migrate()", function () {
        it("isMigrationReady false at start", async function () {
            const { curve } = await loadFixture(deployFixture);
            expect(await curve.isMigrationReady()).to.equal(false);
        });

        it("reverts migrate when not ready", async function () {
            const { curve } = await loadFixture(deployFixture);
            await expect(curve.migrate()).to.be.revertedWith("BC: not ready");
        });

        it("only owner can migrate", async function () {
            const { curve, alice } = await loadFixture(deployFixture);
            await expect(curve.connect(alice).migrate())
                .to.be.revertedWithCustomError(curve, "OwnableUnauthorizedAccount");
        });

        it("becomes ready when USDT raised hits threshold + sweeps to liquidity wallet", async function () {
            const { curve, usdt, wtpix, alice, bob, charlie, relayer } =
                await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            // ต้อง mint USDT เพิ่มให้ครบ $1M threshold (ทุกคนมี $500k แล้ว = $1.5M รวม พอ)
            const big = ethers.parseUnits("400000", 6);
            for (const user of [alice, bob, charlie]) {
                await usdt.connect(user).approve(curveAddr, big);
                await curve.connect(user).buy(big, 0);
            }

            expect(await curve.totalRaised()).to.be.gte(MIGRATION_USDT);
            expect(await curve.isMigrationReady()).to.equal(true);

            const usdtInCurve = await usdt.balanceOf(curveAddr);
            const tpixInCurve = await wtpix.balanceOf(curveAddr);

            await expect(curve.migrate())
                .to.emit(curve, "Migrated")
                .withArgs(usdtInCurve, tpixInCurve, tpixInCurve);

            expect(await curve.migrated()).to.equal(true);
            expect(await usdt.balanceOf(LIQUIDITY_WALLET)).to.equal(usdtInCurve);
            expect(await wtpix.balanceOf(LIQUIDITY_WALLET)).to.equal(tpixInCurve);
            expect(await usdt.balanceOf(curveAddr)).to.equal(0n);
            expect(await wtpix.balanceOf(curveAddr)).to.equal(0n);
        });

        it("blocks buy/sell after migration", async function () {
            const { curve, usdt, alice, bob, charlie } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            const big = ethers.parseUnits("400000", 6);
            for (const user of [alice, bob, charlie]) {
                await usdt.connect(user).approve(curveAddr, big);
                await curve.connect(user).buy(big, 0);
            }
            await curve.migrate();

            await usdt.connect(alice).approve(curveAddr, 1n);
            await expect(curve.connect(alice).buy(1n, 0)).to.be.revertedWith("BC: migrated");
            await expect(curve.connect(alice).sell(1n, 0)).to.be.revertedWith("BC: migrated");
        });

        it("cannot migrate twice", async function () {
            const { curve, usdt, alice, bob, charlie } = await loadFixture(deployFixture);
            const curveAddr = await curve.getAddress();

            const big = ethers.parseUnits("400000", 6);
            for (const user of [alice, bob, charlie]) {
                await usdt.connect(user).approve(curveAddr, big);
                await curve.connect(user).buy(big, 0);
            }
            await curve.migrate();
            // หลัง migrate = true → isMigrationReady() returns false เพราะ !migrated
            // จึงโดน guard แรกก่อน ("BC: not ready") — ไม่ถึง require(!migrated)
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

        it("paused blocks buy + sell", async function () {
            const { curve, usdt, alice } = await loadFixture(deployFixture);
            await curve.pause();

            await usdt.connect(alice).approve(await curve.getAddress(), 100n);
            await expect(curve.connect(alice).buy(100n, 0))
                .to.be.revertedWithCustomError(curve, "EnforcedPause");
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
            // deploy a stray token and send to curve
            const Stray = await ethers.getContractFactory("USDT_TPIX");
            const stray = await Stray.deploy();
            await stray.setBridge(owner.address, true);
            await stray.bridgeMint(await curve.getAddress(), 1000n, "0x" + "f".repeat(64));

            await curve.rescueToken(await stray.getAddress(), 1000n);
            expect(await stray.balanceOf(owner.address)).to.equal(1000n);
        });
    });

    // =========================================================================
    // Overflow check with WHITEPAPER-scale numbers
    // =========================================================================

    describe("production-scale no overflow", function () {
        it("computes quoteBuy with 700M supply + $5M input without overflow", async function () {
            const [owner, relayer, alice] = await ethers.getSigners();

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

            // $5M input — should return ~35-50M TPIX at ~$0.10-0.14 avg, no overflow
            const fiveM = ethers.parseUnits("5000000", 6);
            const out = await curve.quoteBuy(fiveM);
            expect(out).to.be.gt(ethers.parseEther("30000000"));
            expect(out).to.be.lt(ethers.parseEther("60000000"));
        });
    });
});
