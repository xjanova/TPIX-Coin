/**
 * Pre-deploy audit of the IDTC launch (2026-10-11) — the cases LaunchTools.test.js does not cover.
 *
 *   1. FixedPriceSale math fuzz: 1 micro-USDT … the whole 100B inventory, against a BigInt model
 *      (buyer gets floor(pay × num ÷ den), treasury gets exactly pay, a revert moves nothing)
 *   2. TrancheVesting at every period boundary (−1 s / 0 / +1 s) against a reference model,
 *      release at every instant, under-/over-/late funding, tokens sent by mistake
 *   3. End-to-end launch on the local network: factory → operator → IDTC (standard) → lock + presale
 *      → buys → every unlock — and the factory/operator keep no power over the token
 */
const { expect } = require("chai");
const { ethers, artifacts } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const { deployTokenFactory } = require("./helpers/deployTokenFactory");

const E18 = 10n ** 18n;
const B = 1_000_000_000n * E18;
const TOTAL_SUPPLY = 1_100n * B;
const MONTH = 2_629_800n;
const USDT = 10n ** 6n;
const NUM = 2n * E18;            // tokens (wei) per micro-USDT = 2e18 / 3
const DEN = 3n;
const SALE_CAP = 100n * B;

const IDTC_TRANCHES = [
    { amount: 220n * B, cliffPeriods: 12, releasePeriods: 12 },
    { amount: 220n * B, cliffPeriods: 24, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 36, releasePeriods: 12 },
    { amount: 165n * B, cliffPeriods: 48, releasePeriods: 12 },
];
const LOCKED = 770n * B;

/** "standard" exactly as ThaiXTrade create-token.cjs maps it: no mint, no burn, no pause, no blacklist, no auto-burn */
const STANDARD = [false, false, false, false, 0, false, 0, 0];

async function deployStandardToken(owner, supply = TOTAL_SUPPLY) {
    const T = await ethers.getContractFactory("FactoryERC20V2");
    return T.deploy("Invest Energy-Development Coin", "IDTC", 18, supply, owner, ...STANDARD);
}

/** deterministic PRNG (xorshift64*) so a failing fuzz case can be replayed */
function prng(seed) {
    let s = BigInt(seed) & 0xffffffffffffffffn;
    return () => {
        s ^= s >> 12n; s ^= (s << 25n) & 0xffffffffffffffffn; s ^= s >> 27n;
        return (s * 0x2545f4914f6cdd1dn) & 0xffffffffffffffffn;
    };
}

/** reference model of TrancheVesting.vestedAmount */
function modelVested(start, period, tranches, ts) {
    let total = 0n;
    for (const t of tranches) {
        const cliffEnd = start + BigInt(t.cliffPeriods) * period;
        if (ts <= cliffEnd) continue;
        const elapsed = (ts - cliffEnd) / period;
        total += elapsed >= BigInt(t.releasePeriods) ? t.amount : (t.amount * elapsed) / BigInt(t.releasePeriods);
    }
    return total;
}

