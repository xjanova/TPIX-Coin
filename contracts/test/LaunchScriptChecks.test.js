/**
 * scripts/lib/launch-checks.js — the guards launch-token.js runs before it touches anything on the real chain
 *
 * Rehearsal that found these (local node, real --network path, 2026-10-11):
 *   1st run  BENEFICIARY=A VESTING_START=d1 SALE_TREASURY=T SALE_OWNER=A  → deploys lock + presale
 *   2nd run  BENEFICIARY=B VESTING_START=d2 SALE_TREASURY=B SALE_OWNER=B  → printed B / d2, said "มีอยู่แล้ว — ใช้ของเดิม",
 *            and told the owner to send 770B into the lock that still pays A from d1
 */
const { expect } = require("chai");
const { ethers, artifacts } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const checks = require("../scripts/lib/launch-checks");

const E18 = 10n ** 18n;
const B = 1_000_000_000n * E18;
const MONTH = 2_629_800n;
const TRANCHES = [
    { amount: 220n * B, cliffPeriods: 12, releasePeriods: 12 },
    { amount: 220n * B, cliffPeriods: 24, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 36, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 48, releasePeriods: 12 },
];
const STANDARD = [false, false, false, false, 0, false, 0, 0];

describe("launch-token.js guards (scripts/lib/launch-checks.js)", function () {
    let owner, a, b, treasury, token, usdt;

    beforeEach(async function () {
        [owner, a, b, treasury] = await ethers.getSigners();
        const T = await ethers.getContractFactory("FactoryERC20V2");
        token = await T.deploy("Invest Energy-Development Coin", "IDTC", 18, 1_100n * B, owner.address, ...STANDARD);
        usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
    });

    describe("an existing lock is reused only if every constructor value matches", function () {
        let vesting, start;
        beforeEach(async function () {
            start = BigInt(await time.latest()) + 86400n;
            vesting = await (await ethers.getContractFactory("TrancheVesting"))
                .deploy(token.target, a.address, start, MONTH, TRANCHES, "IDTC — lock");
        });
        const expected = (over = {}) => ({ token: null, beneficiary: null, start: null, period: MONTH, tranches: TRANCHES, label: "IDTC — lock", ...over });

        it("identical → no mismatch", async function () {
            expect(await checks.vestingMismatches(vesting, expected({ token: token.target, beneficiary: a.address, start }))).to.deep.equal([]);
        });

        it("different beneficiary / start / period / tranche / label / token → each one is named", async function () {
            const m = await checks.vestingMismatches(vesting, expected({
                token: usdt.target, beneficiary: b.address, start: start + 1n, period: MONTH + 1n, label: "other",
                tranches: [...TRANCHES.slice(0, 3), { amount: 165n * B, cliffPeriods: 47, releasePeriods: 12 }],
            }));
            const text = m.join("\n");
            for (const k of ["token", "beneficiary", "start", "period", "tranche 3", "label"]) expect(text).to.contain(k);
        });

        it("a different tranche count is caught", async function () {
            const m = await checks.vestingMismatches(vesting, expected({ token: token.target, beneficiary: a.address, start, tranches: TRANCHES.slice(0, 3) }));
            expect(m.join("\n")).to.contain("tranche count");
        });
    });

    describe("an existing presale is reused only if every value matches", function () {
        let sale, s0;
        beforeEach(async function () {
            s0 = BigInt(await time.latest()) + 600n;
            sale = await (await ethers.getContractFactory("FixedPriceSale")).deploy(
                token.target, usdt.target, 2n * E18, 3n, 100n * B, treasury.address, s0, s0 + 86400n, a.address);
        });
        const exp = (over = {}) => ({ saleToken: null, payToken: null, num: 2n * E18, den: 3n, cap: 100n * B, treasury: null, start: null, end: null, owner: null, ...over });

        it("identical → no mismatch", async function () {
            expect(await checks.saleMismatches(sale, exp({ saleToken: token.target, payToken: usdt.target, treasury: treasury.address, start: s0, end: s0 + 86400n, owner: a.address }))).to.deep.equal([]);
        });

        it("treasury / owner / window / cap / rate / tokens that differ are each named", async function () {
            const m = (await checks.saleMismatches(sale, exp({
                saleToken: usdt.target, payToken: token.target, num: 1n, den: 1n, cap: 1n,
                treasury: b.address, start: s0 + 1n, end: s0 + 2n, owner: b.address,
            }))).join("\n");
            for (const k of ["saleToken", "payToken", "rate", "saleCap", "treasury", "startTime", "endTime", "owner"]) expect(m).to.contain(k);
        });
    });

    describe("the token must be the audited FactoryERC20V2 'standard' build", function () {
        it("standard token from this build → no problem", async function () {
            expect(await checks.tokenProblems(token, { artifacts, provider: ethers.provider })).to.deep.equal([]);
        });

        it("pausable / blacklist / mintable / auto-burn are refused, not just printed in red", async function () {
            const T = await ethers.getContractFactory("FactoryERC20V2");
            const bad = await T.deploy("I", "IDTC", 18, 1n, owner.address, true, false, true, true, 0, true, 10, 0);
            const p = (await checks.tokenProblems(bad, { artifacts, provider: ethers.provider })).join("\n");
            for (const k of ["mint", "pause", "blacklist", "auto-burn"]) expect(p).to.contain(k);
        });

        it("a token whose code is not FactoryERC20V2 (e.g. the legacy V1 FactoryERC20 or anything else) is refused", async function () {
            const V1 = await ethers.getContractFactory("FactoryERC20");
            const v1 = await V1.deploy("I", "IDTC", 18, 1n, owner.address, false, false);
            const p = (await checks.tokenProblems(v1, { artifacts, provider: ethers.provider })).join("\n");
            expect(p).to.contain("FactoryERC20V2");
        });
    });
});
