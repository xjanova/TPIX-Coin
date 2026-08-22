const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time, setBalance, takeSnapshot } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * ทดสอบ NodeRegistryV2 — เน้นเรื่องที่ทำให้เงินหายจริง
 *
 * ที่ต้องพิสูจน์ให้ได้ก่อน deploy:
 *   1. รางวัลห้ามจ่ายออกจากเงินต้นของคนอื่น (บั๊กเดิม: จ่ายได้ทันทีทั้งที่ pool ว่าง)
 *   2. คนที่มาทีหลังห้ามเจือจางรางวัลที่คนก่อนหน้าหาไว้แล้วย้อนหลัง
 *   3. ลงทะเบียนซ้ำหลังถอน ห้ามทำให้ operators ซ้ำ
 *   4. uptime ที่เปลี่ยนทีหลัง ห้ามย้อนไปตัดรางวัลที่หาไว้แล้ว
 *   5. ถอนเงินต้นได้เต็มจำนวนเสมอ
 */
describe("NodeRegistryV2", function () {
    // ไฟล์นี้เดินนาฬิกา EVM ไปข้างหน้าหลายปีเพื่อทดสอบ emission ต่อปี
    // ถ้าปล่อยค้างไว้ ไฟล์เทสต์อื่นที่คำนวณ deadline จากนาฬิกาเครื่อง (Date.now)
    // จะเจอ EXPIRED ทันที — จึงถ่ายภาพไว้ก่อนแล้วคืนสภาพเมื่อจบไฟล์
    let __snapshot;
    before(async function () { __snapshot = await takeSnapshot(); });
    after(async function () { await __snapshot.restore(); });

    const TIER = { GUARDIAN: 0, SENTINEL: 1, LIGHT: 2, VALIDATOR: 3 };
    const LIGHT_STAKE = ethers.parseEther("10000");
    const SENTINEL_STAKE = ethers.parseEther("100000");
    const ENDPOINT = "203.0.113.10:8545";

    async function deployFixture() {
        const [owner, alice, bob, carol, funder] = await ethers.getSigners();
        // TPIX มี supply 7 พันล้าน — ให้ signer มีเงินพอสำหรับ tier ใหญ่
        for (const s of [owner, alice, bob, carol, funder]) {
            await setBalance(s.address, ethers.parseEther("50000000"));
        }
        const Registry = await ethers.getContractFactory("NodeRegistryV2");
        const registry = await Registry.deploy();
        await registry.waitForDeployment();
        return { registry, owner, alice, bob, carol, funder };
    }

    async function fundedFixture() {
        const f = await deployFixture();
        await f.funder.sendTransaction({
            to: await f.registry.getAddress(),
            value: ethers.parseEther("5000000"),
        });
        return f;
    }

    // ────────────────────────────────────────────────────────────
    //  1. ความมั่นคงของเงินต้น — บั๊กเดิมที่ร้ายแรงที่สุด
    // ────────────────────────────────────────────────────────────
    describe("solvency — รางวัลห้ามกินเงินต้น", function () {
        it("pool ว่าง: claim ไม่ได้เงิน และเงินต้นยังอยู่ครบ", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            // ปล่อยเวลาผ่านไป 1 วัน — สูตรเดิมจะคำนวณรางวัลได้มหาศาล
            await time.increase(24 * 60 * 60);

            // หาได้ (accrual) แต่จ่ายไม่ได้ เพราะไม่มีเงินนอกเหนือเงินต้น
            expect(await registry.pendingReward(alice.address)).to.be.gt(0);
            expect(await registry.availableRewardFunds()).to.equal(0);
            expect(await registry.claimableNow(alice.address)).to.equal(0);

            await registry.connect(alice).claimRewards();

            // สัญญาต้องยังถือเงินต้นไว้ครบ
            expect(await ethers.provider.getBalance(await registry.getAddress()))
                .to.equal(LIGHT_STAKE);
            expect(await registry.totalRewardsDistributed()).to.equal(0);
        });

        it("pool ว่าง: ถอนคืนได้เต็มจำนวน", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(8 * 24 * 60 * 60); // ผ่าน lock 7 วัน

            await registry.connect(alice).claimRewards();
            const before = await ethers.provider.getBalance(alice.address);
            const tx = await registry.connect(alice).deregisterNode();
            const rc = await tx.wait();
            const gas = rc.gasUsed * rc.gasPrice;
            const after = await ethers.provider.getBalance(alice.address);

            expect(after + gas - before).to.equal(LIGHT_STAKE);
            expect(await ethers.provider.getBalance(await registry.getAddress())).to.equal(0);
        });

        it("เงินต้นของคนอื่นห้ามถูกจ่ายเป็นรางวัล", async function () {
            const { registry, alice, bob } = await loadFixture(deployFixture);
            // bob วางเงินต้นก้อนใหญ่ไว้ — เป็นเหยื่อของบั๊กเดิม
            await registry.connect(bob).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            await time.increase(30 * 24 * 60 * 60);
            await registry.connect(alice).claimRewards();

            // ยอดในสัญญาต้องไม่ต่ำกว่าเงินต้นรวม
            const bal = await ethers.provider.getBalance(await registry.getAddress());
            expect(bal).to.be.gte(await registry.totalStaked());
            expect(bal).to.equal(SENTINEL_STAKE + LIGHT_STAKE);
        });

        it("เมื่อเติม pool แล้วค่อยจ่ายได้ และเงินต้นยังปลอดภัย", async function () {
            const { registry, alice, funder } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(60 * 60);
            await registry.connect(alice).claimRewards();   // ยังไม่ได้เงิน
            expect(await registry.totalRewardsDistributed()).to.equal(0);

            const topUp = ethers.parseEther("1000");
            await registry.connect(funder).fundRewardPool({ value: topUp });
            expect(await registry.availableRewardFunds()).to.equal(topUp);

            await registry.connect(alice).claimRewards();
            expect(await registry.totalRewardsDistributed()).to.be.gt(0);

            const bal = await ethers.provider.getBalance(await registry.getAddress());
            expect(bal).to.be.gte(await registry.totalStaked());
        });

        it("จ่ายไม่ครบ ส่วนที่เหลือไม่หาย — ทบไว้เคลมทีหลังได้", async function () {
            const { registry, alice, funder } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(24 * 60 * 60);

            const small = ethers.parseEther("10");
            await registry.connect(funder).fundRewardPool({ value: small });

            const owedBefore = await registry.pendingReward(alice.address);
            expect(owedBefore).to.be.gt(small);

            await registry.connect(alice).claimRewards();
            expect(await registry.totalRewardsDistributed()).to.equal(small);

            // ที่เหลือยังค้างอยู่ ไม่ถูกล้างทิ้ง
            const owedAfter = await registry.pendingReward(alice.address);
            expect(owedAfter).to.be.gte(owedBefore - small);
        });
    });

    // ────────────────────────────────────────────────────────────
    //  2. ห้ามเจือจางย้อนหลัง
    // ────────────────────────────────────────────────────────────
    describe("accumulator — คนมาทีหลังห้ามลดรางวัลย้อนหลัง", function () {
        it("รางวัลช่วงที่อยู่คนเดียว ต้องไม่ถูกหารด้วยจำนวนโหนดใหม่", async function () {
            const { registry, alice, bob } = await loadFixture(fundedFixture);

            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(10 * 24 * 60 * 60);

            const soloEarned = await registry.pendingReward(alice.address);
            expect(soloEarned).to.be.gt(0);

            // bob เข้ามาอีก 9 ตัว (จำลองด้วยการเข้าทีละ signer ไม่ได้ จึงใช้ bob 1 ตัวก็พอ)
            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            // ทันทีที่ bob เข้า ยอดของ alice ต้องไม่ลดลง
            const afterJoin = await registry.pendingReward(alice.address);
            expect(afterJoin).to.be.gte(soloEarned);
        });

        it("โหนดใหม่เริ่มนับจากศูนย์ ไม่ได้รางวัลย้อนหลัง", async function () {
            const { registry, alice, bob } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(10 * 24 * 60 * 60);

            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            // bob เพิ่งเข้า ยอดต้องเกือบศูนย์ (ยอมให้มีเศษจากบล็อกที่เพิ่งผ่าน)
            const bobPending = await registry.pendingReward(bob.address);
            const alicePending = await registry.pendingReward(alice.address);
            expect(bobPending).to.be.lt(alicePending / 100n);
        });

        it("สองโหนดที่อยู่ช่วงเวลาเท่ากัน ได้รางวัลเท่ากัน", async function () {
            const { registry, alice, bob } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(10 * 24 * 60 * 60);

            const a = await registry.pendingReward(alice.address);
            const b = await registry.pendingReward(bob.address);
            const diff = a > b ? a - b : b - a;
            expect(diff).to.be.lt(a / 1000n);   // ต่างกันได้ไม่เกิน 0.1%
        });
    });

    // ────────────────────────────────────────────────────────────
    //  3. operators ห้ามซ้ำ
    // ────────────────────────────────────────────────────────────
    describe("operators list", function () {
        it("ลงทะเบียน → ถอน → ลงทะเบียนใหม่ ต้องนับเป็น 1 คน", async function () {
            const { registry, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(8 * 24 * 60 * 60);
            await registry.connect(alice).deregisterNode();
            await registry.connect(alice).claimRewards();
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            expect(await registry.getOperatorCount()).to.equal(1);
            const active = await registry.getActiveNodes(0, 10);
            expect(active.length).to.equal(1);
        });
    });

    // ────────────────────────────────────────────────────────────
    //  4. uptime มีผลไปข้างหน้าเท่านั้น
    // ────────────────────────────────────────────────────────────
    describe("uptime", function () {
        it("ลด uptime ทีหลัง ห้ามตัดรางวัลที่หาไว้แล้ว", async function () {
            const { registry, owner, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(10 * 24 * 60 * 60);

            const before = await registry.pendingReward(alice.address);
            await registry.connect(owner).updateUptime(alice.address, 5000); // เหลือ 50%
            const after = await registry.pendingReward(alice.address);

            // ที่หาไว้แล้วต้องอยู่ครบ (อนุโลมเศษเวลาจากบล็อกที่เพิ่มมา)
            expect(after).to.be.gte(before);
        });

        it("uptime > 10000 ไม่ได้", async function () {
            const { registry, owner, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await expect(registry.connect(owner).updateUptime(alice.address, 10001))
                .to.be.revertedWith("Max 10000");
        });

        it("คนอื่นเรียก updateUptime ไม่ได้", async function () {
            const { registry, alice, bob } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await expect(registry.connect(bob).updateUptime(alice.address, 5000))
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
        });
    });

    // ────────────────────────────────────────────────────────────
    //  5. กติกาการลงทะเบียน
    // ────────────────────────────────────────────────────────────
    describe("registration rules", function () {
        it("stake ต่ำกว่าขั้นต่ำไม่ได้", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(
                registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: ethers.parseEther("9999") })
            ).to.be.revertedWith("Insufficient stake");
        });

        it("endpoint ว่างหรือยาวเกินไม่ได้", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(
                registry.connect(alice).registerNode(TIER.LIGHT, "", { value: LIGHT_STAKE })
            ).to.be.revertedWith("Endpoint required");
            await expect(
                registry.connect(alice).registerNode(TIER.LIGHT, "x".repeat(101), { value: LIGHT_STAKE })
            ).to.be.revertedWith("Endpoint too long");
        });

        it("ลงทะเบียนซ้อนไม่ได้", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await expect(
                registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE })
            ).to.be.revertedWith("Already registered");
        });

        it("ถอนก่อนครบ lock ไม่ได้", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await expect(registry.connect(alice).deregisterNode()).to.be.revertedWith("Still locked");
        });

        it("tier Validator ต้องมี KYC ก่อน", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(
                registry.connect(alice).registerNode(TIER.VALIDATOR, ENDPOINT, {
                    value: ethers.parseEther("10000000"),
                })
            ).to.be.revertedWith("KYC contract not configured");
        });
    });

    // ────────────────────────────────────────────────────────────
    //  6. slashing
    // ────────────────────────────────────────────────────────────
    describe("slashing", function () {
        it("โดน slash แล้วถอนส่วนที่เหลือได้ และรางวัลที่หาไว้ไม่หาย", async function () {
            const { registry, owner, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await time.increase(10 * 24 * 60 * 60);

            const earnedBefore = await registry.pendingReward(alice.address);
            await registry.connect(owner).slashNode(alice.address, "double sign");

            const node = await registry.getNodeInfo(alice.address);
            expect(node.status).to.equal(2); // Slashed
            expect(node.stakedAmount).to.equal(SENTINEL_STAKE - SENTINEL_STAKE * 500n / 10000n);
            expect(await registry.pendingReward(alice.address)).to.be.gte(earnedBefore * 99n / 100n);

            await registry.connect(alice).withdrawSlashedStake();
            expect((await registry.getNodeInfo(alice.address)).stakedAmount).to.equal(0);
        });

        it("คนอื่น slash ไม่ได้", async function () {
            const { registry, alice, bob } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await expect(registry.connect(bob).slashNode(alice.address, "x"))
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
        });
    });

    // ────────────────────────────────────────────────────────────
    //  7. ปีของ emission
    // ────────────────────────────────────────────────────────────
    describe("reward year", function () {
        it("ข้ามปีก่อนครบ 365 วันไม่ได้", async function () {
            const { registry } = await loadFixture(deployFixture);
            await expect(registry.advanceRewardYear()).to.be.revertedWith("Year not ended");
        });

        it("ครบ 3 ปีแล้ว emission ต้องเป็นศูนย์", async function () {
            const { registry } = await loadFixture(deployFixture);
            const YEAR = 365 * 24 * 60 * 60;
            for (let i = 0; i < 3; i++) {
                await time.increase(YEAR);
                await registry.advanceRewardYear();
            }
            expect(await registry.currentYear()).to.equal(3);
            expect(await registry.currentRewardPerSecond()).to.equal(0);
            await expect(registry.advanceRewardYear()).to.be.revertedWith("All years completed");
        });
    });
});