describe("Launch audit — FixedPriceSale math fuzz (IDTC $0.0000015)", function () {
    let owner, treasury, buyers, idtc, usdt, sale, startTime, endTime;

    beforeEach(async function () {
        const s = await ethers.getSigners();
        [owner, treasury] = s;
        buyers = s.slice(2, 6);
        idtc = await deployStandardToken(owner.address);
        usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        await usdt.setBridge(owner.address, true);
        for (const [i, b] of buyers.entries()) {
            await usdt.bridgeMint(b.address, 200_000n * USDT, ethers.id(`fuzz-${i}`));
        }
        startTime = BigInt(await time.latest()) + 100n;
        endTime = startTime + 30n * 86400n;
        sale = await (await ethers.getContractFactory("FixedPriceSale")).deploy(
            idtc.target, usdt.target, NUM, DEN, SALE_CAP, treasury.address, startTime, endTime, owner.address);
        await idtc.transfer(sale.target, SALE_CAP);
        for (const b of buyers) await usdt.connect(b).approve(sale.target, ethers.MaxUint256);
        await time.increaseTo(startTime);
    });

    async function snapshot(buyer) {
        return {
            buyerUsdt: await usdt.balanceOf(buyer.address),
            buyerIdtc: await idtc.balanceOf(buyer.address),
            treasuryUsdt: await usdt.balanceOf(treasury.address),
            saleIdtc: await idtc.balanceOf(sale.target),
            saleUsdt: await usdt.balanceOf(sale.target),
            sold: await sale.sold(),
            raised: await sale.raised(),
        };
    }

    async function expectNothingMoved(buyer, before) {
        const after = await snapshot(buyer);
        expect(after).to.deep.equal(before);
    }

    it("smallest purchases round down by < 1 wei of IDTC and never up", async function () {
        const b = buyers[0];
        for (const [pay, out] of [
            [1n, 666_666_666_666_666_666n],
            [2n, 1_333_333_333_333_333_333n],
            [3n, 2n * E18],
            [USDT, 666_666_666_666_666_666_666_666n],
        ]) {
            expect(await sale.quote(pay)).to.equal(out);
            const before = await snapshot(b);
            await expect(sale.connect(b).buy(pay)).to.emit(sale, "Purchased").withArgs(b.address, pay, out);
            const after = await snapshot(b);
            expect(after.buyerIdtc - before.buyerIdtc).to.equal(out);
            expect(before.buyerUsdt - after.buyerUsdt).to.equal(pay);
            expect(after.treasuryUsdt - before.treasuryUsdt).to.equal(pay);
            // value check: tokens × price never exceeds what was paid (buyer is never over-credited)
            expect(out * DEN).to.be.lte(pay * NUM);
            expect((out + 1n) * DEN).to.be.gt(pay * NUM);
        }
    });

    it("fuzz: 300 random purchase sizes (log-uniform 1 micro-USDT … 150,000 USDT) match the model exactly", async function () {
        this.timeout(300_000);
        const rnd = prng(0x1D7C2026n);
        const MAX_PAY = 150_000n * USDT;
        let sold = 0n, raised = 0n, reverts = 0, buys = 0;
        for (let i = 0; i < 300; i++) {
            const b = buyers[i % buyers.length];
            const digits = Number(rnd() % 12n);                     // 10^0 … 10^11 micro-USDT
            let pay = (rnd() % (10n ** BigInt(digits + 1))) + 1n;
            if (pay > MAX_PAY) pay = MAX_PAY;
            if (i % 50 === 49) pay = SALE_CAP;                      // absurdly large: must revert cleanly
            const out = (pay * NUM) / DEN;
            const before = await snapshot(b);
            if (sold + out > SALE_CAP) {
                await expect(sale.connect(b).buy(pay)).to.be.revertedWithCustomError(sale, "CapExceeded");
                await expectNothingMoved(b, before);
                reverts++;
                continue;
            }
            if (before.buyerUsdt < pay) {
                await expect(sale.connect(b).buy(pay)).to.be.reverted;
                await expectNothingMoved(b, before);
                reverts++;
                continue;
            }
            await sale.connect(b).buy(pay);
            sold += out; raised += pay; buys++;
            const after = await snapshot(b);
            expect(after.buyerIdtc - before.buyerIdtc).to.equal(out);
            expect(before.buyerUsdt - after.buyerUsdt).to.equal(pay);
            expect(after.treasuryUsdt - before.treasuryUsdt).to.equal(pay);
            expect(after.saleUsdt).to.equal(0n);                     // the sale never holds USDT
            expect(after.saleIdtc).to.equal(SALE_CAP - sold);       // inventory == cap − sold, no drift
        }
        expect(await sale.sold()).to.equal(sold);
        expect(await sale.raised()).to.equal(raised);
        expect(buys).to.be.gt(50);
        expect(reverts).to.be.gt(0);
        console.log(`        fuzz: ${buys} buys, ${reverts} clean reverts, sold ${ethers.formatUnits(sold, 18)} IDTC for ${ethers.formatUnits(raised, 6)} USDT`);
    });

    it("the whole inventory in one purchase (150,000 USDT = exactly 100B IDTC); one more micro-USDT reverts", async function () {
        const b = buyers[0];
        expect(await sale.quote(150_000n * USDT)).to.equal(SALE_CAP);
        let before = await snapshot(b);
        await expect(sale.connect(b).buy(150_000n * USDT + 1n)).to.be.revertedWithCustomError(sale, "CapExceeded");
        await expectNothingMoved(b, before);

        await sale.connect(b).buy(150_000n * USDT);
        expect(await sale.sold()).to.equal(SALE_CAP);
        expect(await sale.remaining()).to.equal(0n);
        expect(await idtc.balanceOf(sale.target)).to.equal(0n);
        expect(await sale.isActive()).to.equal(false);
        before = await snapshot(buyers[1]);
        await expect(sale.connect(buyers[1]).buy(1n)).to.be.revertedWithCustomError(sale, "CapExceeded");
        await expectNothingMoved(buyers[1], before);
    });

    it("the site's 'max' amount (maxPayFor(remaining)) sells out to < 0.67 IDTC of dust, recoverable after the end", async function () {
        const maxPayFor = (t) => ((t + 1n) * DEN - 1n) / NUM;     // presale.js
        // leave an awkward remainder first
        await sale.connect(buyers[0]).buy(12_345_678_901n);
        const remaining = await sale.remaining();
        const pay = maxPayFor(remaining);
        await sale.connect(buyers[1]).buy(pay);
        const dust = await sale.remaining();
        expect(dust).to.be.lt(666_666_666_666_666_667n);
        expect(await sale.quote(pay + 1n)).to.be.gt(remaining);   // one more micro-USDT would not fit
        // nothing else fits (unless the dust is exactly one micro-USDT's worth)
        if (dust < 666_666_666_666_666_666n) {
            await expect(sale.connect(buyers[2]).buy(1n)).to.be.revertedWithCustomError(sale, "CapExceeded");
        }
        await time.increaseTo(endTime);
        await sale.withdrawUnsold(owner.address);
        expect(await idtc.balanceOf(sale.target)).to.equal(0n);
        expect(await idtc.balanceOf(owner.address)).to.equal(TOTAL_SUPPLY - SALE_CAP + dust);
    });

    it("multiplication overflow and zero output revert without moving anything", async function () {
        const b = buyers[0];
        const before = await snapshot(b);
        await expect(sale.connect(b).buy(2n ** 255n)).to.be.revertedWithPanic(0x11);
        await expect(sale.connect(b).buy(0n)).to.be.revertedWithCustomError(sale, "ZeroOutput");
        await expectNothingMoved(b, before);
    });

    it("inventory short of the cap: a purchase it cannot fill reverts — USDT is never taken without delivery", async function () {
        const thin = await (await ethers.getContractFactory("FixedPriceSale")).deploy(
            idtc.target, usdt.target, NUM, DEN, SALE_CAP, treasury.address, startTime, endTime, owner.address);
        await idtc.transfer(thin.target, 1_000_000n * E18);            // 1M IDTC = 1.5 USDT worth
        const b = buyers[0];
        await usdt.connect(b).approve(thin.target, ethers.MaxUint256);
        const before = { usdt: await usdt.balanceOf(b.address), tre: await usdt.balanceOf(treasury.address) };
        await expect(thin.connect(b).buy(3n * USDT)).to.be.revertedWithCustomError(idtc, "ERC20InsufficientBalance");
        expect(await usdt.balanceOf(b.address)).to.equal(before.usdt);
        expect(await usdt.balanceOf(treasury.address)).to.equal(before.tre);
        expect(await thin.sold()).to.equal(0n);
        await thin.connect(b).buy(15n * USDT / 10n);                    // exactly the stock
        expect(await idtc.balanceOf(thin.target)).to.equal(0n);
    });

    it("no allowance / paused USDT_TPIX: reverts, nothing moves", async function () {
        const b = buyers[0];
        await usdt.connect(b).approve(sale.target, 0);
        let before = await snapshot(b);
        await expect(sale.connect(b).buy(USDT)).to.be.revertedWithCustomError(usdt, "ERC20InsufficientAllowance");
        await expectNothingMoved(b, before);
        await usdt.connect(b).approve(sale.target, ethers.MaxUint256);
        await usdt.pause();                                               // USDT_TPIX owner (bridge operator) can do this
        before = await snapshot(b);
        await expect(sale.connect(b).buy(USDT)).to.be.revertedWithCustomError(usdt, "EnforcedPause");
        await expectNothingMoved(b, before);
    });

    it("owner can pause + withdraw the inventory at any time (documented trust assumption), buyers keep what they bought", async function () {
        await sale.connect(buyers[0]).buy(USDT);
        await sale.pause();
        await sale.withdrawUnsold(owner.address);
        await sale.unpause();
        const before = await snapshot(buyers[1]);
        await expect(sale.connect(buyers[1]).buy(USDT)).to.be.revertedWithCustomError(idtc, "ERC20InsufficientBalance");
        await expectNothingMoved(buyers[1], before);
        expect(await idtc.balanceOf(buyers[0].address)).to.equal(666_666_666_666_666_666_666_666n);
    });

    it("tokens sent to the sale by mistake (USDT transferred directly) can be returned by the owner — never the sale token", async function () {
        const b = buyers[0];
        await usdt.connect(b).transfer(sale.target, 25n * USDT);         // a classic user mistake
        await expect(sale.connect(b).recoverToken(usdt.target, b.address))
            .to.be.revertedWithCustomError(sale, "OwnableUnauthorizedAccount");
        await expect(sale.recoverToken(idtc.target, owner.address))
            .to.be.revertedWithCustomError(sale, "SaleTokenUseWithdrawUnsold");
        await expect(sale.recoverToken(usdt.target, ethers.ZeroAddress))
            .to.be.revertedWithCustomError(sale, "ZeroAddress");
        await expect(sale.recoverToken(usdt.target, b.address))
            .to.emit(sale, "TokenRecovered").withArgs(usdt.target, b.address, 25n * USDT);
        expect(await usdt.balanceOf(sale.target)).to.equal(0n);
        expect(await usdt.balanceOf(b.address)).to.equal(200_000n * USDT);
        await expect(sale.recoverToken(usdt.target, b.address)).to.be.revertedWithCustomError(sale, "NothingToRecover");
        // the sale inventory is untouched
        expect(await idtc.balanceOf(sale.target)).to.equal(SALE_CAP);
    });
});

