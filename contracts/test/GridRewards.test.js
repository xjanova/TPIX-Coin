/**
 * GridRewards — จ่ายรางวัล IDTC Grid เป็นรอบด้วย Merkle root
 *
 * ต้นไม้: leaf = keccak256(keccak256(abi.encode(contract, round, account, amount)))
 *         คู่ = keccak256(เรียงน้อยไปมาก(a, b)) · ชั้นที่เหลือตัวเดียว ยกขึ้นชั้นถัดไปเลย (แบบเดียวกับ idtc.online GridMerkle)
 */
const fs = require("fs");
const path = require("path");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const E18 = 10n ** 18n;
const coder = ethers.AbiCoder.defaultAbiCoder();

function leafOf(contract, round, account, amount) {
    const inner = ethers.keccak256(coder.encode(["address", "uint256", "address", "uint256"], [contract, round, account, amount]));
    return ethers.keccak256(inner);
}

const hashPair = (a, b) => (BigInt(a) < BigInt(b) ? ethers.keccak256(ethers.concat([a, b])) : ethers.keccak256(ethers.concat([b, a])));

/** @returns {{root: string, proof: (i: number) => string[]}} */
function tree(leaves) {
    const layers = [leaves.slice()];
    while (layers[layers.length - 1].length > 1) {
        const cur = layers[layers.length - 1];
        const next = [];
        for (let i = 0; i < cur.length; i += 2) next.push(i + 1 < cur.length ? hashPair(cur[i], cur[i + 1]) : cur[i]);
        layers.push(next);
    }
    return {
        root: layers[layers.length - 1][0],
        proof(index) {
            const out = [];
            let i = index;
            for (let l = 0; l < layers.length - 1; l++) {
                const sib = i ^ 1;
                if (sib < layers[l].length) out.push(layers[l][sib]);
                i >>= 1;
            }
            return out;
        },
    };
}

async function deployToken(owner) {
    const T = await ethers.getContractFactory("FactoryERC20V2");
    return T.deploy("Invest Energy-Development Coin", "IDTC", 18, 1_100_000_000_000n * E18, owner, false, true, false, false, 0, false, 0, 0);
}

