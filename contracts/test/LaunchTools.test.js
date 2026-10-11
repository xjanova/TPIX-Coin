/**
 * เครื่องมือเปิดตัวเหรียญ (src/launch) — ทดสอบด้วยตัวเลขจริงของ IDTC
 *
 * TrancheVesting: ล็อก 70% ของ 1.1T แบบ A (ตามตาราง + ทยอยรายเดือนหลังครบล็อก)
 *   ก้อน 1 ปี  220B → ปลดเดือน 13–24 · ก้อน 2 ปี 220B → 25–36
 *   ก้อน 3 ปี  165B → 37–48         · ก้อน 4 ปี 165B → 49–60
 * FixedPriceSale: presale ที่ $0.0000015 ต่อ IDTC จ่ายด้วย USDT (6 ทศนิยม) → 1 USDT = 666,666.66… IDTC
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const E18 = 10n ** 18n;
const B = 1_000_000_000n * E18;            // 1 พันล้านเหรียญ
const TOTAL_SUPPLY = 1_100n * B;           // 1.1T
const MONTH = 2_629_800n;                  // เดือนเฉลี่ย = 365.25 วัน / 12
const USDT = 10n ** 6n;

async function deployToken(owner, supply = TOTAL_SUPPLY) {
    const T = await ethers.getContractFactory("FactoryERC20V2");
    // standard: ไม่มี mint/pause/blacklist/auto-burn — แบบเดียวกับที่ IDTC จะใช้
    return T.deploy("Invest Energy-Development Coin", "IDTC", 18, supply, owner,
        false, true, false, false, 0, false, 0, 0);
}

const IDTC_TRANCHES = [
    { amount: 220n * B, cliffPeriods: 12, releasePeriods: 12 },
    { amount: 220n * B, cliffPeriods: 24, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 36, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 48, releasePeriods: 12 },
];

describe("Launch tools — TrancheVesting (IDTC ล็อก 70% แบบ A)", function () {
    let owner, beneficiary, anyone, token, vesting, start;

    beforeEach(async function () {
        [owner, beneficiary, anyone] = await ethers.getSigners();
        token = await deployToken(owner.address);
        start = BigInt(await time.latest()) + 1000n;
        const V = await ethers.getContractFactory("TrancheVesting");
        vesting = await V.deploy(token.target, beneficiary.address, start, MONTH, IDTC_TRANCHES, "IDTC — ล็อก 70%");
    });

    const at = (months, extra = 0n) => start + BigInt(months) * MONTH + extra;

    it("ยอดรวม = 770B (70% ของ 1.1T) และต้องฝากครบถึงจะขึ้นว่าล็อกครบ", async function () {
        expect(await vesting.totalAllocation()).to.equal(770n * B);
        expect(await vesting.isFunded()).to.equal(false);
        await token.transfer(vesting.target, 770n * B);
        expect(await vesting.isFunded()).to.equal(true);
        expect(await token.balanceOf(owner.address)).to.equal(330n * B); // หมุนเวียน 30%
    });

    it("ตลอด 12 เดือนแรกปลดไม่ได้เลย", async function () {
        await token.transfer(vesting.target, 770n * B);
        // tx release() ถูกขุดในบล็อกถัดไป (+1 วินาที) จึงถอยไว้ 2 วินาทีให้ยังอยู่ก่อนงวดแรก
        await time.increaseTo(at(13) - 2n);
        expect(await vesting.releasable()).to.equal(0n);
        await expect(vesting.release()).to.be.revertedWithCustomError(vesting, "NothingToRelease");
    });

    it("ปลดเป็นงวดตามแบบ A: เดือน 13 / 24 / 25 / 60", async function () {
        await token.transfer(vesting.target, 770n * B);

        await time.increaseTo(at(13));
        expect(await vesting.releasable()).to.equal((220n * B) / 12n);

        await time.increaseTo(at(24));
        expect(await vesting.vestedAmount(at(24))).to.equal(220n * B);

        expect(await vesting.vestedAmount(at(25))).to.equal(220n * B + (220n * B) / 12n);
        expect(await vesting.vestedAmount(at(48))).to.equal(605n * B);   // 220+220+165
        expect(await vesting.vestedAmount(at(60))).to.equal(770n * B);
        expect(await vesting.vestedAmount(at(100))).to.equal(770n * B);
    });

    it("ไม่มีงวดไหนปลดเกิน ~1.67% ของ supply (ไม่มีวันปลดก้อนใหญ่)", async function () {
        let prev = 0n;
        for (let m = 1; m <= 61; m++) {
            const v = await vesting.vestedAmount(at(m));
            expect(v - prev).to.be.lte(TOTAL_SUPPLY / 60n + 1n);
            prev = v;
        }
    });

    it("ใครกด release ก็ได้ แต่เหรียญไปที่ beneficiary เท่านั้น", async function () {
        await token.transfer(vesting.target, 770n * B);
        await time.increaseTo(at(14));
        await expect(vesting.connect(anyone).release()).to.emit(vesting, "Released");
        expect(await token.balanceOf(anyone.address)).to.equal(0n);
        expect(await token.balanceOf(beneficiary.address)).to.equal(((220n * B) * 2n) / 12n);
        await expect(vesting.release()).to.be.revertedWithCustomError(vesting, "NothingToRelease");
    });

    it("ปลดครบเดือน 60 แล้วเหลือ 0 และไม่มีงวดถัดไป", async function () {
        await token.transfer(vesting.target, 770n * B);
        await time.increaseTo(at(60));
        await vesting.release();
        expect(await token.balanceOf(beneficiary.address)).to.equal(770n * B);
        expect(await vesting.lockedAmount()).to.equal(0n);
        const [nextAt, amount] = await vesting.nextUnlock();
        expect(nextAt).to.equal(0n);
        expect(amount).to.equal(0n);
    });

    it("nextUnlock บอกงวดแรก = เดือน 13 และจำนวนของงวดนั้น", async function () {
        const [nextAt, amount] = await vesting.nextUnlock();
        expect(nextAt).to.equal(at(13));
        expect(amount).to.equal((220n * B) / 12n);
    });

    it("beneficiary ย้ายได้แบบสองขั้น (เช่น ไป multisig) คนอื่นสั่งไม่ได้", async function () {
        await expect(vesting.connect(anyone).transferBeneficiary(anyone.address))
            .to.be.revertedWithCustomError(vesting, "NotBeneficiary");
        await vesting.connect(beneficiary).transferBeneficiary(anyone.address);
        expect(await vesting.beneficiary()).to.equal(beneficiary.address);
        await expect(vesting.connect(owner).acceptBeneficiary())
            .to.be.revertedWithCustomError(vesting, "NotPendingBeneficiary");
        await vesting.connect(anyone).acceptBeneficiary();
        expect(await vesting.beneficiary()).to.equal(anyone.address);
    });

    it("sweepExcess คืนเฉพาะส่วนที่ส่งเกิน ไม่แตะยอดที่ต้องล็อก", async function () {
        await token.transfer(vesting.target, 770n * B);
        await expect(vesting.connect(beneficiary).sweepExcess(token.target))
            .to.be.revertedWithCustomError(vesting, "NoExcess");
        await token.transfer(vesting.target, 5n * E18);
        await vesting.connect(beneficiary).sweepExcess(token.target);
        expect(await token.balanceOf(beneficiary.address)).to.equal(5n * E18);
        expect(await vesting.isFunded()).to.equal(true);
        await expect(vesting.connect(anyone).sweepExcess(token.target))
            .to.be.revertedWithCustomError(vesting, "NotBeneficiary");
    });

    it("ปฏิเสธตารางที่ผิด", async function () {
        const V = await ethers.getContractFactory("TrancheVesting");
        await expect(V.deploy(token.target, beneficiary.address, start, MONTH, [], "x"))
            .to.be.revertedWithCustomError(V, "BadSchedule");
        await expect(V.deploy(token.target, beneficiary.address, start, MONTH,
            [{ amount: 0, cliffPeriods: 1, releasePeriods: 1 }], "x")).to.be.revertedWithCustomError(V, "BadSchedule");
        await expect(V.deploy(token.target, beneficiary.address, start, MONTH,
            [{ amount: 1, cliffPeriods: 1, releasePeriods: 0 }], "x")).to.be.revertedWithCustomError(V, "BadSchedule");
        await expect(V.deploy(token.target, beneficiary.address, start, 0,
            [{ amount: 1, cliffPeriods: 1, releasePeriods: 1 }], "x")).to.be.revertedWithCustomError(V, "BadSchedule");
        await expect(V.deploy(token.target, ethers.ZeroAddress, start, MONTH,
            [{ amount: 1, cliffPeriods: 1, releasePeriods: 1 }], "x")).to.be.revertedWithCustomError(V, "ZeroAddress");
    });
});

describe("Launch tools — FixedPriceSale (IDTC presale $0.0000015)", function () {
    let owner, treasury, buyer, buyer2, idtc, usdt, sale, startTime, endTime;
    const SALE_CAP = 100n * B;

    beforeEach(async function () {
        [owner, treasury, buyer, buyer2] = await ethers.getSigners();
        idtc = await deployToken(owner.address);
        usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        await usdt.setBridge(owner.address, true);
        await usdt.bridgeMint(buyer.address, 1_000_000n * USDT, ethers.id("t1"));
        await usdt.bridgeMint(buyer2.address, 1_000_000n * USDT, ethers.id("t2"));

        startTime = BigInt(await time.latest()) + 100n;
        endTime = startTime + 30n * 86400n;
        const S = await ethers.getContractFactory("FixedPriceSale");
        // 1 หน่วยเล็กสุดของ USDT (1e-6) = 2/3 IDTC → num 2e18, den 3
        sale = await S.deploy(idtc.target, usdt.target, 2n * E18, 3n, SALE_CAP, treasury.address,
            startTime, endTime, owner.address);
        await idtc.transfer(sale.target, SALE_CAP);
        await usdt.connect(buyer).approve(sale.target, ethers.MaxUint256);
        await usdt.connect(buyer2).approve(sale.target, ethers.MaxUint256);
    });

    it("ราคาตรงกับ $0.0000015: 1 USDT = 666,666.66… IDTC", async function () {
        expect(await sale.quote(1n * USDT)).to.equal(666_666_666_666_666_666_666_666n);
        expect(await sale.quote(15n * USDT / 10n)).to.equal(1_000_000n * E18); // 1.5 USDT = 1M IDTC
    });

    it("ยังไม่ถึงเวลา / หมดเวลา ซื้อไม่ได้", async function () {
        await expect(sale.connect(buyer).buy(USDT)).to.be.revertedWithCustomError(sale, "NotActive");
        await time.increaseTo(endTime);
        await expect(sale.connect(buyer).buy(USDT)).to.be.revertedWithCustomError(sale, "NotActive");
    });

    it("ซื้อแล้วได้เหรียญทันที และเงินเข้า treasury ตรง ๆ สัญญาไม่ถือเงิน", async function () {
        await time.increaseTo(startTime);
        await expect(sale.connect(buyer).buy(150n * USDT))
            .to.emit(sale, "Purchased").withArgs(buyer.address, 150n * USDT, 100_000_000n * E18);
        expect(await idtc.balanceOf(buyer.address)).to.equal(100_000_000n * E18);
        expect(await usdt.balanceOf(treasury.address)).to.equal(150n * USDT);
        expect(await usdt.balanceOf(sale.target)).to.equal(0n);
        expect(await sale.sold()).to.equal(100_000_000n * E18);
        expect(await sale.raised()).to.equal(150n * USDT);
    });

    it("เพดานรวม · เพดานต่อกระเป๋า · ขั้นต่ำ", async function () {
        await time.increaseTo(startTime);
        await sale.setLimits(10n * USDT, 1_000_000_000n * E18);
        await expect(sale.connect(buyer).buy(5n * USDT)).to.be.revertedWithCustomError(sale, "BelowMinimum");
        await sale.connect(buyer).buy(1_500n * USDT);                       // 1B พอดี
        await expect(sale.connect(buyer).buy(10n * USDT)).to.be.revertedWithCustomError(sale, "WalletLimitExceeded");

        await sale.setLimits(0, 0);
        await expect(sale.connect(buyer2).buy(150_000n * USDT)).to.be.revertedWithCustomError(sale, "CapExceeded");
    });

    it("หยุดชั่วคราวแล้วซื้อไม่ได้ · ราคาไม่มีทางแก้ (ไม่มี setter)", async function () {
        await time.increaseTo(startTime);
        await sale.pause();
        await expect(sale.connect(buyer).buy(USDT)).to.be.revertedWithCustomError(sale, "EnforcedPause");
        await sale.unpause();
        await expect(sale.connect(buyer).buy(USDT)).to.not.be.reverted;
        expect(sale.interface.getFunction("setRate")).to.equal(null);
    });

    it("ถอนเหรียญที่เหลือได้เฉพาะหลังปิดรอบหรือขณะหยุด · คนอื่นสั่งไม่ได้", async function () {
        await time.increaseTo(startTime);
        await expect(sale.withdrawUnsold(owner.address)).to.be.revertedWithCustomError(sale, "SaleNotOver");
        await expect(sale.connect(buyer).withdrawUnsold(buyer.address)).to.be.revertedWithCustomError(sale, "OwnableUnauthorizedAccount");
        await time.increaseTo(endTime);
        await sale.withdrawUnsold(owner.address);
        expect(await idtc.balanceOf(sale.target)).to.equal(0n);
    });

    it("ปฏิเสธค่าตั้งต้นที่ผิด", async function () {
        const S = await ethers.getContractFactory("FixedPriceSale");
        await expect(S.deploy(idtc.target, idtc.target, 1, 1, 1, treasury.address, 1, 2, owner.address))
            .to.be.revertedWithCustomError(S, "BadConfig");
        await expect(S.deploy(idtc.target, usdt.target, 0, 1, 1, treasury.address, 1, 2, owner.address))
            .to.be.revertedWithCustomError(S, "BadConfig");
        await expect(S.deploy(idtc.target, usdt.target, 1, 1, 1, treasury.address, 5, 5, owner.address))
            .to.be.revertedWithCustomError(S, "BadConfig");
        await expect(S.deploy(idtc.target, usdt.target, 1, 1, 1, ethers.ZeroAddress, 1, 2, owner.address))
            .to.be.revertedWithCustomError(S, "ZeroAddress");
    });
});
