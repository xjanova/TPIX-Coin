const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

/**
 * ทดสอบ TPIXBridgeMinter — ด่านจำกัดอัตราการ mint ของสะพาน USDT → TPIX Chain
 *
 * สิ่งที่ต้องจริงเสมอ:
 *   - relayer mint ได้ภายใต้ maxPerTx + dailyCap เท่านั้น (คีย์หลุด = เสียหายไม่เกินเพดาน/วัน)
 *   - guardian สั่ง pause ได้ แต่ปลด pause ไม่ได้ (ต้องเจ้าของเท่านั้น)
 *   - depositId ซ้ำ → ตัวเหรียญ revert และตัวนับเพดานต้องย้อนกลับ (ไม่กินโควตาฟรี)
 *   - setter ทุกตัวเป็นของเจ้าของ และยิง event ให้ตรวจย้อนหลังได้
 */
describe("TPIXBridgeMinter", function () {
    const U = (n) => ethers.parseUnits(String(n), 6);
    const MAX_PER_TX = U(1000);
    const DAILY_CAP = U(5000);
    const dep = (n) => ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "bytes32", "uint256"],
        [56, ethers.zeroPadValue(ethers.toBeHex(n), 32), 0],
    ));

    async function deployFixture() {
        const [owner, relayer, guardian, alice, bob, stranger] = await ethers.getSigners();

        const USDT = await ethers.getContractFactory("USDT_TPIX");
        const usdt = await USDT.deploy();
        await usdt.waitForDeployment();

        const Minter = await ethers.getContractFactory("TPIXBridgeMinter");
        const minter = await Minter.deploy(await usdt.getAddress(), MAX_PER_TX, DAILY_CAP);
        await minter.waitForDeployment();

        // ขั้นตอนเจ้าของหลัง deploy — minter เป็นที่อยู่เดียวที่ mint ได้
        await usdt.setBridge(await minter.getAddress(), true);
        await minter.setRelayer(relayer.address, true);
        await minter.setGuardian(guardian.address, true);

        return { usdt, minter, owner, relayer, guardian, alice, bob, stranger };
    }

    describe("deployment", function () {
        it("stores the token, caps and owner", async function () {
            const { usdt, minter, owner } = await loadFixture(deployFixture);
            expect(await minter.token()).to.equal(await usdt.getAddress());
            expect(await minter.maxPerTx()).to.equal(MAX_PER_TX);
            expect(await minter.dailyCap()).to.equal(DAILY_CAP);
            expect(await minter.owner()).to.equal(owner.address);
            expect(await minter.paused()).to.equal(false);
        });

        it("rejects a token address without code", async function () {
            const [, , , alice] = await ethers.getSigners();
            const Minter = await ethers.getContractFactory("TPIXBridgeMinter");
            await expect(Minter.deploy(alice.address, MAX_PER_TX, DAILY_CAP))
                .to.be.revertedWith("TPIXBridgeMinter: token has no code");
        });

        it("rejects the zero token address", async function () {
            const Minter = await ethers.getContractFactory("TPIXBridgeMinter");
            await expect(Minter.deploy(ethers.ZeroAddress, MAX_PER_TX, DAILY_CAP))
                .to.be.revertedWithCustomError(Minter, "ZeroAddress");
        });

        it("rejects caps where maxPerTx > dailyCap or either is zero", async function () {
            const { usdt } = await loadFixture(deployFixture);
            const Minter = await ethers.getContractFactory("TPIXBridgeMinter");
            const token = await usdt.getAddress();
            await expect(Minter.deploy(token, U(6000), U(5000))).to.be.revertedWithCustomError(Minter, "InvalidCaps");
            await expect(Minter.deploy(token, 0, U(5000))).to.be.revertedWithCustomError(Minter, "InvalidCaps");
            await expect(Minter.deploy(token, U(1), 0)).to.be.revertedWithCustomError(Minter, "InvalidCaps");
        });
    });

    describe("mint()", function () {
        it("mints through USDT_TPIX and emits BridgeMinted", async function () {
            const { usdt, minter, relayer, alice } = await loadFixture(deployFixture);
            const id = dep(1);

            await expect(minter.connect(relayer).mint(alice.address, U(250), id))
                .to.emit(minter, "BridgeMinted")
                .withArgs(relayer.address, alice.address, U(250), id, anyValue, U(250))
                .and.to.emit(usdt, "Minted")
                .withArgs(alice.address, U(250), id);

            const day = await minter.currentDay();
            expect(await usdt.balanceOf(alice.address)).to.equal(U(250));
            expect(await minter.totalMinted()).to.equal(U(250));
            expect(await minter.mintedPerDay(day)).to.equal(U(250));
            expect(await minter.isProcessed(id)).to.equal(true);
            expect(await minter.remainingToday()).to.equal(DAILY_CAP - U(250));
        });

        it("refuses anyone who is not a relayer — including the owner", async function () {
            const { minter, owner, stranger, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(stranger).mint(alice.address, U(1), dep(2)))
                .to.be.revertedWithCustomError(minter, "NotRelayer").withArgs(stranger.address);
            await expect(minter.connect(owner).mint(alice.address, U(1), dep(3)))
                .to.be.revertedWithCustomError(minter, "NotRelayer").withArgs(owner.address);
        });

        it("refuses zero recipient, zero amount and empty deposit id", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(relayer).mint(ethers.ZeroAddress, U(1), dep(4)))
                .to.be.revertedWithCustomError(minter, "ZeroAddress");
            await expect(minter.connect(relayer).mint(alice.address, 0, dep(5)))
                .to.be.revertedWithCustomError(minter, "ZeroAmount");
            await expect(minter.connect(relayer).mint(alice.address, U(1), ethers.ZeroHash))
                .to.be.revertedWithCustomError(minter, "EmptyDepositId");
        });

        it("enforces maxPerTx", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(relayer).mint(alice.address, MAX_PER_TX + 1n, dep(6)))
                .to.be.revertedWithCustomError(minter, "ExceedsMaxPerTx")
                .withArgs(MAX_PER_TX + 1n, MAX_PER_TX);
            await expect(minter.connect(relayer).mint(alice.address, MAX_PER_TX, dep(7))).to.not.be.reverted;
        });

        it("enforces the daily cap and resets on the next UTC day", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);

            // ขยับเวลาไปต้นวัน UTC ใหม่ กันเทสต์ข้ามเที่ยงคืนกลางคัน
            const now = await time.latest();
            await time.increaseTo((Math.floor(now / 86400) + 1) * 86400 + 60);

            for (let i = 0; i < 5; i++) {
                await minter.connect(relayer).mint(alice.address, MAX_PER_TX, dep(100 + i));
            }
            expect(await minter.remainingToday()).to.equal(0n);

            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(200)))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap")
                .withArgs(U(1), 0n);

            await time.increase(86400);
            expect(await minter.remainingToday()).to.equal(DAILY_CAP);
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(200))).to.not.be.reverted;
        });

        it("reports the exact remaining quota when a mint would cross the cap", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            const now = await time.latest();
            await time.increaseTo((Math.floor(now / 86400) + 1) * 86400 + 60);

            for (let i = 0; i < 4; i++) {
                await minter.connect(relayer).mint(alice.address, MAX_PER_TX, dep(300 + i));
            }
            await minter.connect(relayer).mint(alice.address, U(600), dep(310));

            await expect(minter.connect(relayer).mint(alice.address, U(500), dep(311)))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap")
                .withArgs(U(500), U(400));
        });

        it("REPLAY: a repeated deposit id reverts and does not consume quota", async function () {
            const { usdt, minter, relayer, alice, bob } = await loadFixture(deployFixture);
            const id = dep(42);

            await minter.connect(relayer).mint(alice.address, U(100), id);
            const usedBefore = await minter.remainingToday();
            const totalBefore = await minter.totalMinted();

            await expect(minter.connect(relayer).mint(bob.address, U(100), id))
                .to.be.revertedWith("USDT_TPIX: txhash replayed");

            expect(await minter.remainingToday()).to.equal(usedBefore);
            expect(await minter.totalMinted()).to.equal(totalBefore);
            expect(await usdt.balanceOf(bob.address)).to.equal(0n);
        });

        it("fails closed when the token no longer lists the minter as a bridge", async function () {
            const { usdt, minter, relayer, alice } = await loadFixture(deployFixture);
            await usdt.setBridge(await minter.getAddress(), false);
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(50)))
                .to.be.revertedWith("USDT_TPIX: not a bridge");
        });

        it("stops minting when the token itself is paused", async function () {
            const { usdt, minter, relayer, alice } = await loadFixture(deployFixture);
            await usdt.pause();
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(51)))
                .to.be.revertedWithCustomError(usdt, "EnforcedPause");
        });

        it("a removed relayer can no longer mint", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            await expect(minter.setRelayer(relayer.address, false))
                .to.emit(minter, "RelayerSet").withArgs(relayer.address, false);
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(52)))
                .to.be.revertedWithCustomError(minter, "NotRelayer");
        });
    });

    describe("pause / unpause", function () {
        it("guardian can pause; minting then reverts", async function () {
            const { minter, guardian, relayer, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(guardian).pause())
                .to.emit(minter, "Paused").withArgs(guardian.address);
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(60)))
                .to.be.revertedWithCustomError(minter, "EnforcedPause");
        });

        it("owner can pause too", async function () {
            const { minter, owner } = await loadFixture(deployFixture);
            await expect(minter.connect(owner).pause()).to.emit(minter, "Paused").withArgs(owner.address);
        });

        it("strangers and relayers cannot pause", async function () {
            const { minter, stranger, relayer } = await loadFixture(deployFixture);
            await expect(minter.connect(stranger).pause())
                .to.be.revertedWithCustomError(minter, "NotGuardian").withArgs(stranger.address);
            await expect(minter.connect(relayer).pause())
                .to.be.revertedWithCustomError(minter, "NotGuardian").withArgs(relayer.address);
        });

        it("guardian cannot unpause — only the owner can", async function () {
            const { minter, guardian, owner, relayer, alice } = await loadFixture(deployFixture);
            await minter.connect(guardian).pause();

            await expect(minter.connect(guardian).unpause())
                .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");

            await expect(minter.connect(owner).unpause()).to.emit(minter, "Unpaused").withArgs(owner.address);
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(61))).to.not.be.reverted;
        });

        it("pausing twice reverts (callers must read paused() first)", async function () {
            const { minter, guardian } = await loadFixture(deployFixture);
            await minter.connect(guardian).pause();
            await expect(minter.connect(guardian).pause()).to.be.revertedWithCustomError(minter, "EnforcedPause");
        });

        it("a removed guardian can no longer pause", async function () {
            const { minter, guardian } = await loadFixture(deployFixture);
            await expect(minter.setGuardian(guardian.address, false))
                .to.emit(minter, "GuardianSet").withArgs(guardian.address, false);
            await expect(minter.connect(guardian).pause()).to.be.revertedWithCustomError(minter, "NotGuardian");
        });
    });

    describe("owner setters", function () {
        it("only the owner can change roles and caps", async function () {
            const { minter, stranger, guardian, relayer } = await loadFixture(deployFixture);
            for (const signer of [stranger, guardian, relayer]) {
                await expect(minter.connect(signer).setRelayer(signer.address, true))
                    .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
                await expect(minter.connect(signer).setGuardian(signer.address, true))
                    .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
                await expect(minter.connect(signer).setMaxPerTx(U(1)))
                    .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
                await expect(minter.connect(signer).setDailyCap(U(10_000)))
                    .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
            }
        });

        it("updates caps with events and keeps maxPerTx <= dailyCap", async function () {
            const { minter } = await loadFixture(deployFixture);
            await expect(minter.setDailyCap(U(20_000)))
                .to.emit(minter, "DailyCapUpdated").withArgs(DAILY_CAP, U(20_000));
            await expect(minter.setMaxPerTx(U(2_000)))
                .to.emit(minter, "MaxPerTxUpdated").withArgs(MAX_PER_TX, U(2_000));

            await expect(minter.setMaxPerTx(U(20_001))).to.be.revertedWithCustomError(minter, "InvalidCaps");
            await expect(minter.setDailyCap(U(1_999))).to.be.revertedWithCustomError(minter, "InvalidCaps");
            await expect(minter.setMaxPerTx(0)).to.be.revertedWithCustomError(minter, "InvalidCaps");
        });

        it("lowering the daily cap below today's usage leaves zero quota, not an underflow", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            const now = await time.latest();
            await time.increaseTo((Math.floor(now / 86400) + 1) * 86400 + 60);

            await minter.connect(relayer).mint(alice.address, U(1000), dep(70));
            await minter.connect(relayer).mint(alice.address, U(1000), dep(71));
            await minter.setMaxPerTx(U(500));
            await minter.setDailyCap(U(1500));

            expect(await minter.remainingToday()).to.equal(0n);
            await expect(minter.connect(relayer).mint(alice.address, U(1), dep(72)))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap").withArgs(U(1), 0n);
        });

        it("rejects zero addresses for roles", async function () {
            const { minter } = await loadFixture(deployFixture);
            await expect(minter.setRelayer(ethers.ZeroAddress, true)).to.be.revertedWithCustomError(minter, "ZeroAddress");
            await expect(minter.setGuardian(ethers.ZeroAddress, true)).to.be.revertedWithCustomError(minter, "ZeroAddress");
        });
    });

    describe("ownership", function () {
        it("renounceOwnership is disabled so the bridge can never be stranded", async function () {
            const { minter, owner } = await loadFixture(deployFixture);
            await expect(minter.connect(owner).renounceOwnership())
                .to.be.revertedWithCustomError(minter, "RenounceDisabled");
            expect(await minter.owner()).to.equal(owner.address);
        });

        it("ownership moves only through the two-step handshake", async function () {
            const { minter, owner, alice, bob } = await loadFixture(deployFixture);
            await minter.connect(owner).transferOwnership(alice.address);
            expect(await minter.owner()).to.equal(owner.address);
            await expect(minter.connect(bob).acceptOwnership())
                .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
            await minter.connect(alice).acceptOwnership();
            expect(await minter.owner()).to.equal(alice.address);
        });
    });
});
