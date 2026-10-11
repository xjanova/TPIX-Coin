const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * WTPIX_BEP20 — wTPIX บน BSC (ตัวแทน TPIX ก่อน bridge พร้อม)
 *
 * ไฟล์นี้เขียนขึ้น 2026-08-05 เพราะสัญญานี้เดิม **ไม่มีเทสต์เลยแม้แต่ข้อเดียว**
 * และมีช่องโหว่ W1: bridgeBurn() ไม่หัก allowance ทั้งที่คอมเมนต์บอกว่าต้อง approve
 *
 * ⚠️ ชื่อ contract ชนกับ src/sale/WTPIX_ERC20.sol (ชื่อ `WTPIX` ทั้งคู่)
 *    ต้องใช้ fully qualified name เสมอ
 */
describe("WTPIX_BEP20", function () {
    const FQN = "src/bridge/WTPIX_BEP20.sol:WTPIX";
    const TIMELOCK = 2 * 24 * 60 * 60; // 2 days

    async function deployFixture() {
        const [owner, bridge, minter, alice, bob] = await ethers.getSigners();

        const WTPIX = await ethers.getContractFactory(FQN);
        const wtpix = await WTPIX.deploy();
        await wtpix.waitForDeployment();

        await wtpix.connect(owner).setInitialMinter(minter.address);

        // ตั้ง bridgeContract ผ่าน timelock 2 วัน
        await wtpix.connect(owner).queueBridgeContract(bridge.address);
        await time.increase(TIMELOCK + 1);
        await wtpix.connect(owner).executeBridgeContract();

        const AMOUNT = ethers.parseEther("1000");
        await wtpix.connect(minter).mint(alice.address, AMOUNT);

        return { wtpix, owner, bridge, minter, alice, bob, AMOUNT };
    }

    describe("mint()", function () {
        it("minter ที่อยู่ใน whitelist mint ได้", async function () {
            const { wtpix, minter, bob } = await loadFixture(deployFixture);
            await wtpix.connect(minter).mint(bob.address, ethers.parseEther("5"));
            expect(await wtpix.balanceOf(bob.address)).to.equal(ethers.parseEther("5"));
        });

        it("คนที่ไม่ใช่ minter mint ไม่ได้", async function () {
            const { wtpix, alice, bob } = await loadFixture(deployFixture);
            await expect(wtpix.connect(alice).mint(bob.address, 1))
                .to.be.revertedWith("WTPIX: not a minter");
        });

        it("mint เกิน MAX_SUPPLY ไม่ได้", async function () {
            const { wtpix, minter, bob } = await loadFixture(deployFixture);
            const max = await wtpix.MAX_SUPPLY();
            await expect(wtpix.connect(minter).mint(bob.address, max))
                .to.be.revertedWith("WTPIX: exceeds max supply");
        });
    });

    describe("bridgeBurn() — ช่องโหว่ W1", function () {
        it("W1: bridge เผาเหรียญคนอื่นโดยไม่มี approve ไม่ได้", async function () {
            const { wtpix, bridge, alice, AMOUNT } = await loadFixture(deployFixture);
            expect(await wtpix.allowance(alice.address, bridge.address)).to.equal(0);

            // เดิมผ่านได้ทันที เพราะโค้ดเช็คแค่ msg.sender == bridgeContract
            await expect(wtpix.connect(bridge).bridgeBurn(alice.address, AMOUNT))
                .to.be.revertedWithCustomError(wtpix, "ERC20InsufficientAllowance");

            expect(await wtpix.balanceOf(alice.address)).to.equal(AMOUNT);
        });

        it("เผาได้เมื่อเจ้าของ approve แล้ว และ allowance ถูกหักจริง", async function () {
            const { wtpix, bridge, alice, AMOUNT } = await loadFixture(deployFixture);
            const half = AMOUNT / 2n;

            await wtpix.connect(alice).approve(bridge.address, AMOUNT);
            await wtpix.connect(bridge).bridgeBurn(alice.address, half);

            expect(await wtpix.balanceOf(alice.address)).to.equal(AMOUNT - half);
            expect(await wtpix.allowance(alice.address, bridge.address)).to.equal(AMOUNT - half);
        });

        it("เผาเกิน allowance ที่อนุมัติไว้ไม่ได้", async function () {
            const { wtpix, bridge, alice, AMOUNT } = await loadFixture(deployFixture);
            await wtpix.connect(alice).approve(bridge.address, AMOUNT / 2n);
            await expect(wtpix.connect(bridge).bridgeBurn(alice.address, AMOUNT))
                .to.be.revertedWithCustomError(wtpix, "ERC20InsufficientAllowance");
        });

        it("คนที่ไม่ใช่ bridge เรียก bridgeBurn ไม่ได้ แม้จะมี allowance", async function () {
            const { wtpix, alice, bob, AMOUNT } = await loadFixture(deployFixture);
            await wtpix.connect(alice).approve(bob.address, AMOUNT);
            await expect(wtpix.connect(bob).bridgeBurn(alice.address, AMOUNT))
                .to.be.revertedWith("WTPIX: only bridge");
        });
    });

    describe("bridge contract timelock", function () {
        it("execute ก่อนครบ 2 วันไม่ได้", async function () {
            const { wtpix, owner, bob } = await loadFixture(deployFixture);
            await wtpix.connect(owner).queueBridgeContract(bob.address);
            await expect(wtpix.connect(owner).executeBridgeContract())
                .to.be.revertedWith("WTPIX: timelock not expired");
        });

        it("cancel แล้ว execute ไม่ได้", async function () {
            const { wtpix, owner, bob } = await loadFixture(deployFixture);
            await wtpix.connect(owner).queueBridgeContract(bob.address);
            await wtpix.connect(owner).cancelBridgeContract();
            await time.increase(TIMELOCK + 1);
            await expect(wtpix.connect(owner).executeBridgeContract())
                .to.be.revertedWith("WTPIX: no pending");
        });

        it("คนที่ไม่ใช่ owner queue ไม่ได้", async function () {
            const { wtpix, alice, bob } = await loadFixture(deployFixture);
            await expect(wtpix.connect(alice).queueBridgeContract(bob.address))
                .to.be.revertedWithCustomError(wtpix, "OwnableUnauthorizedAccount");
        });
    });

    /**
     * 2026-10-11: เดิม setMinter() เพิ่ม minter ได้ทันที — คีย์เจ้าของหลุด = mint ถึง MAX_SUPPLY ข้ามเพดานของสะพาน
     * ตอนนี้ตัวแรกตั้งได้ครั้งเดียว ตัวต่อไปต้องรอ 2 วัน ส่วนการถอดทำได้ทันที
     */
    describe("minter timelock", function () {
        it("ไม่มีฟังก์ชันเพิ่ม minter ทันทีแบบเดิมแล้ว", async function () {
            const { wtpix } = await loadFixture(deployFixture);
            const names = wtpix.interface.fragments.filter((f) => f.type === "function").map((f) => f.name);
            expect(names).to.not.include("setMinter");
        });

        it("setInitialMinter ใช้ได้ครั้งเดียว", async function () {
            const { wtpix, owner, bob } = await loadFixture(deployFixture);
            expect(await wtpix.initialMinterSet()).to.equal(true);
            await expect(wtpix.connect(owner).setInitialMinter(bob.address))
                .to.be.revertedWith("WTPIX: initial minter already set");
        });

        it("คนที่ไม่ใช่ owner ตั้ง/เข้าคิว/ถอด minter ไม่ได้", async function () {
            const WTPIX = await ethers.getContractFactory(FQN);
            const fresh = await WTPIX.deploy();
            const [, , , alice, bob] = await ethers.getSigners();
            await expect(fresh.connect(alice).setInitialMinter(bob.address))
                .to.be.revertedWithCustomError(fresh, "OwnableUnauthorizedAccount");
            await expect(fresh.connect(alice).queueMinter(bob.address))
                .to.be.revertedWithCustomError(fresh, "OwnableUnauthorizedAccount");
            await expect(fresh.connect(alice).removeMinter(bob.address))
                .to.be.revertedWithCustomError(fresh, "OwnableUnauthorizedAccount");
        });

        it("เพิ่ม minter ตัวที่สองต้องรอครบ 2 วัน", async function () {
            const { wtpix, owner, bob } = await loadFixture(deployFixture);
            await expect(wtpix.connect(owner).queueMinter(bob.address))
                .to.emit(wtpix, "MinterQueued");
            await expect(wtpix.connect(owner).executeMinter(bob.address))
                .to.be.revertedWith("WTPIX: timelock not expired");
            await expect(wtpix.connect(bob).mint(bob.address, 1))
                .to.be.revertedWith("WTPIX: not a minter");

            await time.increase(TIMELOCK + 1);
            await expect(wtpix.connect(owner).executeMinter(bob.address))
                .to.emit(wtpix, "MinterSet").withArgs(bob.address, true);
            await wtpix.connect(bob).mint(bob.address, 1);
            expect(await wtpix.balanceOf(bob.address)).to.equal(1);
        });

        it("ยกเลิกคิวแล้ว execute ไม่ได้", async function () {
            const { wtpix, owner, bob } = await loadFixture(deployFixture);
            await wtpix.connect(owner).queueMinter(bob.address);
            await expect(wtpix.connect(owner).cancelMinter(bob.address))
                .to.emit(wtpix, "MinterCancelled").withArgs(bob.address);
            await time.increase(TIMELOCK + 1);
            await expect(wtpix.connect(owner).executeMinter(bob.address))
                .to.be.revertedWith("WTPIX: no pending minter");
        });

        it("ถอด minter มีผลทันที และล้างคิวของที่อยู่นั้นด้วย", async function () {
            const { wtpix, owner, minter, bob } = await loadFixture(deployFixture);
            await expect(wtpix.connect(owner).removeMinter(minter.address))
                .to.emit(wtpix, "MinterSet").withArgs(minter.address, false);
            await expect(wtpix.connect(minter).mint(bob.address, 1))
                .to.be.revertedWith("WTPIX: not a minter");

            await wtpix.connect(owner).queueMinter(bob.address);
            await wtpix.connect(owner).removeMinter(bob.address);
            await time.increase(TIMELOCK + 1);
            await expect(wtpix.connect(owner).executeMinter(bob.address))
                .to.be.revertedWith("WTPIX: no pending minter");
        });

        it("เข้าคิวที่อยู่ที่เป็น minter อยู่แล้ว หรือที่อยู่ศูนย์ไม่ได้", async function () {
            const { wtpix, owner, minter } = await loadFixture(deployFixture);
            await expect(wtpix.connect(owner).queueMinter(minter.address))
                .to.be.revertedWith("WTPIX: already a minter");
            await expect(wtpix.connect(owner).queueMinter(ethers.ZeroAddress))
                .to.be.revertedWith("WTPIX: zero minter");
        });
    });

    describe("pause", function () {
        it("pause บล็อกทั้ง transfer, mint และ bridgeBurn", async function () {
            const { wtpix, owner, minter, bridge, alice, bob, AMOUNT } =
                await loadFixture(deployFixture);
            await wtpix.connect(alice).approve(bridge.address, AMOUNT);
            await wtpix.connect(owner).pause();

            await expect(wtpix.connect(alice).transfer(bob.address, 1))
                .to.be.revertedWithCustomError(wtpix, "EnforcedPause");
            await expect(wtpix.connect(minter).mint(bob.address, 1))
                .to.be.revertedWithCustomError(wtpix, "EnforcedPause");
            await expect(wtpix.connect(bridge).bridgeBurn(alice.address, 1))
                .to.be.revertedWithCustomError(wtpix, "EnforcedPause");
        });

        it("unpause คืนการทำงาน", async function () {
            const { wtpix, owner, alice, bob } = await loadFixture(deployFixture);
            await wtpix.connect(owner).pause();
            await wtpix.connect(owner).unpause();
            await wtpix.connect(alice).transfer(bob.address, 1);
            expect(await wtpix.balanceOf(bob.address)).to.equal(1);
        });
    });
});
