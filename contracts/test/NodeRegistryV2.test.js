const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time, setBalance, setCode, takeSnapshot } = require("@nomicfoundation/hardhat-network-helpers");

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
            // Light มีเพดาน APR 6% → 10,000 TPIX ได้ ~1.64 TPIX/วัน ปล่อย 30 วันให้ได้ ~49 TPIX
            await time.increase(30 * 24 * 60 * 60);

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
            const active = await registry.getActiveOperators(0, 10);
            expect(active).to.deep.equal([alice.address]);
        });

        it("getActiveOperators แบ่งหน้าได้ และข้ามคนที่ถอนไปแล้ว", async function () {
            const { registry, alice, bob, carol } = await loadFixture(fundedFixture);
            for (const s of [alice, bob, carol]) {
                await registry.connect(s).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            }
            await time.increase(8 * 24 * 60 * 60);
            await registry.connect(bob).deregisterNode();

            expect(await registry.getActiveOperators(0, 10)).to.deep.equal([alice.address, carol.address]);
            expect(await registry.getActiveOperators(1, 1)).to.deep.equal([carol.address]);
            expect(await registry.getActiveOperators(5, 10)).to.deep.equal([]);
        });
    });

    // ────────────────────────────────────────────────────────────
    //  ขนาด bytecode — tx deploy ต้องลอดลิมิต body ของ RPC proxy (rpc1 ขยายเป็น 128k เมื่อ 2026-10-22)
    // ────────────────────────────────────────────────────────────
    describe("deploy size", function () {
        it("initcode ของ NodeRegistryV2 ต้องเล็กพอให้ eth_sendRawTransaction ผ่าน rpc1 (nginx 128k)", async function () {
            const artifact = await artifacts.readArtifact("NodeRegistryV2");
            const initBytes = (artifact.bytecode.length - 2) / 2;
            // raw tx ≈ initcode + ~120 ไบต์ (nonce/gas/v/r/s) → hex ×2 + JSON ~100 ไบต์ ต้อง < 131,072
            const jsonBodyBytes = (initBytes + 120) * 2 + 2 + 100;
            expect(jsonBodyBytes, `initcode ${initBytes} ไบต์`).to.be.lt(131072 - 512);
            // runtime ต้องไม่ชนเพดาน EIP-170 (24,576 ไบต์) — เชนปฏิเสธ deploy ทั้งที่ RPC รับ
            const runtimeBytes = (artifact.deployedBytecode.length - 2) / 2;
            expect(runtimeBytes, `runtime ${runtimeBytes} ไบต์`).to.be.lt(24576);
        });

        it("hash ของ runtime ที่ compile ได้ ต้องอยู่ในรายการที่ TPIX Wallet ตรึงไว้", async function () {
            // แอปยอมเขียนธุรกรรมเข้าเฉพาะสัญญาที่ keccak256(eth_getCode) อยู่ในรายการ
            // (ไม่มี immutable → ค่านี้เท่ากับ eth_getCode ทุกที่อยู่) — แก้สัญญาแม้แต่คอมเมนต์
            // hash เปลี่ยน (metadata ของ solc ฝัง hash ของไฟล์ต้นฉบับ) ต้อง pin ใหม่ทั้ง Wallet
            // และแอป PC (TPIX-Masternode/electron/node-registry.js) แล้วปล่อยแอปก่อนชี้เว็บ
            const fs = require("fs");
            const path = require("path");
            const artifact = await artifacts.readArtifact("NodeRegistryV2");
            const hash = ethers.keccak256(artifact.deployedBytecode).toLowerCase();
            const walletPins = fs.readFileSync(
                path.join(__dirname, "..", "..", "wallet", "lib", "services", "masternode_service.dart"), "utf8");
            expect(walletPins, `runtime hash ${hash} ยังไม่ได้ pin ใน wallet`).to.include(`'${hash}'`);
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
                .to.be.revertedWith("Not owner or uptime oracle");
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
    //  6b. ผลตรวจ 2026-10 — เพดาน APR / stake พอดี / หยุดรับสมัคร / slash ย้อนหลัง / reentrancy
    // ────────────────────────────────────────────────────────────
    describe("audit 2026-10: APR cap — โหนดแรกห้ามกิน emission ทั้งชั้น", function () {
        const YEAR = 365 * 24 * 60 * 60;

        it("Light ตัวเดียว 1 ปี ได้ ~6% ของเงินต้น (600 TPIX) ไม่ใช่ 90 ล้าน", async function () {
            const { registry, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(YEAR);

            const earned = await registry.pendingReward(alice.address);
            // 10,000 × 6% = 600 TPIX (เผื่อเศษปัดและบล็อกที่เพิ่มขึ้น 1 วินาที)
            expect(earned).to.be.gte(ethers.parseEther("599.99"));
            expect(earned).to.be.lte(ethers.parseEther("600.01"));
        });

        it("pool เติม 5M แล้วโหนดเดียวเคลมได้แค่ตามเพดาน pool ยังเหลือเกือบเต็ม", async function () {
            const { registry, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(YEAR);
            await registry.connect(alice).claimRewards();

            const paid = await registry.totalRewardsDistributed();
            expect(paid).to.be.lte(ethers.parseEther("600.01"));
            expect(await registry.availableRewardFunds()).to.be.gte(ethers.parseEther("5000000") - ethers.parseEther("600.01"));
        });

        it("เพดาน APR ของแต่ละชั้นตรงกับที่โฆษณา (G 12%, S 9%, L 6%, V 20%)", async function () {
            const { registry } = await loadFixture(deployFixture);
            expect(await registry.tierAprCapBps(TIER.GUARDIAN)).to.equal(1200);
            expect(await registry.tierAprCapBps(TIER.SENTINEL)).to.equal(900);
            expect(await registry.tierAprCapBps(TIER.LIGHT)).to.equal(600);
            expect(await registry.tierAprCapBps(TIER.VALIDATOR)).to.equal(2000);
        });

        it("nodeRewardRate บอก APR ที่คนสมัครใหม่จะได้จริง", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            const [cur0, next0] = await registry.nodeRewardRate(TIER.LIGHT);
            expect(cur0).to.equal(0);                // ยังไม่มีใครอยู่ในชั้น
            const aprBps = (next0 * BigInt(YEAR) * 10000n) / LIGHT_STAKE;
            expect(aprBps).to.be.gte(599n);
            expect(aprBps).to.be.lte(600n);

            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            const [cur1] = await registry.nodeRewardRate(TIER.LIGHT);
            expect(cur1).to.equal(next0);
        });

        it("ชั้นที่คนเยอะจน emission ต่อหัวต่ำกว่าเพดาน → หารตาม emission (ตารางปล่อยยังเป็นเพดานรวม)", async function () {
            const { registry, owner, alice, bob } = await loadFixture(fundedFixture);
            // ย่อส่วนแบ่ง Light เหลือ 0.01% ของ 600M/ปี = 60,000 TPIX/ปี และยก min stake เป็น 10M
            // → เพดาน 6% ของ 10M = 600,000/ปี สูงกว่าส่วนแบ่ง ทำให้ emission เป็นตัวจำกัด
            await registry.connect(owner).setRewardShares(3500, 4499, 1, 2000);
            await registry.connect(owner).updateTierConfig(TIER.LIGHT, ethers.parseEther("10000000"), 0, 7, 0, 1);

            const big = ethers.parseEther("10000000");
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: big });
            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: big });
            await time.increase(YEAR);

            const a = await registry.pendingReward(alice.address);
            // 60,000/ปี หาร 2 = ~30,000 ต่อคน (อนุโลม 0.1%)
            expect(a).to.be.gte(ethers.parseEther("29970"));
            expect(a).to.be.lte(ethers.parseEther("30030"));
        });

        it("เปลี่ยนเพดานกลางทาง: ช่วงก่อนหน้าคิดด้วยเพดานเดิม", async function () {
            const { registry, owner, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(YEAR);
            await registry.connect(owner).setTierAprCap(TIER.LIGHT, 300);   // 3%
            await time.increase(YEAR);

            const earned = await registry.pendingReward(alice.address);
            // 600 (ปีแรก 6%) + 300 (ปีที่สอง 3% — ยังเป็นอัตราปีแรกของตาราง เพราะยังไม่มีใคร advance)
            expect(earned).to.be.gte(ethers.parseEther("899.9"));
            expect(earned).to.be.lte(ethers.parseEther("900.1"));
        });

        it("setTierAprCap: owner เท่านั้น และอยู่ในช่วง 1..5000", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);
            await expect(registry.connect(alice).setTierAprCap(TIER.LIGHT, 100))
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
            await expect(registry.connect(owner).setTierAprCap(TIER.LIGHT, 0))
                .to.be.revertedWith("APR cap out of range");
            await expect(registry.connect(owner).setTierAprCap(TIER.LIGHT, 5001))
                .to.be.revertedWith("APR cap out of range");
            await expect(registry.connect(owner).setTierAprCap(TIER.LIGHT, 5000))
                .to.emit(registry, "TierAprCapUpdated").withArgs(TIER.LIGHT, 5000);
        });
    });

    describe("audit 2026-10: ย้ายสัดส่วนรางวัลระหว่างชั้น", function () {
        it("updateTierConfig ย้ายส่วนแบ่งทีละชั้นไม่ได้ (ผลรวมพังทันที) → ต้องใช้ setRewardShares", async function () {
            const { registry, owner } = await loadFixture(deployFixture);
            await expect(
                registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 7, 0, 1000)
            ).to.be.revertedWith("Shares must sum to 10000");

            await registry.connect(owner).setRewardShares(4000, 3000, 1000, 2000);
            expect((await registry.getTierInfo(TIER.GUARDIAN)).rewardShare).to.equal(4000);
            expect((await registry.getTierInfo(TIER.LIGHT)).rewardShare).to.equal(1000);
            await expect(registry.connect(owner).setRewardShares(4000, 3000, 1000, 1999))
                .to.be.revertedWith("Shares must sum to 10000");
        });

        it("คนอื่นเปลี่ยนสัดส่วนไม่ได้", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(registry.connect(alice).setRewardShares(4000, 3000, 1000, 2000))
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
        });
    });

    describe("audit 2026-10: stake ต้องพอดีขั้นต่ำ", function () {
        it("ส่งเกินขั้นต่ำ → revert (รางวัลเท่ากันต่อโหนด ส่งเกินมีแต่ถูกล็อกฟรี)", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(
                registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE + 1n })
            ).to.be.revertedWith("Stake must equal tier minimum");
        });

        it("ส่งขาด → Insufficient stake เหมือนเดิม (ข้อความเดิมที่เว็บ/แอปแปลไว้)", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(
                registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE - 1n })
            ).to.be.revertedWith("Insufficient stake");
        });

        it("ชั้นเต็ม → Tier full", async function () {
            const { registry, owner, alice, bob } = await loadFixture(deployFixture);
            await registry.connect(owner).updateTierConfig(TIER.SENTINEL, SENTINEL_STAKE, 1, 30, 500, 3000);
            await registry.connect(alice).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await expect(
                registry.connect(bob).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE })
            ).to.be.revertedWith("Tier full");
        });
    });

    describe("audit 2026-10: หยุดรับสมัครชั่วคราว", function () {
        it("หยุดแล้วสมัครใหม่ไม่ได้ แต่ถอน/เคลมของคนเดิมยังทำได้", async function () {
            const { registry, owner, alice, bob } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(8 * 24 * 60 * 60);

            await expect(registry.connect(owner).setRegistrationPaused(true))
                .to.emit(registry, "RegistrationPaused").withArgs(true);
            await expect(
                registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE })
            ).to.be.revertedWith("Registration paused");

            await registry.connect(alice).claimRewards();
            expect(await registry.totalRewardsDistributed()).to.be.gt(0);
            await registry.connect(alice).deregisterNode();
            expect((await registry.getNodeInfo(alice.address)).stakedAmount).to.equal(0);

            await registry.connect(owner).setRegistrationPaused(false);
            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
        });

        it("คนอื่นหยุดระบบไม่ได้", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            await expect(registry.connect(alice).setRegistrationPaused(true))
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
        });
    });

    describe("audit 2026-10: slash ย้อนหลังแรงกว่าตอนสมัครไม่ได้", function () {
        it("Light สมัครตอน slash 0% → owner ขึ้นเป็นเพดาน 15% ทีหลัง เงินต้นต้องไม่ถูกตัด", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 7, 1500, 1500);

            await registry.connect(owner).slashNode(alice.address, "test");
            expect((await registry.getNodeInfo(alice.address)).stakedAmount).to.equal(LIGHT_STAKE);
            await registry.connect(alice).withdrawSlashedStake();
            expect((await registry.getNodeInfo(alice.address)).stakedAmount).to.equal(0);
        });

        it("owner ลด % ลงทีหลัง → ใช้ % ที่ต่ำกว่า", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await registry.connect(owner).updateTierConfig(TIER.SENTINEL, SENTINEL_STAKE, 500, 30, 200, 3000);
            await registry.connect(owner).slashNode(alice.address, "test");
            expect((await registry.getNodeInfo(alice.address)).stakedAmount)
                .to.equal(SENTINEL_STAKE - (SENTINEL_STAKE * 200n) / 10000n);
        });

        it("เงินที่ถูก slash ไม่ออกไปหาใคร — อยู่ในสัญญาเป็นงบรางวัล", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await registry.connect(owner).slashNode(alice.address, "test");
            const slashed = (SENTINEL_STAKE * 500n) / 10000n;
            expect(await ethers.provider.getBalance(await registry.getAddress())).to.equal(SENTINEL_STAKE);
            expect(await registry.availableRewardFunds()).to.equal(slashed);
        });
    });

    describe("audit 2026-10: reentrancy จาก operator ที่เป็นสัญญา", function () {
        it("เจาะ claimRewards/deregisterNode ซ้ำตอนรับเงิน → ได้แค่รอบเดียว เงินต้นคนอื่นไม่หาย", async function () {
            const { registry, bob } = await loadFixture(fundedFixture);
            const Probe = await ethers.getContractFactory("RegistryReentrancyProbe");
            const probe = await Probe.deploy(await registry.getAddress());
            await probe.waitForDeployment();

            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await probe.register(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(30 * 24 * 60 * 60);

            await probe.claim();
            expect(await probe.reentryAttempts()).to.equal(1);
            expect(await probe.reentrySucceeded()).to.equal(0);

            const paid = await registry.totalRewardsDistributed();
            expect(paid).to.be.gt(0);
            expect(paid).to.be.lte(ethers.parseEther("49.4"));   // 30 วันที่ 6% ของ 10K ≈ 49.32
            expect(await ethers.provider.getBalance(await registry.getAddress()))
                .to.be.gte(await registry.totalStaked());

            // ถอนตอนพ้นล็อก — ต้องได้เงินต้นคืนครั้งเดียว
            await probe.exit();
            expect(await registry.totalStaked()).to.equal(LIGHT_STAKE);   // เหลือของ bob
            expect(await ethers.provider.getBalance(await probe.getAddress()))
                .to.be.gte(LIGHT_STAKE);
        });
    });

    describe("audit 2026-10: owner ถอนเงินออกจากสัญญาไม่ได้เลย", function () {
        it("ABI ไม่มีฟังก์ชันถอน/โอนเงินของ owner", async function () {
            const { registry } = await loadFixture(deployFixture);
            const names = registry.interface.fragments
                .filter((f) => f.type === "function")
                .map((f) => f.name);
            for (const bad of ["withdraw", "emergencyWithdraw", "sweep", "rescue", "withdrawRewardPool", "transferFunds"]) {
                expect(names).to.not.include(bad);
            }
        });
    });

    describe("audit 2026-10b: เปลี่ยน minStake ตอนชั้นยังมีโหนดอยู่", function () {
        const YEAR = 365 * 24 * 60 * 60;

        it("owner ขึ้น minStake ทีหลัง → โหนดเดิมที่วาง 10K ต้องไม่ได้เกิน 6% ของเงินต้นตัวเอง", async function () {
            const { registry, owner, alice } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            // เพดาน APR คิดจาก minStake ของชั้น ไม่ใช่เงินต้นของโหนด — ถ้ายอมให้เปลี่ยน
            // alice จะได้ 6% ของ 20K = 1,200 TPIX/ปี (12% ของเงินต้นจริง)
            await registry.connect(owner)
                .updateTierConfig(TIER.LIGHT, LIGHT_STAKE * 2n, 0, 7, 0, 1500)
                .catch(() => {});
            await time.increase(YEAR);

            expect(await registry.pendingReward(alice.address)).to.be.lte(ethers.parseEther("600.01"));
        });

        it("owner ตั้ง minStake มหาศาลตอนมีโหนดอยู่ → ห้ามทำให้ถอนเงินต้นไม่ได้ถาวร", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            // minStake × เพดาน APR × 1e18 ล้น uint256 → _syncTier ของชั้นนี้ revert ทุกครั้ง
            // (รวมถึง updateTierConfig เองที่ต้อง sync ก่อน — แก้กลับก็ไม่ได้)
            await registry.connect(owner)
                .updateTierConfig(TIER.LIGHT, 2n ** 200n, 0, 7, 0, 1500)
                .catch(() => {});
            await time.increase(8 * 24 * 60 * 60);

            await registry.connect(alice).deregisterNode();
            expect((await registry.getNodeInfo(alice.address)).stakedAmount).to.equal(0);
            expect(await ethers.provider.getBalance(await registry.getAddress())).to.equal(0);
        });

        it("ชั้นที่มีโหนดอยู่: เปลี่ยน minStake ไม่ได้ แต่ปรับค่าอื่นได้ / ชั้นว่างเปลี่ยนได้", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            await expect(
                registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE * 2n, 0, 7, 0, 1500)
            ).to.be.revertedWith("Tier has active nodes");

            // minStake เท่าเดิม → ปรับ lock / โควตาได้ตามปกติ
            await expect(registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 1000, 14, 0, 1500))
                .to.emit(registry, "TierConfigUpdated").withArgs(TIER.LIGHT);
            // ชั้นที่ยังไม่มีใคร → เปลี่ยน minStake ได้
            await registry.connect(owner).updateTierConfig(TIER.SENTINEL, SENTINEL_STAKE * 2n, 500, 30, 500, 3000);
            expect((await registry.getTierInfo(TIER.SENTINEL)).minStake).to.equal(SENTINEL_STAKE * 2n);

            // คนสุดท้ายออกแล้ว ชั้นว่าง → เปลี่ยนได้
            await time.increase(8 * 24 * 60 * 60);
            await registry.connect(alice).deregisterNode();
            await registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE * 2n, 0, 7, 0, 1500);
            expect((await registry.getTierInfo(TIER.LIGHT)).minStake).to.equal(LIGHT_STAKE * 2n);
        });
    });

    describe("audit 2026-10c: ระยะล็อก · KYC · ถอนตอนพูลว่าง", function () {
        const DAY = 24 * 60 * 60;

        it("owner (ซึ่งรัน validator เอง) แทรก lockDays 100 ปีก่อน tx สมัคร → เงินต้นต้องไม่ถูกขังเกิน 180 วัน", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);

            // ผู้ใช้เห็น Light ล็อก 7 วันแล้วกดสมัคร — owner/validator แทรก tx ก่อนในบล็อกเดียวกันได้
            // registerNode ไม่มีพารามิเตอร์ "ล็อกได้ไม่เกิน" ให้ผู้ใช้กันเอง → ต้องมีเพดานในสัญญา
            await registry.connect(owner)
                .updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 36500, 0, 1500)
                .catch(() => {});
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            const n = await registry.getNodeInfo(alice.address);
            expect(n.unlockAt - n.registeredAt).to.be.lte(180n * BigInt(DAY));
        });

        it("สัญญา KYC ที่เปลี่ยนเป็น revert / ถูกถอดออก ห้ามขวาง Validator ถอนหรือเคลม", async function () {
            const { registry, owner, alice, funder } = await loadFixture(deployFixture);
            const kyc = "0x00000000000000000000000000000000000c0de1";
            await setCode(kyc, "0x600160005260206000f3");            // isApproved → true
            await registry.connect(owner).setKYCContract(kyc);
            const V_STAKE = ethers.parseEther("10000000");
            await registry.connect(alice).registerNode(TIER.VALIDATOR, ENDPOINT, { value: V_STAKE });
            await funder.sendTransaction({ to: await registry.getAddress(), value: ethers.parseEther("1000000") });

            // KYC "อัปเกรด" เป็นโค้ดที่ revert ทุกครั้ง แล้ว owner ถอดออกอีกที
            await setCode(kyc, "0x60006000fd");
            await time.increase(181 * DAY);
            await registry.connect(alice).claimRewards();
            await registry.connect(owner).setKYCContract(ethers.ZeroAddress);
            const before = await ethers.provider.getBalance(alice.address);
            const rc = await (await registry.connect(alice).deregisterNode()).wait();
            const after = await ethers.provider.getBalance(alice.address);
            expect(after - before + rc.gasUsed * rc.gasPrice).to.be.gte(V_STAKE);
            expect(await registry.totalStaked()).to.equal(0);
        });

        it("ถอนตอนพูลว่าง: ได้เงินต้นครบ รางวัลค้างเป็นหนี้ · สมัครใหม่ต้องรอเคลมก่อน", async function () {
            const { registry, alice, funder } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(8 * DAY);
            await registry.connect(alice).deregisterNode();

            const owed = await registry.pendingReward(alice.address);
            expect(owed).to.be.gt(0);
            expect(await ethers.provider.getBalance(await registry.getAddress())).to.equal(0);
            await expect(registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE }))
                .to.be.revertedWith("Claim pending rewards first");

            await registry.connect(funder).fundRewardPool({ value: ethers.parseEther("1000") });
            await expect(registry.connect(alice).claimRewards())
                .to.emit(registry, "RewardClaimed").withArgs(alice.address, owed);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
        });
    });

    describe("audit 2026-10d: แทรก % slash ก่อนสมัคร · uptime oracle · โอน owner 2 ขั้น", function () {
        const DAY = 24 * 60 * 60;
        const YEAR = 365 * DAY;

        it("owner (ซึ่งรัน validator เอง) แทรก slash 50% ก่อน tx สมัคร → เงินต้นต้องไม่ถูกตัดเกิน 15%", async function () {
            const { registry, owner, alice } = await loadFixture(deployFixture);

            // ช่องเดียวกับ lockDays: สัญญาจำ % slash ณ ตอนสมัครเป็นเพดานของโหนด
            // ผู้ใช้เห็น Light slash 0% แต่ owner แทรก tx ตั้ง 50% ไว้ก่อนในบล็อกเดียวกันได้
            await registry.connect(owner)
                .updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 7, 5000, 1500)
                .catch(() => {});
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(owner).slashNode(alice.address, "front-run");

            expect((await registry.getNodeInfo(alice.address)).stakedAmount)
                .to.be.gte(LIGHT_STAKE - (LIGHT_STAKE * 1500n) / 10000n);
        });

        it("slash เกิน 15% → revert · 15% พอดีได้ · lockDays เกิน 180 → revert · 180 พอดีได้", async function () {
            const { registry, owner } = await loadFixture(deployFixture);
            expect(await registry.MAX_SLASH_BPS()).to.equal(1500);
            expect(await registry.MAX_LOCK_DAYS()).to.equal(180);
            await expect(registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 7, 1501, 1500))
                .to.be.revertedWith("Max 15% slash");
            await expect(registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 181, 0, 1500))
                .to.be.revertedWith("Max 180-day lock");
            await expect(registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 180, 1500, 1500))
                .to.emit(registry, "TierConfigUpdated").withArgs(TIER.LIGHT);
        });

        it("ยังไม่ตั้ง oracle: โหนดใหม่เริ่ม uptime 100% เหมือนเดิม", async function () {
            const { registry, alice } = await loadFixture(deployFixture);
            expect(await registry.uptimeOracle()).to.equal(ethers.ZeroAddress);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            expect((await registry.getNodeInfo(alice.address)).uptime).to.equal(10000);
        });

        it("ตั้ง oracle แล้ว: โหนดใหม่เริ่ม 0% ไม่ได้รางวัลจนกว่า oracle ยืนยันว่ารันเครื่องจริง", async function () {
            const { registry, owner, alice, carol } = await loadFixture(fundedFixture);
            await expect(registry.connect(owner).setUptimeOracle(carol.address))
                .to.emit(registry, "UptimeOracleUpdated").withArgs(carol.address);

            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            expect((await registry.getNodeInfo(alice.address)).uptime).to.equal(0);
            await time.increase(10 * DAY);
            expect(await registry.pendingReward(alice.address)).to.equal(0);

            // oracle เห็นว่าเครื่องเปิดจริง → ได้รางวัลตั้งแต่ตอนนั้นไป (ไม่ย้อนหลัง)
            await registry.connect(carol).updateUptime(alice.address, 10000);
            await time.increase(YEAR);
            const owed = await registry.pendingReward(alice.address);
            expect(owed).to.be.gte(ethers.parseEther("599.9"));    // 6% ของ 10K ต่อปี
            expect(owed).to.be.lte(ethers.parseEther("600.01"));
        });

        it("oracle ตั้งได้ทีละชุด: ข้ามโหนดที่ไม่ active และย้อนไปตัดรางวัลที่หาไว้แล้วไม่ได้", async function () {
            const { registry, owner, alice, bob, carol } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(owner).setUptimeOracle(carol.address);
            await time.increase(30 * DAY);
            const before = await registry.pendingReward(alice.address);

            // bob ไม่ได้ลงโหนด — ชุดต้องไม่ล้มทั้งชุดเพราะคนเดียว
            await expect(registry.connect(carol).updateUptimeBatch([alice.address, bob.address], [0, 10000]))
                .to.emit(registry, "UptimeUpdated").withArgs(alice.address, 0);
            expect((await registry.getNodeInfo(alice.address)).uptime).to.equal(0);
            expect((await registry.getNodeInfo(bob.address)).status).to.equal(0);   // Inactive เหมือนเดิม
            expect((await registry.getNodeInfo(bob.address)).uptime).to.equal(0);   // ข้ามจริง ไม่ได้เขียนทับ
            expect(await registry.pendingReward(alice.address)).to.be.gte(before);

            await time.increase(30 * DAY);
            const frozen = await registry.pendingReward(alice.address);
            await time.increase(30 * DAY);
            expect(await registry.pendingReward(alice.address)).to.equal(frozen);  // uptime 0 = ไม่เพิ่ม
        });

        it("batch: ความยาวไม่ตรง / เกิน 100 / ค่าเกิน 10000 → revert", async function () {
            const { registry, owner, alice, carol } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(owner).setUptimeOracle(carol.address);
            await expect(registry.connect(carol).updateUptimeBatch([alice.address], [1, 2]))
                .to.be.revertedWith("Length mismatch");
            const many = Array(101).fill(alice.address);
            await expect(registry.connect(carol).updateUptimeBatch(many, Array(101).fill(1)))
                .to.be.revertedWith("Batch too large");
            await expect(registry.connect(carol).updateUptimeBatch([alice.address], [10001]))
                .to.be.revertedWith("Max 10000");
        });

        it("batch เต็ม 100 โหนด (กรณีแพงสุด: รางวัลค้าง 0 → มีค่าทุกตัว) ใช้แก๊สต่ำกว่าเพดานบล็อก 10M พอสมควร", async function () {
            this.timeout(120000);
            const { registry, owner, carol } = await loadFixture(fundedFixture);
            await registry.connect(owner).setUptimeOracle(carol.address);
            const ops = [];
            for (let i = 0; i < 100; i++) {
                const w = ethers.Wallet.createRandom().connect(ethers.provider);
                await setBalance(w.address, ethers.parseEther("20000"));
                await registry.connect(w).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
                ops.push(w.address);
            }
            await registry.connect(carol).updateUptimeBatch(ops, Array(100).fill(10000));
            await time.increase(30 * DAY);
            const rc = await (await registry.connect(carol).updateUptimeBatch(ops, Array(100).fill(5000))).wait();
            expect(rc.gasUsed, `gas ${rc.gasUsed}`).to.be.lt(8_000_000n);
        });

        it("oracle แตะได้แค่ uptime — slash / แก้เงื่อนไข / หยุดระบบ / ตั้ง oracle / โอน owner ไม่ได้", async function () {
            const { registry, owner, alice, carol } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await registry.connect(owner).setUptimeOracle(carol.address);
            const o = registry.connect(carol);
            const denied = "OwnableUnauthorizedAccount";
            await expect(o.slashNode(alice.address, "x")).to.be.revertedWithCustomError(registry, denied);
            await expect(o.updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 7, 0, 1500)).to.be.revertedWithCustomError(registry, denied);
            await expect(o.setRewardShares(2500, 2500, 2500, 2500)).to.be.revertedWithCustomError(registry, denied);
            await expect(o.setTierAprCap(TIER.LIGHT, 5000)).to.be.revertedWithCustomError(registry, denied);
            await expect(o.setRegistrationPaused(true)).to.be.revertedWithCustomError(registry, denied);
            await expect(o.setKYCContract(carol.address)).to.be.revertedWithCustomError(registry, denied);
            await expect(o.setUptimeOracle(carol.address)).to.be.revertedWithCustomError(registry, denied);
            await expect(o.transferOwnership(carol.address)).to.be.revertedWithCustomError(registry, denied);
            expect((await registry.getNodeInfo(alice.address)).stakedAmount).to.equal(SENTINEL_STAKE);
        });

        it("ถอด oracle แล้วตั้ง uptime ไม่ได้อีก · คนนอกตั้งไม่ได้", async function () {
            const { registry, owner, alice, bob, carol } = await loadFixture(deployFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(owner).setUptimeOracle(carol.address);
            await expect(registry.connect(bob).updateUptime(alice.address, 0))
                .to.be.revertedWith("Not owner or uptime oracle");
            await registry.connect(owner).setUptimeOracle(ethers.ZeroAddress);
            await expect(registry.connect(carol).updateUptime(alice.address, 0))
                .to.be.revertedWith("Not owner or uptime oracle");
            await expect(registry.connect(carol).updateUptimeBatch([alice.address], [0]))
                .to.be.revertedWith("Not owner or uptime oracle");
            await registry.connect(owner).updateUptime(alice.address, 5000);      // owner ยังทำได้
        });

        it("โอน owner ต้องให้ปลายทางกดรับก่อน — พิมพ์ที่อยู่ผิดไม่เสียสิทธิ์แอดมิน", async function () {
            const { registry, owner, bob, carol } = await loadFixture(deployFixture);
            await registry.connect(owner).transferOwnership(bob.address);       // สมมติพิมพ์ผิด
            expect(await registry.owner()).to.equal(owner.address);
            expect(await registry.pendingOwner()).to.equal(bob.address);
            await registry.connect(owner).setRegistrationPaused(true);            // ยังเป็นแอดมินอยู่

            await registry.connect(owner).transferOwnership(carol.address);      // แก้ปลายทาง
            await expect(registry.connect(bob).acceptOwnership())
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
            await registry.connect(carol).acceptOwnership();
            expect(await registry.owner()).to.equal(carol.address);
            await expect(registry.connect(owner).setRegistrationPaused(false))
                .to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
        });
    });

    describe("security 2026-10-22: กุญแจ owner / oracle ถูกยึด", function () {
        const DAY = 24 * 60 * 60;
        const REVERT_CODE = "0x60006000fd";
        const balanceOf = (a) => ethers.provider.getBalance(a);

        // ผู้โจมตีถือกุญแจ owner แล้วใช้ทุกสิทธิ์ที่สัญญามีพร้อมกัน — เงินต้นต้องเสียได้ไม่เกินเพดาน
        // และต้องถอนออกได้เสมอ (ไม่มีทางขังถาวร ไม่มีทางดึงเงินออกไปที่ใคร)
        it("owner ถูกยึด: แทรกเงื่อนไขสูงสุด + slash + หยุดระบบ + uptime 0 + ตัดรางวัล + KYC พัง + โอน/สละ owner → เงินต้นเสียไม่เกิน 15% ถอนได้ใน 180 วัน", async function () {
            this.timeout(60000);
            const { registry, owner, alice, bob, carol, funder } = await loadFixture(fundedFixture);
            const [, , , , , attacker2] = await ethers.getSigners();
            const regAddr = await registry.getAddress();

            // bob สมัครก่อนโดนยึด (Light: slash 0% ล็อก 7 วัน) แล้วหารางวัลไว้ 30 วัน
            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await time.increase(30 * DAY);
            const bobEarned = await registry.pendingReward(bob.address);
            expect(bobEarned).to.be.gt(0);

            // ── กุญแจหลุด ──
            await registry.connect(owner).updateTierConfig(TIER.LIGHT, LIGHT_STAKE, 0, 180, 1500, 1500);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(carol).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });

            await registry.connect(owner).setUptimeOracle(owner.address);
            await registry.connect(owner).updateUptimeBatch([alice.address, bob.address, carol.address], [0, 0, 0]);
            await registry.connect(owner).setTierAprCap(TIER.LIGHT, 1);
            await registry.connect(owner).setRewardShares(5000, 5000, 0, 0);
            const kyc = "0x00000000000000000000000000000000000c0de2";
            await setCode(kyc, REVERT_CODE);
            await registry.connect(owner).setKYCContract(kyc);
            await registry.connect(owner).setRegistrationPaused(true);
            await registry.connect(owner).slashNode(alice.address, "attack");
            await registry.connect(owner).slashNode(bob.address, "attack");          // สมัครตอน 0% → ตัดไม่ได้
            await registry.connect(owner).transferOwnership(attacker2.address);
            await registry.connect(attacker2).acceptOwnership();
            await registry.connect(attacker2).renounceOwnership();
            expect(await registry.owner()).to.equal(ethers.ZeroAddress);

            // ── ผู้ใช้ถอนเงิน ──
            // alice โดน slash: ได้ส่วนที่เหลือคืนทันที ไม่ต้องรอล็อก
            await registry.connect(alice).withdrawSlashedStake();
            // bob: % ตอนสมัคร = 0 → เงินต้นครบ + รางวัลที่หาไว้ก่อนโดนยึดยังเคลมได้
            expect(await registry.pendingReward(bob.address)).to.be.gte(bobEarned);
            await registry.connect(bob).withdrawSlashedStake();
            await registry.connect(bob).claimRewards();
            // carol ไม่โดน slash แต่โดนล็อก 180 วัน (เพดาน) — ก่อนครบถอนไม่ได้ ครบแล้วได้เต็ม
            await expect(registry.connect(carol).deregisterNode()).to.be.revertedWith("Still locked");
            await time.increase(180 * DAY);
            const before = await balanceOf(carol.address);
            const rc = await (await registry.connect(carol).deregisterNode()).wait();
            // เงินต้นครบ + รางวัลเศษไม่กี่วินาทีก่อนผู้โจมตีตั้ง uptime 0 (หาไว้แล้ว ต้องได้)
            const carolGot = await balanceOf(carol.address) - before + rc.gasUsed * rc.gasPrice;
            const carolRewards = (await registry.getNodeInfo(carol.address)).totalRewards;
            expect(carolGot).to.equal(LIGHT_STAKE + carolRewards);
            expect(carolRewards).to.be.lt(ethers.parseEther("1"));

            expect((await registry.getNodeInfo(alice.address)).totalRewards).to.equal(0);
            expect((await registry.getNodeInfo(bob.address)).totalRewards).to.be.gte(bobEarned);
            expect(await registry.totalStaked()).to.equal(0);
            // ที่ถูก slash (15% ของ alice) ยังอยู่ในสัญญาเป็นงบรางวัล — ไม่ได้ออกไปหาผู้โจมตี
            const slashed = (LIGHT_STAKE * 1500n) / 10000n;
            const funded = ethers.parseEther("5000000");
            const paidOut = (await registry.getNodeInfo(bob.address)).totalRewards + carolRewards;
            expect(await registry.totalRewardsDistributed()).to.equal(paidOut);
            expect(await balanceOf(regAddr)).to.equal(funded + slashed - paidOut);
            expect(await registry.availableRewardFunds()).to.equal(funded + slashed - paidOut);
            void funder;
        });

        it("oracle ถูกยึด: ตั้ง 0 ทุกคนรัว ๆ ได้แค่หยุดรางวัลจากนี้ไป — รางวัลที่หาไว้แล้วและเงินต้นอยู่ครบ", async function () {
            const { registry, owner, alice, bob, carol } = await loadFixture(fundedFixture);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(bob).registerNode(TIER.SENTINEL, ENDPOINT, { value: SENTINEL_STAKE });
            await time.increase(60 * DAY);
            const earnedA = await registry.pendingReward(alice.address);
            const earnedB = await registry.pendingReward(bob.address);

            await registry.connect(owner).setUptimeOracle(carol.address);
            for (let i = 0; i < 5; i++) {
                await registry.connect(carol).updateUptimeBatch([alice.address, bob.address, alice.address], [0, 0, 0]);
            }
            await time.increase(60 * DAY);
            expect(await registry.pendingReward(alice.address)).to.be.gte(earnedA);
            expect(await registry.pendingReward(alice.address)).to.be.lt(earnedA + ethers.parseEther("0.01"));
            expect(await registry.pendingReward(bob.address)).to.be.gte(earnedB);

            // owner ถอด oracle แล้วคืนค่าได้ · ทุกคนถอนเงินต้นครบ
            await registry.connect(owner).setUptimeOracle(ethers.ZeroAddress);
            await registry.connect(owner).updateUptimeBatch([alice.address, bob.address], [10000, 10000]);
            await registry.connect(alice).deregisterNode();
            await registry.connect(bob).deregisterNode();
            expect(await registry.totalStaked()).to.equal(0);
            expect((await registry.getNodeInfo(alice.address)).totalRewards).to.be.gte(earnedA);
        });

        it("oracle ถูกยึด: ตั้ง 100% ให้โหนดที่ไม่ได้รันได้แค่เพดาน APR และจ่ายจากพูลเท่านั้น — ไม่แตะเงินต้นคนอื่น", async function () {
            const { registry, owner, alice, bob, carol, funder } = await loadFixture(deployFixture);
            await registry.connect(owner).setUptimeOracle(carol.address);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(bob).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(carol).updateUptime(alice.address, 10000);       // alice ไม่ได้รันจริง
            await registry.connect(funder).fundRewardPool({ value: ethers.parseEther("100") });
            await time.increase(365 * DAY);

            // ได้ไม่เกิน 6% ของ 10K/ปี และจ่ายได้แค่ 100 ที่อยู่ในพูล — เงินต้นของ bob ไม่ถูกแตะ
            expect(await registry.pendingReward(alice.address)).to.be.lte(ethers.parseEther("600.01"));
            await registry.connect(alice).claimRewards();
            expect((await registry.getNodeInfo(alice.address)).totalRewards).to.equal(ethers.parseEther("100"));
            expect(await ethers.provider.getBalance(await registry.getAddress())).to.equal(LIGHT_STAKE * 2n);
            await registry.connect(bob).deregisterNode();
            expect((await registry.getNodeInfo(bob.address)).stakedAmount).to.equal(0);
        });

        it("batch: ที่อยู่ซ้ำ = ค่าหลังสุดชนะ · ที่อยู่ศูนย์/ไม่เคยสมัครถูกข้าม ไม่ทำให้ทั้งชุดล้ม", async function () {
            const { registry, owner, alice, carol } = await loadFixture(deployFixture);
            await registry.connect(owner).setUptimeOracle(carol.address);
            await registry.connect(alice).registerNode(TIER.LIGHT, ENDPOINT, { value: LIGHT_STAKE });
            await registry.connect(carol).updateUptimeBatch(
                [alice.address, ethers.ZeroAddress, alice.address], [10000, 10000, 2500]);
            expect((await registry.getNodeInfo(alice.address)).uptime).to.equal(2500);
            expect((await registry.getNodeInfo(ethers.ZeroAddress)).status).to.equal(0);
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