describe("GridRewards — รอบจ่ายรางวัล IDTC Grid", function () {
    let owner, a, b, c, stranger, token, rewards, addr;

    const round = (id, entries) => {
        const leaves = entries.map(([acc, amt]) => leafOf(addr, id, acc, amt));
        const t = tree(leaves);
        return { root: t.root, total: entries.reduce((s, [, amt]) => s + amt, 0n), proof: (i) => t.proof(i), leaves };
    };

    beforeEach(async function () {
        [owner, a, b, c, stranger] = await ethers.getSigners();
        token = await deployToken(owner.address);
        const R = await ethers.getContractFactory("GridRewards");
        rewards = await R.deploy(await token.getAddress(), owner.address);
        addr = await rewards.getAddress();
    });

    it("pays each account its amount once, from a funded round", async function () {
        const r = round(0, [[a.address, 1000n * E18], [b.address, 250n * E18], [c.address, 1n]]);
        await token.transfer(addr, r.total);
        await expect(rewards.addRound(0, r.root, r.total, 0)).to.emit(rewards, "RoundAdded").withArgs(0, r.root, r.total, 0);
        expect(await rewards.outstanding()).to.equal(r.total);

        // ใครกดแทนก็ได้ แต่เหรียญเข้ากระเป๋าในรายชื่อ
        await expect(rewards.connect(stranger).claim(0, a.address, 1000n * E18, r.proof(0)))
            .to.emit(rewards, "Claimed").withArgs(0, a.address, 1000n * E18);
        expect(await token.balanceOf(a.address)).to.equal(1000n * E18);
        expect(await token.balanceOf(stranger.address)).to.equal(0n);

        await expect(rewards.claim(0, a.address, 1000n * E18, r.proof(0))).to.be.revertedWithCustomError(rewards, "AlreadyClaimed");
        await rewards.claim(0, c.address, 1n, r.proof(2));
        expect(await rewards.outstanding()).to.equal(250n * E18);
        expect((await rewards.rounds(0)).claimed).to.equal(1000n * E18 + 1n);
    });

    it("rejects a wrong amount, a wrong account and a proof from another round", async function () {
        const r0 = round(0, [[a.address, 10n], [b.address, 20n]]);
        const r1 = round(1, [[a.address, 10n], [b.address, 20n]]);
        await token.transfer(addr, 30n + 30n);
        await rewards.addRound(0, r0.root, 30n, 0);
        await rewards.addRound(1, r1.root, 30n, 0);

        await expect(rewards.claim(0, a.address, 11n, r0.proof(0))).to.be.revertedWithCustomError(rewards, "InvalidProof");
        await expect(rewards.claim(0, c.address, 10n, r0.proof(0))).to.be.revertedWithCustomError(rewards, "InvalidProof");
        // รายชื่อเหมือนกันทุกอย่าง แต่ leaf ผูกเลขรอบ → proof ของรอบ 0 ใช้กับรอบ 1 ไม่ได้
        await expect(rewards.claim(1, a.address, 10n, r0.proof(0))).to.be.revertedWithCustomError(rewards, "InvalidProof");
        await rewards.claim(1, a.address, 10n, r1.proof(0));
    });

    it("refuses an underfunded round and a stale round id", async function () {
        const r = round(0, [[a.address, 100n]]);
        await token.transfer(addr, 99n);
        await expect(rewards.addRound(0, r.root, 100n, 0)).to.be.revertedWithCustomError(rewards, "Underfunded");
        await token.transfer(addr, 1n);
        await expect(rewards.addRound(1, r.root, 100n, 0)).to.be.revertedWithCustomError(rewards, "WrongRoundId");
        await rewards.addRound(0, r.root, 100n, 0);

        // รอบที่สองต้องมีเหรียญพอทั้งรอบเก่าที่ยังค้าง + รอบใหม่
        const r1 = round(1, [[b.address, 50n]]);
        await token.transfer(addr, 49n);
        await expect(rewards.addRound(1, r1.root, 50n, 0)).to.be.revertedWithCustomError(rewards, "Underfunded");
        await expect(rewards.addRound(0, r1.root, 0n, 0)).to.be.revertedWithCustomError(rewards, "WrongRoundId");
        await expect(rewards.addRound(1, ethers.ZeroHash, 50n, 0)).to.be.revertedWithCustomError(rewards, "EmptyRound");
    });

    it("waits for unlockAt", async function () {
        const r = round(0, [[a.address, 5n]]);
        await token.transfer(addr, 5n);
        const at = BigInt(await time.latest()) + 3600n;
        await rewards.addRound(0, r.root, 5n, at);
        await expect(rewards.claim(0, a.address, 5n, r.proof(0))).to.be.revertedWithCustomError(rewards, "NotUnlocked");
        await time.increaseTo(at);
        await rewards.claim(0, a.address, 5n, r.proof(0));
    });

    it("never lets one round's bad list drain another round", async function () {
        // รายชื่อผิด: ใบเดียวเกินยอดรวมของรอบ
        const bad = round(0, [[a.address, 1000n]]);
        const good = round(1, [[b.address, 1000n]]);
        await token.transfer(addr, 1010n);
        await rewards.addRound(0, bad.root, 10n, 0);
        await rewards.addRound(1, good.root, 1000n, 0);
        await expect(rewards.claim(0, a.address, 1000n, bad.proof(0))).to.be.revertedWithCustomError(rewards, "AmountTooLarge");
        await rewards.claim(1, b.address, 1000n, good.proof(0));
    });

    it("lets the owner revoke a round, pause claims and withdraw only the excess", async function () {
        const r = round(0, [[a.address, 70n], [b.address, 30n]]);
        await token.transfer(addr, 150n);
        await rewards.addRound(0, r.root, 100n, 0);
        expect(await rewards.excess()).to.equal(50n);
        await expect(rewards.withdrawExcess(owner.address, 51n)).to.be.revertedWithCustomError(rewards, "ExceedsExcess");
        await expect(rewards.connect(stranger).withdrawExcess(stranger.address, 1n)).to.be.revertedWithCustomError(rewards, "OwnableUnauthorizedAccount");
        await expect(rewards.connect(stranger).addRound(1, r.root, 1n, 0)).to.be.revertedWithCustomError(rewards, "OwnableUnauthorizedAccount");

        await rewards.pause();
        await expect(rewards.claim(0, a.address, 70n, r.proof(0))).to.be.revertedWithCustomError(rewards, "EnforcedPause");
        await rewards.unpause();
        await rewards.claim(0, a.address, 70n, r.proof(0));

        await expect(rewards.revokeRound(0)).to.emit(rewards, "RoundRevoked").withArgs(0, 30n);
        await expect(rewards.claim(0, b.address, 30n, r.proof(1))).to.be.revertedWithCustomError(rewards, "RoundRevokedError");
        expect(await rewards.outstanding()).to.equal(0n);
        expect(await rewards.excess()).to.equal(80n);
        await rewards.withdrawExcess(owner.address, 80n);
        await expect(rewards.revokeRound(0)).to.be.revertedWithCustomError(rewards, "RoundRevokedError");
    });

    it("claims several rounds in one transaction", async function () {
        const r0 = round(0, [[a.address, 3n], [b.address, 4n]]);
        const r1 = round(1, [[b.address, 9n], [a.address, 5n], [c.address, 6n]]);
        await token.transfer(addr, 27n);
        await rewards.addRound(0, r0.root, 7n, 0);
        await rewards.addRound(1, r1.root, 20n, 0);
        await rewards.claimMany([0, 1], a.address, [3n, 5n], [r0.proof(0), r1.proof(1)]);
        expect(await token.balanceOf(a.address)).to.equal(8n);
        await expect(rewards.claimMany([0], a.address, [3n, 1n], [r0.proof(0)])).to.be.revertedWithCustomError(rewards, "LengthMismatch");
    });

    it("works with odd-sized lists (a lone node moves up a level)", async function () {
        const entries = Array.from({ length: 7 }, (_, i) => [ethers.Wallet.createRandom().address, BigInt(i + 1)]);
        const r = round(0, entries);
        await token.transfer(addr, r.total);
        await rewards.addRound(0, r.root, r.total, 0);
        for (let i = 0; i < entries.length; i++) {
            expect(await rewards.verify(0, entries[i][0], entries[i][1], r.proof(i))).to.equal(true);
            await rewards.claim(0, entries[i][0], entries[i][1], r.proof(i));
        }
        expect(await rewards.outstanding()).to.equal(0n);
    });

    // รายชื่อ/ราก/proof ที่สร้างโดย idtc.online (PHP: App\Services\Grid\GridMerkle) ต้องรับได้จริงบนสัญญา
    it("accepts the round built by idtc.online (cross-implementation vectors)", async function () {
        const file = path.join(__dirname, "fixtures", "grid-rewards-php.json");
        const fx = JSON.parse(fs.readFileSync(file, "utf8"));
        // deploy จากกุญแจทดสอบตายตัว nonce 0 → ได้ที่อยู่สัญญาเดียวกับที่ PHP ใช้สร้าง leaf
        const deployer = new ethers.Wallet(fx.deployer_key, ethers.provider);
        await ethers.provider.send("hardhat_setBalance", [deployer.address, "0x56BC75E2D63100000"]);
        expect(await ethers.provider.getTransactionCount(deployer.address)).to.equal(0);
        const R = await ethers.getContractFactory("GridRewards", deployer);
        const deployed = await R.deploy(await token.getAddress(), owner.address);
        expect((await deployed.getAddress()).toLowerCase()).to.equal(fx.contract.toLowerCase());
        const fixed = deployed.connect(owner);

        // เลขรอบอยู่ใน leaf → ต้องประกาศรอบก่อนหน้าให้ครบก่อน (รอบละ 1 หน่วย)
        await token.transfer(await fixed.getAddress(), BigInt(fx.total) + BigInt(fx.round));
        for (let i = 0; i < fx.round; i++) await fixed.addRound(i, ethers.id(`filler-${i}`), 1n, 0);
        await fixed.addRound(fx.round, fx.root, BigInt(fx.total), 0);
        for (const item of fx.items) {
            await fixed.claim(fx.round, item.wallet, BigInt(item.amount), item.proof);
            expect(await token.balanceOf(item.wallet)).to.equal(BigInt(item.amount));
        }
        expect(await fixed.outstanding()).to.equal(BigInt(fx.round));
    });
});