describe("Launch audit — TrancheVesting boundaries and funding", function () {
    let owner, beneficiary, anyone, token, vesting, start;
    const at = (m, extra = 0n) => start + BigInt(m) * MONTH + extra;

    beforeEach(async function () {
        [owner, beneficiary, anyone] = await ethers.getSigners();
        token = await deployStandardToken(owner.address);
        start = BigInt(await time.latest()) + 1000n;
        vesting = await (await ethers.getContractFactory("TrancheVesting")).deploy(
            token.target, beneficiary.address, start, MONTH, IDTC_TRANCHES, "IDTC — lock 70%");
    });

    it("vestedAmount matches the reference model at every boundary −1 s / 0 / +1 s (months 0 … 62)", async function () {
        for (let m = 0; m <= 62; m++) {
            for (const d of [-1n, 0n, 1n]) {
                const ts = at(m, d);
                expect(await vesting.vestedAmount(ts), `month ${m} ${d}s`).to.equal(modelVested(start, MONTH, IDTC_TRANCHES, ts));
            }
        }
        expect(await vesting.vestedAmount(at(13) - 1n)).to.equal(0n);       // first unlock is at month 13, not before
        expect(await vesting.vestedAmount(at(60))).to.equal(LOCKED);
        expect(await vesting.vestedAmount(at(60) - 1n)).to.equal(LOCKED - (165n * B - (165n * B * 11n) / 12n));
    });

    it("release at every instant (months 13 … 60): 48 releases sum to exactly 770B, no dust left", async function () {
        await token.transfer(vesting.target, LOCKED);
        let paid = 0n;
        for (let m = 13; m <= 60; m++) {
            const [nextAt, nextAmt] = await vesting.nextUnlock();
            expect(nextAt).to.equal(at(m));
            const expected = modelVested(start, MONTH, IDTC_TRANCHES, at(m)) - paid;
            expect(nextAmt).to.equal(expected);
            // one second before the instant there is nothing new (off-by-one guard)
            await time.setNextBlockTimestamp(at(m) - 1n);
            await expect(vesting.connect(anyone).release()).to.be.revertedWithCustomError(vesting, "NothingToRelease");
            await time.setNextBlockTimestamp(at(m));
            await expect(vesting.connect(anyone).release()).to.emit(vesting, "Released").withArgs(beneficiary.address, expected);
            paid += expected;
            expect(await vesting.released()).to.equal(paid);
        }
        expect(paid).to.equal(LOCKED);
        expect(await token.balanceOf(vesting.target)).to.equal(0n);
        expect(await token.balanceOf(beneficiary.address)).to.equal(LOCKED);
        expect(await vesting.nextUnlock()).to.deep.equal([0n, 0n]);
        await expect(vesting.release()).to.be.revertedWithCustomError(vesting, "NothingToRelease");
    });

    it("jittered releases (random seconds inside each month) still sum to exactly 770B", async function () {
        await token.transfer(vesting.target, LOCKED);
        const rnd = prng(42n);
        for (let m = 12; m <= 61; m++) {
            await time.setNextBlockTimestamp(at(m, rnd() % MONTH));
            try { await vesting.release(); } catch (e) { expect(e.message).to.match(/NothingToRelease/); }
        }
        expect(await vesting.released()).to.equal(LOCKED);
        expect(await token.balanceOf(beneficiary.address)).to.equal(LOCKED);
    });

    it("unfunded: release reverts and nothing is recorded; funded late it catches up in one go", async function () {
        await time.increaseTo(at(30));
        await expect(vesting.release()).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
        expect(await vesting.released()).to.equal(0n);
        expect(await vesting.isFunded()).to.equal(false);
        await token.transfer(vesting.target, LOCKED);
        await time.setNextBlockTimestamp(at(30, 5n));
        await vesting.release();
        expect(await vesting.released()).to.equal(modelVested(start, MONTH, IDTC_TRANCHES, at(30, 5n)));
    });

    it("under-funded by 1 wei: isFunded=false; the last unlock reverts until topped up — earlier unlocks are unaffected", async function () {
        await token.transfer(vesting.target, LOCKED - 1n);
        expect(await vesting.isFunded()).to.equal(false);
        await time.increaseTo(at(59));
        await vesting.release();
        await time.increaseTo(at(60));
        await expect(vesting.release()).to.be.revertedWithCustomError(token, "ERC20InsufficientBalance");
        await token.transfer(vesting.target, 1n);
        await vesting.release();
        expect(await token.balanceOf(beneficiary.address)).to.equal(LOCKED);
    });

    it("over-funded: sweepExcess returns only the surplus, before and after partial releases", async function () {
        await token.transfer(vesting.target, LOCKED + 7n * E18);
        await vesting.connect(beneficiary).sweepExcess(token.target);
        expect(await token.balanceOf(beneficiary.address)).to.equal(7n * E18);
        await time.increaseTo(at(20));
        await vesting.release();
        await expect(vesting.connect(beneficiary).sweepExcess(token.target)).to.be.revertedWithCustomError(vesting, "NoExcess");
        expect(await vesting.isFunded()).to.equal(true);
        expect(await token.balanceOf(vesting.target)).to.equal(LOCKED - (await vesting.released()));
    });

    it("another token sent by mistake goes back to the beneficiary only", async function () {
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        await usdt.setBridge(owner.address, true);
        await usdt.bridgeMint(vesting.target, 9n * USDT, ethers.id("oops"));
        await expect(vesting.connect(anyone).sweepExcess(usdt.target)).to.be.revertedWithCustomError(vesting, "NotBeneficiary");
        await expect(vesting.connect(beneficiary).sweepExcess(usdt.target))
            .to.emit(vesting, "ExcessSwept").withArgs(usdt.target, beneficiary.address, 9n * USDT);
    });

    it("beneficiary handover: pending can be replaced, the old beneficiary loses everything after accept", async function () {
        await token.transfer(vesting.target, LOCKED);
        await vesting.connect(beneficiary).transferBeneficiary(owner.address);
        await vesting.connect(beneficiary).transferBeneficiary(anyone.address);        // overwrite the pending one
        await expect(vesting.connect(owner).acceptBeneficiary()).to.be.revertedWithCustomError(vesting, "NotPendingBeneficiary");
        await expect(vesting.connect(anyone).acceptBeneficiary())
            .to.emit(vesting, "BeneficiaryTransferred").withArgs(beneficiary.address, anyone.address);
        expect(await vesting.pendingBeneficiary()).to.equal(ethers.ZeroAddress);
        await expect(vesting.connect(beneficiary).transferBeneficiary(beneficiary.address))
            .to.be.revertedWithCustomError(vesting, "NotBeneficiary");
        await time.increaseTo(at(13));
        await vesting.connect(beneficiary).release();                                   // anyone may call …
        expect(await token.balanceOf(anyone.address)).to.equal((220n * B) / 12n);       // … it pays the new beneficiary
        expect(await token.balanceOf(beneficiary.address)).to.equal(0n);
    });
});

