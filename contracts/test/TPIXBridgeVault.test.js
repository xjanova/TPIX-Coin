const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time, setBalance } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

/**
 * ทดสอบ TPIXBridgeVault — คลังล็อก TPIX บน TPIX Chain ของสะพาน TPIX ↔ wTPIX (BSC)
 *
 * สิ่งที่ต้องจริงเสมอ:
 *   - ล็อกได้ทั้งเรียก lock() และโอนตรงเข้าที่อยู่ (แอปเดิมส่งเข้า "treasury") ภายในช่วง min/max
 *   - relayer ปล่อยได้ภายใต้ maxPerTx + dailyCap เท่านั้น และ depositId เดียวปล่อยได้ครั้งเดียว
 *   - ไม่มีทางให้ใครถอนเงินออกนอกจาก release()
 *   - หยุดอยู่ = ไม่รับล็อกและไม่ปล่อยเงิน
 *
 * ท้ายไฟล์มีเทสต์ไปกลับครบวงจร (ล็อก → mint wTPIX → เผา → ปล่อย) บนเชนเดียว
 */
describe("TPIXBridgeVault", function () {
    const T = (n) => ethers.parseEther(String(n));
    const MIN_LOCK = T(10);
    const MAX_LOCK = T(100_000);
    const MAX_PER_TX = T(100_000);
    const DAILY_CAP = T(500_000);
    const dep = (n, chainId = 56) => ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "bytes32", "uint256"],
        [chainId, ethers.zeroPadValue(ethers.toBeHex(n), 32), 0],
    ));

    async function startOfNextUtcDay() {
        const now = await time.latest();
        await time.increaseTo((Math.floor(now / 86400) + 1) * 86400 + 60);
    }

    async function deployFixture() {
        const [owner, relayer, guardian, alice, bob, stranger] = await ethers.getSigners();

        const Vault = await ethers.getContractFactory("TPIXBridgeVault");
        const vault = await Vault.deploy(MIN_LOCK, MAX_LOCK, MAX_PER_TX, DAILY_CAP);
        await vault.waitForDeployment();

        await vault.setRelayer(relayer.address, true);
        await vault.setGuardian(guardian.address, true);

        // บัญชีทดสอบเริ่มที่ 10,000 — ไม่พอเติมคลังให้ถึงเพดานรายวัน 500,000
        await setBalance(alice.address, T(10_000_000));

        return { vault, owner, relayer, guardian, alice, bob, stranger };
    }

    /** ล็อกให้คลังมีเงินพอสำหรับเทสต์ปล่อย (ล็อกได้ครั้งละไม่เกิน MAX_LOCK) */
    async function fund(vault, signer, times) {
        for (let i = 0; i < times; i++) {
            await vault.connect(signer).lock({ value: MAX_LOCK });
        }
    }

    describe("deployment", function () {
        it("stores limits, caps and owner", async function () {
            const { vault, owner } = await loadFixture(deployFixture);
            expect(await vault.minLock()).to.equal(MIN_LOCK);
            expect(await vault.maxLock()).to.equal(MAX_LOCK);
            expect(await vault.maxPerTx()).to.equal(MAX_PER_TX);
            expect(await vault.dailyCap()).to.equal(DAILY_CAP);
            expect(await vault.owner()).to.equal(owner.address);
        });

        it("rejects invalid lock limits and caps", async function () {
            const Vault = await ethers.getContractFactory("TPIXBridgeVault");
            await expect(Vault.deploy(0, MAX_LOCK, MAX_PER_TX, DAILY_CAP)).to.be.revertedWithCustomError(Vault, "InvalidLockLimits");
            await expect(Vault.deploy(T(20), T(10), MAX_PER_TX, DAILY_CAP)).to.be.revertedWithCustomError(Vault, "InvalidLockLimits");
            await expect(Vault.deploy(MIN_LOCK, MAX_LOCK, DAILY_CAP + 1n, DAILY_CAP)).to.be.revertedWithCustomError(Vault, "InvalidCaps");
            await expect(Vault.deploy(MIN_LOCK, MAX_LOCK, 0, DAILY_CAP)).to.be.revertedWithCustomError(Vault, "InvalidCaps");
        });

        it("has no owner withdrawal path — funds leave only through release()", async function () {
            const { vault } = await loadFixture(deployFixture);
            const escapeHatches = vault.interface.fragments
                .filter((f) => f.type === "function")
                .map((f) => f.name)
                .filter((name) => /withdraw|sweep|rescue|drain|emergency|migrat/i.test(name));
            expect(escapeHatches).to.deep.equal([]);
        });
    });

    describe("lock()", function () {
        it("locks via lock() and emits Locked with an increasing nonce", async function () {
            const { vault, alice, bob } = await loadFixture(deployFixture);

            await expect(vault.connect(alice).lock({ value: T(1000) }))
                .to.emit(vault, "Locked").withArgs(alice.address, T(1000), 1n);
            await expect(vault.connect(bob).lock({ value: T(50) }))
                .to.emit(vault, "Locked").withArgs(bob.address, T(50), 2n);

            expect(await vault.totalLocked()).to.equal(T(1050));
            expect(await vault.lockNonce()).to.equal(2n);
            expect(await ethers.provider.getBalance(await vault.getAddress())).to.equal(T(1050));
        });

        it("a plain transfer to the vault address is a lock for the sender (old apps keep working)", async function () {
            const { vault, alice } = await loadFixture(deployFixture);
            await expect(alice.sendTransaction({ to: await vault.getAddress(), value: T(500) }))
                .to.emit(vault, "Locked").withArgs(alice.address, T(500), 1n);
            expect(await vault.totalLocked()).to.equal(T(500));
        });

        it("a plain transfer capped at 21000 gas fails instead of silently losing coins", async function () {
            const { vault, alice } = await loadFixture(deployFixture);
            const before = await ethers.provider.getBalance(alice.address);
            await expect(alice.sendTransaction({ to: await vault.getAddress(), value: T(500), gasLimit: 21000, gasPrice: 0 }))
                .to.be.reverted;
            expect(await vault.totalLocked()).to.equal(0n);
            // เชนทดสอบคิดแก๊ส 0 เหมือนของจริง — ยอดต้องไม่ขยับเลย
            expect(await ethers.provider.getBalance(alice.address)).to.equal(before);
        });

        it("enforces minLock and maxLock", async function () {
            const { vault, alice } = await loadFixture(deployFixture);
            await expect(vault.connect(alice).lock({ value: MIN_LOCK - 1n }))
                .to.be.revertedWithCustomError(vault, "BelowMinLock").withArgs(MIN_LOCK - 1n, MIN_LOCK);
            await expect(vault.connect(alice).lock({ value: MAX_LOCK + 1n }))
                .to.be.revertedWithCustomError(vault, "AboveMaxLock").withArgs(MAX_LOCK + 1n, MAX_LOCK);
            await expect(vault.connect(alice).lock({ value: MIN_LOCK })).to.not.be.reverted;
            await expect(vault.connect(alice).lock({ value: MAX_LOCK })).to.not.be.reverted;
        });

        it("refuses locks while paused (nobody would mint for them)", async function () {
            const { vault, guardian, alice } = await loadFixture(deployFixture);
            await vault.connect(guardian).pause();
            await expect(vault.connect(alice).lock({ value: T(100) }))
                .to.be.revertedWithCustomError(vault, "EnforcedPause");
            await expect(alice.sendTransaction({ to: await vault.getAddress(), value: T(100) }))
                .to.be.revertedWithCustomError(vault, "EnforcedPause");
        });
    });

    describe("release()", function () {
        it("releases TPIX to the recipient and emits Released", async function () {
            const { vault, relayer, alice, bob } = await loadFixture(deployFixture);
            await fund(vault, alice, 1);
            const id = dep(1);
            const before = await ethers.provider.getBalance(bob.address);

            await expect(vault.connect(relayer).release(bob.address, T(250), id))
                .to.emit(vault, "Released")
                .withArgs(relayer.address, bob.address, T(250), id, anyValue, T(250));

            expect(await ethers.provider.getBalance(bob.address)).to.equal(before + T(250));
            expect(await vault.processed(id)).to.equal(true);
            expect(await vault.totalReleased()).to.equal(T(250));
            expect(await vault.remainingToday()).to.equal(DAILY_CAP - T(250));
        });

        it("refuses anyone who is not a relayer — including the owner", async function () {
            const { vault, owner, stranger, alice } = await loadFixture(deployFixture);
            await fund(vault, alice, 1);
            await expect(vault.connect(stranger).release(stranger.address, T(1), dep(2)))
                .to.be.revertedWithCustomError(vault, "NotRelayer").withArgs(stranger.address);
            await expect(vault.connect(owner).release(owner.address, T(1), dep(3)))
                .to.be.revertedWithCustomError(vault, "NotRelayer").withArgs(owner.address);
        });

        it("refuses zero recipient, zero amount and empty deposit id", async function () {
            const { vault, relayer, alice } = await loadFixture(deployFixture);
            await fund(vault, alice, 1);
            await expect(vault.connect(relayer).release(ethers.ZeroAddress, T(1), dep(4)))
                .to.be.revertedWithCustomError(vault, "ZeroAddress");
            await expect(vault.connect(relayer).release(alice.address, 0, dep(5)))
                .to.be.revertedWithCustomError(vault, "ZeroAmount");
            await expect(vault.connect(relayer).release(alice.address, T(1), ethers.ZeroHash))
                .to.be.revertedWithCustomError(vault, "EmptyDepositId");
        });

        it("REPLAY: a repeated deposit id pays nothing and consumes no quota", async function () {
            const { vault, relayer, alice, bob } = await loadFixture(deployFixture);
            await fund(vault, alice, 1);
            const id = dep(42);

            await vault.connect(relayer).release(alice.address, T(100), id);
            const remainingBefore = await vault.remainingToday();
            const bobBefore = await ethers.provider.getBalance(bob.address);

            await expect(vault.connect(relayer).release(alice.address, T(100), id))
                .to.be.revertedWithCustomError(vault, "AlreadyProcessed").withArgs(id);
            await expect(vault.connect(relayer).release(bob.address, T(100), id))
                .to.be.revertedWithCustomError(vault, "AlreadyProcessed").withArgs(id);

            expect(await vault.remainingToday()).to.equal(remainingBefore);
            expect(await vault.totalReleased()).to.equal(T(100));
            expect(await ethers.provider.getBalance(bob.address)).to.equal(bobBefore);
        });

        it("enforces maxPerTx and the daily cap, resetting on the next UTC day", async function () {
            const { vault, relayer, alice, bob } = await loadFixture(deployFixture);
            await fund(vault, alice, 7);
            await startOfNextUtcDay();

            await expect(vault.connect(relayer).release(bob.address, MAX_PER_TX + 1n, dep(10)))
                .to.be.revertedWithCustomError(vault, "ExceedsMaxPerTx").withArgs(MAX_PER_TX + 1n, MAX_PER_TX);

            for (let i = 0; i < 5; i++) {
                await vault.connect(relayer).release(bob.address, MAX_PER_TX, dep(100 + i));
            }
            await expect(vault.connect(relayer).release(bob.address, T(1), dep(200)))
                .to.be.revertedWithCustomError(vault, "ExceedsDailyCap").withArgs(T(1), 0n);
            expect(await vault.processed(dep(200))).to.equal(false);

            await time.increase(86400);
            await expect(vault.connect(relayer).release(bob.address, T(1), dep(200))).to.not.be.reverted;
        });

        it("refuses to release more than the vault holds", async function () {
            const { vault, relayer, alice, bob } = await loadFixture(deployFixture);
            await vault.connect(alice).lock({ value: T(100) });
            await expect(vault.connect(relayer).release(bob.address, T(101), dep(20)))
                .to.be.revertedWithCustomError(vault, "InsufficientVaultBalance").withArgs(T(101), T(100));
        });

        it("a recipient that rejects TPIX reverts the whole release and leaves the id unused", async function () {
            const { vault, relayer, alice } = await loadFixture(deployFixture);
            await fund(vault, alice, 1);

            // สัญญาที่ไม่มี receive()/fallback รับเงินไม่ได้ — ใช้ตัว vault ตัวที่สองที่หยุดอยู่แทน
            const Vault = await ethers.getContractFactory("TPIXBridgeVault");
            const rejecting = await Vault.deploy(MIN_LOCK, MAX_LOCK, MAX_PER_TX, DAILY_CAP);
            await rejecting.pause();

            const id = dep(30);
            await expect(vault.connect(relayer).release(await rejecting.getAddress(), T(10), id))
                .to.be.revertedWithCustomError(vault, "TransferFailed");
            expect(await vault.processed(id)).to.equal(false);
            expect(await vault.totalReleased()).to.equal(0n);
        });

        it("guardian pause stops releases; only the owner can resume", async function () {
            const { vault, owner, relayer, guardian, alice } = await loadFixture(deployFixture);
            await fund(vault, alice, 1);
            await vault.connect(guardian).pause();
            await expect(vault.connect(relayer).release(alice.address, T(1), dep(40)))
                .to.be.revertedWithCustomError(vault, "EnforcedPause");
            await expect(vault.connect(guardian).unpause())
                .to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
            await vault.connect(owner).unpause();
            await expect(vault.connect(relayer).release(alice.address, T(1), dep(40))).to.not.be.reverted;
        });
    });

    describe("owner setters", function () {
        it("only the owner can change roles, limits and caps", async function () {
            const { vault, stranger } = await loadFixture(deployFixture);
            for (const call of [
                () => vault.connect(stranger).setRelayer(stranger.address, true),
                () => vault.connect(stranger).setGuardian(stranger.address, true),
                () => vault.connect(stranger).setLockLimits(T(1), T(2)),
                () => vault.connect(stranger).setMaxPerTx(T(1)),
                () => vault.connect(stranger).setDailyCap(T(1)),
            ]) {
                await expect(call()).to.be.revertedWithCustomError(vault, "OwnableUnauthorizedAccount");
            }
        });

        it("validates new limits and caps and emits events", async function () {
            const { vault, owner } = await loadFixture(deployFixture);
            await expect(vault.connect(owner).setLockLimits(T(5), T(50_000)))
                .to.emit(vault, "LockLimitsUpdated").withArgs(T(5), T(50_000));
            await expect(vault.connect(owner).setLockLimits(T(10), T(5)))
                .to.be.revertedWithCustomError(vault, "InvalidLockLimits");
            await expect(vault.connect(owner).setMaxPerTx(DAILY_CAP + 1n))
                .to.be.revertedWithCustomError(vault, "InvalidCaps");
            await expect(vault.connect(owner).setDailyCap(T(1_000_000)))
                .to.emit(vault, "DailyCapUpdated").withArgs(DAILY_CAP, T(1_000_000));
        });

        it("renounceOwnership is disabled", async function () {
            const { vault, owner } = await loadFixture(deployFixture);
            await expect(vault.connect(owner).renounceOwnership())
                .to.be.revertedWithCustomError(vault, "RenounceDisabled");
        });
    });

    describe("round trip with WTPIXBridgeMinter (both sides on one test chain)", function () {
        /** depositId จาก log จริงในใบเสร็จ — สูตรเดียวกับที่เซิร์ฟเวอร์ใช้ */
        function depositIdFromLog(chainId, receipt, contractAddress, eventName, iface) {
            const log = receipt.logs.find((l) =>
                l.address.toLowerCase() === contractAddress.toLowerCase()
                && iface.parseLog(l)?.name === eventName);
            return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
                ["uint256", "bytes32", "uint256"],
                [chainId, receipt.hash, log.index],
            ));
        }

        it("lock → mint wTPIX → burn → release, and every retry is a no-op", async function () {
            const { vault, relayer, alice } = await loadFixture(deployFixture);

            const WTPIX = await ethers.getContractFactory("src/bridge/WTPIX_BEP20.sol:WTPIX");
            const wtpix = await WTPIX.deploy();
            const Minter = await ethers.getContractFactory("WTPIXBridgeMinter");
            const minter = await Minter.deploy(await wtpix.getAddress(), MAX_PER_TX, DAILY_CAP);
            await wtpix.setInitialMinter(await minter.getAddress());
            await minter.setRelayer(relayer.address, true);

            // 1) ล็อก 1000 TPIX บน "TPIX Chain"
            const lockRc = await (await vault.connect(alice).lock({ value: T(1000) })).wait();
            const lockId = depositIdFromLog(4289, lockRc, await vault.getAddress(), "Locked", vault.interface);

            // 2) เซิร์ฟเวอร์ mint 999 wTPIX (หักค่าธรรมเนียม 1) — ลองซ้ำต้องไม่ได้เพิ่ม
            await minter.connect(relayer).mint(alice.address, T(999), lockId);
            await expect(minter.connect(relayer).mint(alice.address, T(999), lockId))
                .to.be.revertedWithCustomError(minter, "AlreadyProcessed");
            expect(await wtpix.balanceOf(alice.address)).to.equal(T(999));

            // 3) เผา 500 wTPIX บน "BSC"
            const burnRc = await (await wtpix.connect(alice).burn(T(500))).wait();
            const burnId = depositIdFromLog(56, burnRc, await wtpix.getAddress(), "Transfer", wtpix.interface);

            // 4) เซิร์ฟเวอร์ปล่อย 499 TPIX — ลองซ้ำต้องไม่ได้เพิ่ม
            const before = await ethers.provider.getBalance(alice.address);
            await vault.connect(relayer).release(alice.address, T(499), burnId);
            await expect(vault.connect(relayer).release(alice.address, T(499), burnId))
                .to.be.revertedWithCustomError(vault, "AlreadyProcessed");
            expect(await ethers.provider.getBalance(alice.address)).to.equal(before + T(499));

            // คลังต้องหนุน wTPIX ที่ยังหมุนอยู่ได้เต็มเสมอ (ส่วนเกิน = ค่าธรรมเนียม 2 TPIX)
            const vaultBalance = await ethers.provider.getBalance(await vault.getAddress());
            expect(vaultBalance).to.equal(T(501));
            expect(await wtpix.totalSupply()).to.equal(T(499));
            expect(vaultBalance - (await wtpix.totalSupply())).to.equal(T(2));
        });
    });
});
