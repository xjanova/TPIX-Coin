const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { loadFixture, setBalance } = require("@nomicfoundation/hardhat-network-helpers");
const { inspectRegistry, runwayDays, fundPool } = require("../scripts/lib/reward-pool");

/**
 * ทดสอบเส้นทางเดียวกับ fund-reward-pool.js (ต่างแค่ provider/signer มาจาก hardhat)
 *
 * สิ่งที่ต้องพิสูจน์ก่อนให้เจ้าของเติมเงินจริงหลักสิบล้าน TPIX:
 *   1. เติมด้วย fundRewardPool() แล้วเงินเข้าพูลจริง ไม่ปนกับเงินต้น
 *   2. การโอนธรรมดา 21,000 gas (send-tpix.ps1) ล้ม — ต้องใช้สคริปต์นี้เท่านั้น
 *   3. ปฏิเสธสัญญารุ่นเก่าที่ไม่มีเพดาน APR / ที่อยู่ว่าง / เชนผิด
 *   4. ตัวเลข "พอจ่ายกี่วัน" ถูกต้อง
 */
describe("fund-reward-pool script helpers", function () {
    const LIGHT_STAKE = ethers.parseEther("10000");

    async function fixture() {
        const [owner, alice, funder] = await ethers.getSigners();
        for (const s of [owner, alice, funder]) await setBalance(s.address, ethers.parseEther("1000000"));
        const Registry = await ethers.getContractFactory("NodeRegistryV2");
        const registry = await Registry.deploy();
        await registry.waitForDeployment();
        return { registry, address: await registry.getAddress(), owner, alice, funder };
    }

    it("อ่านสถานะได้ และยังไม่มีโหนด = ไม่มีรายจ่าย", async function () {
        const { address } = await loadFixture(fixture);
        const s = await inspectRegistry(ethers.provider, address, 4289);
        expect(s.fundedBalanceWei).to.equal(0n);
        expect(s.annualOutflowWei).to.equal(0n);
        expect(s.tiers.map((t) => t.aprCapBps)).to.deep.equal([1200, 900, 600, 2000]);
        expect(runwayDays(s.fundedBalanceWei, s.annualOutflowWei)).to.equal(null);
    });

    it("เติมด้วย fundRewardPool() แล้วพูลเพิ่มจริง และบอกวันที่พอจ่ายถูก", async function () {
        const { registry, address, alice, funder } = await loadFixture(fixture);
        await registry.connect(alice).registerNode(2, "203.0.113.10:8545", { value: LIGHT_STAKE });

        const r = await fundPool(funder, address, ethers.parseEther("300"));
        expect(r.txHash).to.match(/^0x[0-9a-f]{64}$/);
        expect(r.gasUsed).to.be.lt(r.gasLimit);

        const s = await inspectRegistry(ethers.provider, address, 4289);
        expect(s.fundedBalanceWei).to.equal(ethers.parseEther("300"));
        // Light 1 โหนดที่ 6% ของ 10,000 = 600 TPIX/ปี → 300 TPIX พอ ~182.5 วัน
        const days = runwayDays(s.fundedBalanceWei, s.annualOutflowWei);
        expect(days).to.be.closeTo(182.5, 0.1);
        // เงินต้นไม่ถูกนับเป็นเงินในพูล
        expect(await ethers.provider.getBalance(address)).to.equal(LIGHT_STAKE + ethers.parseEther("300"));
    });

    it("dry run ประเมินแก๊สอย่างเดียว ไม่ส่ง", async function () {
        const { address, funder } = await loadFixture(fixture);
        const r = await fundPool(funder, address, ethers.parseEther("1"), { dryRun: true });
        expect(r.dryRun).to.equal(true);
        expect(r.gasEstimate).to.be.gt(21000n);
        const s = await inspectRegistry(ethers.provider, address, 4289);
        expect(s.fundedBalanceWei).to.equal(0n);
    });

    it("กับดัก send-tpix.ps1: โอนธรรมดา 21,000 gas เข้า registry ล้มเพราะแก๊สหมด", async function () {
        const { address, funder } = await loadFixture(fixture);
        await expect(
            funder.sendTransaction({ to: address, value: ethers.parseEther("1"), gasLimit: 21000 })
        ).to.be.reverted;
    });

    it("ปฏิเสธที่อยู่ที่ไม่มีโค้ด / เชนผิด / สัญญารุ่นเก่าที่ไม่มีเพดาน APR", async function () {
        const { address, alice } = await loadFixture(fixture);
        await expect(inspectRegistry(ethers.provider, alice.address, 4289)).to.be.rejectedWith(/eth_getCode = 0x/);
        await expect(inspectRegistry(ethers.provider, address, 56)).to.be.rejectedWith(/chainId 4289 ไม่ใช่ 56/);

        const V1 = await ethers.getContractFactory("NodeRegistry");
        const v1 = await V1.deploy();
        await v1.waitForDeployment();
        await expect(inspectRegistry(ethers.provider, await v1.getAddress(), 4289))
            .to.be.rejectedWith(/ไม่มี tierAprCapBps/);
    });

    it("เชนผิดต้องถูกจับแม้ provider ตั้ง staticNetwork (แบบที่ fund-reward-pool.js ใช้)", async function () {
        const { address } = await loadFixture(fixture);
        // fund-reward-pool.js สร้าง JsonRpcProvider(url, 4289, { staticNetwork: true })
        // → getNetwork() ตอบเลขที่เราบอกมันเองโดยไม่ถาม RPC เลย
        // จำลอง: provider อ้างว่าเป็น 56 แต่ RPC ข้างหลังคือเชน 4289 ของ hardhat
        const claims56 = new ethers.BrowserProvider(network.provider, 56, { staticNetwork: true });
        expect((await claims56.getNetwork()).chainId).to.equal(56n);
        await expect(inspectRegistry(claims56, address, 56)).to.be.rejectedWith(/chainId 4289 ไม่ใช่ 56/);
    });

    it("จำนวน 0 ไม่ได้", async function () {
        const { address, funder } = await loadFixture(fixture);
        await expect(fundPool(funder, address, 0n)).to.be.rejectedWith(/มากกว่า 0/);
    });
});
