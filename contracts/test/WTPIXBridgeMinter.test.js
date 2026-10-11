const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

/**
 * ทดสอบ WTPIXBridgeMinter — ด่านจำกัดอัตราการ mint wTPIX บน BSC (สะพาน TPIX Chain → BSC)
 *
 * สิ่งที่ต้องจริงเสมอ:
 *   - relayer mint ได้ภายใต้ maxPerTx + dailyCap เท่านั้น (คีย์หลุด = เสียหายไม่เกินเพดาน/วัน)
 *   - depositId เดียว mint ได้ครั้งเดียว — เซิร์ฟเวอร์ลองซ้ำหลัง timeout ได้โดยไม่จ่ายซ้ำ
 *   - relayer mint ที่ตัวเหรียญตรง ๆ ไม่ได้ ต้องผ่านด่านนี้เท่านั้น
 *   - guardian สั่ง pause ได้ แต่ปลด pause ไม่ได้
 */
describe("WTPIXBridgeMinter", function () {
    const T = (n) => ethers.parseEther(String(n));
    const MAX_PER_TX = T(100_000);
    const DAILY_CAP = T(500_000);
    const WTPIX_FQN = "src/bridge/WTPIX_BEP20.sol:WTPIX";
    const dep = (n) => ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "bytes32", "uint256"],
        [4289, ethers.zeroPadValue(ethers.toBeHex(n), 32), 0],
    ));

    async function startOfNextUtcDay() {
        const now = await time.latest();
        await time.increaseTo((Math.floor(now / 86400) + 1) * 86400 + 60);
    }

    async function deployFixture() {
        const [owner, relayer, guardian, alice, bob, stranger] = await ethers.getSigners();

        const WTPIX = await ethers.getContractFactory(WTPIX_FQN);
        const wtpix = await WTPIX.deploy();
        await wtpix.waitForDeployment();

        const Minter = await ethers.getContractFactory("WTPIXBridgeMinter");
        const minter = await Minter.deploy(await wtpix.getAddress(), MAX_PER_TX, DAILY_CAP);
        await minter.waitForDeployment();

        // ขั้นตอนเจ้าของหลัง deploy — minter เป็นที่อยู่เดียวที่ mint wTPIX ได้
        await wtpix.setInitialMinter(await minter.getAddress());
        await minter.setRelayer(relayer.address, true);
        await minter.setGuardian(guardian.address, true);

        return { wtpix, minter, owner, relayer, guardian, alice, bob, stranger };
    }

    describe("deployment", function () {
        it("stores the token, caps and owner", async function () {
            const { wtpix, minter, owner } = await loadFixture(deployFixture);
            expect(await minter.token()).to.equal(await wtpix.getAddress());
            expect(await minter.maxPerTx()).to.equal(MAX_PER_TX);
            expect(await minter.dailyCap()).to.equal(DAILY_CAP);
            expect(await minter.owner()).to.equal(owner.address);
            expect(await minter.paused()).to.equal(false);
        });

        it("rejects a token address without code and the zero address", async function () {
            const [, , , alice] = await ethers.getSigners();
            const Minter = await ethers.getContractFactory("WTPIXBridgeMinter");
            await expect(Minter.deploy(alice.address, MAX_PER_TX, DAILY_CAP))
                .to.be.revertedWith("WTPIXBridgeMinter: token has no code");
            await expect(Minter.deploy(ethers.ZeroAddress, MAX_PER_TX, DAILY_CAP))
                .to.be.revertedWithCustomError(Minter, "ZeroAddress");
        });

        it("rejects caps where maxPerTx > dailyCap or either is zero", async function () {
            const { wtpix } = await loadFixture(deployFixture);
            const Minter = await ethers.getContractFactory("WTPIXBridgeMinter");
            const token = await wtpix.getAddress();
            await expect(Minter.deploy(token, T(600_000), T(500_000))).to.be.revertedWithCustomError(Minter, "InvalidCaps");
            await expect(Minter.deploy(token, 0, T(500_000))).to.be.revertedWithCustomError(Minter, "InvalidCaps");
            await expect(Minter.deploy(token, T(1), 0)).to.be.revertedWithCustomError(Minter, "InvalidCaps");
        });
    });

    describe("mint()", function () {
        it("mints wTPIX and emits BridgeMinted", async function () {
            const { wtpix, minter, relayer, alice } = await loadFixture(deployFixture);
            const id = dep(1);

            await expect(minter.connect(relayer).mint(alice.address, T(250), id))
                .to.emit(minter, "BridgeMinted")
                .withArgs(relayer.address, alice.address, T(250), id, anyValue, T(250));

            const day = await minter.currentDay();
            expect(await wtpix.balanceOf(alice.address)).to.equal(T(250));
            expect(await minter.totalMinted()).to.equal(T(250));
            expect(await minter.mintedPerDay(day)).to.equal(T(250));
            expect(await minter.processed(id)).to.equal(true);
            expect(await minter.remainingToday()).to.equal(DAILY_CAP - T(250));
        });

        it("refuses anyone who is not a relayer — including the owner", async function () {
            const { minter, owner, stranger, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(stranger).mint(alice.address, T(1), dep(2)))
                .to.be.revertedWithCustomError(minter, "NotRelayer").withArgs(stranger.address);
            await expect(minter.connect(owner).mint(alice.address, T(1), dep(3)))
                .to.be.revertedWithCustomError(minter, "NotRelayer").withArgs(owner.address);
        });

        it("the relayer cannot bypass the gate by minting on the token directly", async function () {
            const { wtpix, relayer, alice } = await loadFixture(deployFixture);
            await expect(wtpix.connect(relayer).mint(alice.address, T(1)))
                .to.be.revertedWith("WTPIX: not a minter");
        });

        it("refuses zero recipient, zero amount and empty deposit id", async function () {
            const { minter, relayer, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(relayer).mint(ethers.ZeroAddress, T(1), dep(4)))
                .to.be.revertedWithCustomError(minter, "ZeroAddress");
            await expect(minter.connect(relayer).mint(alice.address, 0, dep(5)))
                .to.be.revertedWithCustomError(minter, "ZeroAmount");
            await expect(minter.connect(relayer).mint(alice.address, T(1), ethers.ZeroHash))
                .to.be.revertedWithCustomError(minter, "EmptyDepositId");
        });

        it("REPLAY: a repeated deposit id reverts without minting or consuming quota", async function () {
            const { wtpix, minter, relayer, alice, bob } = await loadFixture(deployFixture);
            const id = dep(42);

            await minter.connect(relayer).mint(alice.address, T(100), id);
            const remainingBefore = await minter.remainingToday();
            const totalBefore = await minter.totalMinted();
            const supplyBefore = await wtpix.totalSupply();

            // ลองซ้ำทั้งผู้รับเดิมและผู้รับใหม่ — ต้องไม่ได้สักบาท
            await expect(minter.connect(relayer).mint(alice.address, T(100), id))
                .to.be.revertedWithCustomError(minter, "AlreadyProcessed").withArgs(id);
            await expect(minter.connect(relayer).mint(bob.address, T(100), id))
                .to.be.revertedWithCustomError(minter, "AlreadyProcessed").withArgs(id);

            expect(await minter.remainingToday()).to.equal(remainingBefore);
            expect(await minter.totalMinted()).to.equal(totalBefore);
            expect(await wtpix.totalSupply()).to.equal(supplyBefore);
            expect(await wtpix.balanceOf(bob.address)).to.equal(0n);
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
            await startOfNextUtcDay();

            for (let i = 0; i < 5; i++) {
                await minter.connect(relayer).mint(alice.address, MAX_PER_TX, dep(100 + i));
            }
            expect(await minter.remainingToday()).to.equal(0n);

            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(200)))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap")
                .withArgs(T(1), 0n);

            await time.increase(86400);
            expect(await minter.remainingToday()).to.equal(DAILY_CAP);
            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(200))).to.not.be.reverted;
        });

        it("a deposit refused for the daily cap can still be minted later (id not burned)", async function () {
            const { wtpix, minter, relayer, alice } = await loadFixture(deployFixture);
            await startOfNextUtcDay();
            for (let i = 0; i < 5; i++) {
                await minter.connect(relayer).mint(alice.address, MAX_PER_TX, dep(400 + i));
            }

            const queued = dep(499);
            await expect(minter.connect(relayer).mint(alice.address, T(10), queued))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap");
            expect(await minter.processed(queued)).to.equal(false);

            await time.increase(86400);
            await minter.connect(relayer).mint(alice.address, T(10), queued);
            expect(await minter.processed(queued)).to.equal(true);
            expect(await wtpix.balanceOf(alice.address)).to.equal(MAX_PER_TX * 5n + T(10));
        });

        it("fails closed when wTPIX revokes the minter or is paused", async function () {
            const { wtpix, minter, relayer, alice } = await loadFixture(deployFixture);

            await wtpix.pause();
            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(50)))
                .to.be.revertedWithCustomError(wtpix, "EnforcedPause");
            await wtpix.unpause();

            await wtpix.removeMinter(await minter.getAddress());
            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(51)))
                .to.be.revertedWith("WTPIX: not a minter");

            // ล้มทั้งธุรกรรม = depositId ยังไม่ถูกใช้ เปิดสิทธิ์คืนแล้ว mint ได้
            expect(await minter.processed(dep(51))).to.equal(false);
        });

        it("still respects wTPIX MAX_SUPPLY even with generous caps", async function () {
            const { wtpix, relayer, alice } = await loadFixture(deployFixture);
            const Minter = await ethers.getContractFactory("WTPIXBridgeMinter");
            const big = T(800_000_000);
            const wide = await Minter.deploy(await wtpix.getAddress(), big, big);
            await wtpix.queueMinter(await wide.getAddress());
            await time.increase(2 * 86400 + 1);
            await wtpix.executeMinter(await wide.getAddress());
            await wide.setRelayer(relayer.address, true);

            await wide.connect(relayer).mint(alice.address, T(700_000_000), dep(60));
            await expect(wide.connect(relayer).mint(alice.address, 1n, dep(61)))
                .to.be.revertedWith("WTPIX: exceeds max supply");
        });

        it("a removed relayer can no longer mint", async function () {
            const { minter, owner, relayer, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(owner).setRelayer(relayer.address, false))
                .to.emit(minter, "RelayerSet").withArgs(relayer.address, false);
            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(70)))
                .to.be.revertedWithCustomError(minter, "NotRelayer");
        });
    });

    describe("pause / unpause", function () {
        it("guardian can pause; minting then reverts", async function () {
            const { minter, relayer, guardian, alice } = await loadFixture(deployFixture);
            await expect(minter.connect(guardian).pause())
                .to.emit(minter, "Paused").withArgs(guardian.address);
            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(80)))
                .to.be.revertedWithCustomError(minter, "EnforcedPause");
        });

        it("strangers and relayers cannot pause", async function () {
            const { minter, relayer, stranger } = await loadFixture(deployFixture);
            await expect(minter.connect(stranger).pause())
                .to.be.revertedWithCustomError(minter, "NotGuardian").withArgs(stranger.address);
            await expect(minter.connect(relayer).pause())
                .to.be.revertedWithCustomError(minter, "NotGuardian").withArgs(relayer.address);
        });

        it("guardian cannot unpause — only the owner can", async function () {
            const { minter, owner, guardian } = await loadFixture(deployFixture);
            await minter.connect(guardian).pause();
            await expect(minter.connect(guardian).unpause())
                .to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
            await expect(minter.connect(owner).unpause())
                .to.emit(minter, "Unpaused").withArgs(owner.address);
        });
    });

    describe("owner setters", function () {
        it("only the owner can change roles and caps", async function () {
            const { minter, stranger } = await loadFixture(deployFixture);
            for (const call of [
                () => minter.connect(stranger).setRelayer(stranger.address, true),
                () => minter.connect(stranger).setGuardian(stranger.address, true),
                () => minter.connect(stranger).setMaxPerTx(T(1)),
                () => minter.connect(stranger).setDailyCap(T(1)),
            ]) {
                await expect(call()).to.be.revertedWithCustomError(minter, "OwnableUnauthorizedAccount");
            }
        });

        it("keeps maxPerTx <= dailyCap and rejects zero-address roles", async function () {
            const { minter, owner } = await loadFixture(deployFixture);
            await expect(minter.connect(owner).setMaxPerTx(DAILY_CAP + 1n))
                .to.be.revertedWithCustomError(minter, "InvalidCaps");
            await expect(minter.connect(owner).setDailyCap(MAX_PER_TX - 1n))
                .to.be.revertedWithCustomError(minter, "InvalidCaps");
            await expect(minter.connect(owner).setRelayer(ethers.ZeroAddress, true))
                .to.be.revertedWithCustomError(minter, "ZeroAddress");
            await expect(minter.connect(owner).setGuardian(ethers.ZeroAddress, true))
                .to.be.revertedWithCustomError(minter, "ZeroAddress");
        });

        it("lowering the daily cap below today's usage leaves zero quota, not an underflow", async function () {
            const { minter, owner, relayer, alice } = await loadFixture(deployFixture);
            await startOfNextUtcDay();
            await minter.connect(relayer).mint(alice.address, T(100_000), dep(90));
            await minter.connect(relayer).mint(alice.address, T(100_000), dep(91));

            await minter.connect(owner).setDailyCap(T(150_000));
            expect(await minter.remainingToday()).to.equal(0n);
            await expect(minter.connect(relayer).mint(alice.address, T(1), dep(92)))
                .to.be.revertedWithCustomError(minter, "ExceedsDailyCap").withArgs(T(1), 0n);
        });
    });

    describe("ownership", function () {
        it("renounceOwnership is disabled", async function () {
            const { minter, owner } = await loadFixture(deployFixture);
            await expect(minter.connect(owner).renounceOwnership())
                .to.be.revertedWithCustomError(minter, "RenounceDisabled");
        });

        it("ownership moves only through the two-step handshake", async function () {
            const { minter, owner, bob } = await loadFixture(deployFixture);
            await minter.connect(owner).transferOwnership(bob.address);
            expect(await minter.owner()).to.equal(owner.address);
            await minter.connect(bob).acceptOwnership();
            expect(await minter.owner()).to.equal(bob.address);
        });
    });
});