describe("Launch audit — end-to-end IDTC launch on the local network", function () {
    it("factory (operator-owned) → IDTC standard → lock 770B + presale 100B → buys → all unlocks; no one keeps power over IDTC", async function () {
        this.timeout(120_000);
        const [deployer, operator, project, multisig, treasury, buyer] = await ethers.getSigners();

        // ── 1. factory as deploy-token-factory.js leaves it: creators bound, ownership → FACTORY_OPERATOR ──
        const { creators, tokenFactory } = await deployTokenFactory();
        await tokenFactory.transferOwnership(operator.address);
        expect(await tokenFactory.owner()).to.equal(operator.address);
        await expect(tokenFactory.connect(project).createERC20V2("X", "X", 18, 1, project.address, ...STANDARD))
            .to.be.revertedWithCustomError(tokenFactory, "OwnableUnauthorizedAccount");

        // ── 2. the operator creates IDTC for the project wallet with ThaiXTrade's "standard" mapping ──
        const tx = await tokenFactory.connect(operator).createERC20V2(
            "Invest Energy-Development Coin", "IDTC", 18, TOTAL_SUPPLY, project.address, ...STANDARD);
        const rc = await tx.wait();
        const ev = rc.logs.map((l) => { try { return tokenFactory.interface.parseLog(l); } catch { return null; } })
            .find((l) => l && l.name === "TokenCreated");
        const idtc = await ethers.getContractAt("FactoryERC20V2", ev.args.tokenAddress);
        expect(ev.args.tokenOwner).to.equal(project.address);

        // the token is the audited FactoryERC20V2 code, all supply with the project, owner = project
        const art = await artifacts.readArtifact("FactoryERC20V2");
        expect((await ethers.provider.getCode(idtc.target)).length).to.equal(art.deployedBytecode.length);
        expect(await idtc.owner()).to.equal(project.address);
        expect(await idtc.totalSupply()).to.equal(TOTAL_SUPPLY);
        expect(await idtc.balanceOf(project.address)).to.equal(TOTAL_SUPPLY);
        for (const a of [operator.address, deployer.address, tokenFactory.target, creators.ERC20V2Creator.target]) {
            expect(await idtc.balanceOf(a)).to.equal(0n);
        }
        expect([await idtc.isMintable(), await idtc.isBurnable(), await idtc.isPausable(),
            await idtc.isBlacklistEnabled(), await idtc.isAutoBurnEnabled()]).to.deep.equal([false, false, false, false, false]);
        // even the owner cannot mint / pause / blacklist / burn
        await expect(idtc.connect(project).mint(project.address, 1n)).to.be.revertedWith("V2: minting disabled");
        await expect(idtc.connect(project).pause()).to.be.revertedWith("V2: not pausable");
        await expect(idtc.connect(project).setBlacklist(buyer.address, true)).to.be.revertedWith("V2: blacklist disabled");
        await expect(idtc.connect(project).burn(1n)).to.be.revertedWith("V2: burning disabled");
        // the operator / factory deployer have no role on the token at all
        await expect(idtc.connect(operator).transferOwnership(operator.address))
            .to.be.revertedWithCustomError(idtc, "OwnableUnauthorizedAccount");
        // the factory's only state-changing functions create new tokens — no back door into an existing one
        const mutators = (iface) => iface.fragments
            .filter((f) => f.type === "function" && f.stateMutability !== "view" && f.stateMutability !== "pure")
            .map((f) => f.format());
        expect(mutators(creators.ERC20V2Creator.interface).sort()).to.deep.equal([
            "bindFactory(address)",
            "create(bytes32,string,string,uint8,uint256,address,bool,bool,bool,bool,uint256,bool,uint16,uint256)",
        ]);
        expect(mutators(tokenFactory.interface).sort()).to.deep.equal([
            "createERC20V2(string,string,uint8,uint256,address,bool,bool,bool,bool,uint256,bool,uint16,uint256)",
            "createGovernanceToken(string,string,uint8,uint256,address,bool,bool,bool,bool,bool,uint256,uint256,uint16,uint256)",
            "createRewardToken(string,string,uint8,uint256,address,bool,bool,bool,bool,uint8,uint16,uint256,uint256,uint256)",
            "createStablecoinToken(string,string,uint8,uint256,address,address,bool,bool,bool)",
            "createUtilityToken(string,string,uint8,uint256,address,bool,bool,bool,bool,(uint16,uint16,uint16,address,address,uint16),(uint16,uint16,uint256,uint256))",
            "renounceOwnership()",
            "transferOwnership(address)",
        ].sort());

        // ── 3. launch contracts with the plan's numbers (scripts/launch-plans/idtc.json) ──
        const plan = require("../scripts/launch-plans/idtc.json");
        const tranches = plan.vesting.tranches.map((t) => ({
            amount: ethers.parseUnits(t.amount, 18), cliffPeriods: t.cliffPeriods, releasePeriods: t.releasePeriods,
        }));
        expect(tranches.reduce((a, t) => a + t.amount, 0n)).to.equal((TOTAL_SUPPLY * 70n) / 100n);
        expect(BigInt(plan.vesting.periodSeconds)).to.equal(MONTH);
        const start = BigInt(await time.latest()) + 86400n;
        const usdt = await (await ethers.getContractFactory("USDT_TPIX")).deploy();
        const vesting = await (await ethers.getContractFactory("TrancheVesting"))
            .deploy(idtc.target, multisig.address, start, MONTH, tranches, plan.vesting.label);
        const saleStart = BigInt(await time.latest()) + 60n;
        const sale = await (await ethers.getContractFactory("FixedPriceSale")).deploy(
            idtc.target, usdt.target, NUM, DEN, SALE_CAP, treasury.address, saleStart, saleStart + 30n * 86400n, multisig.address);
        // price check: $0.0000015 per IDTC ⇔ 1 USDT buys 666,666.666… IDTC
        expect(await sale.quote(15n * USDT)).to.equal(10_000_000n * E18);

        // ── 4. the project funds both from its own wallet ──
        await idtc.connect(project).transfer(vesting.target, LOCKED);
        await idtc.connect(project).transfer(sale.target, SALE_CAP);
        expect(await vesting.isFunded()).to.equal(true);
        expect(await idtc.balanceOf(project.address)).to.equal(230n * B);   // 30% circulating − presale stock

        // ── 5. a buyer buys ──
        await usdt.setBridge(deployer.address, true);
        await usdt.bridgeMint(buyer.address, 1_000n * USDT, ethers.id("e2e"));
        await usdt.connect(buyer).approve(sale.target, 1_000n * USDT);
        await time.increaseTo(saleStart);
        await sale.connect(buyer).buy(1_000n * USDT);
        expect(await idtc.balanceOf(buyer.address)).to.equal((1_000n * USDT * NUM) / DEN);
        expect(await usdt.balanceOf(treasury.address)).to.equal(1_000n * USDT);

        // ── 6. every unlock reaches the multisig and the lock ends empty ──
        for (let m = 13; m <= 60; m++) {
            await time.setNextBlockTimestamp(start + BigInt(m) * MONTH);
            await vesting.connect(buyer).release();
        }
        expect(await idtc.balanceOf(multisig.address)).to.equal(LOCKED);
        expect(await idtc.balanceOf(vesting.target)).to.equal(0n);
        expect(await idtc.totalSupply()).to.equal(TOTAL_SUPPLY);
    });
});
