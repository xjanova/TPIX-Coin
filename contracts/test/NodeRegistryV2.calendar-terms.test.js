const { expect } = require('chai');
const { ethers, network } = require('hardhat');
const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');

const YEAR = 365n * 86400n;
const E18 = 10n ** 18n;
async function fixture() {
    const [owner, alice, bob] = await ethers.getSigners();
    for (const s of [owner, alice, bob]) await network.provider.send('hardhat_setBalance', [s.address, ethers.toBeHex(10n**36n)]);
    const r = await (await ethers.getContractFactory('NodeRegistryV2')).deploy();
    await r.setRegistrationPaused(false);
    return { r, owner, alice, bob, start: await r.rewardStartTime() };
}
async function join(r, who, value = 10000n*E18) {
    const rc = await (await r.connect(who).registerNode(2, 'node.example:30301', 7, 0, ethers.MaxUint256, { value })).wait();
    return BigInt((await ethers.provider.getBlock(rc.blockNumber)).timestamp);
}

describe('NodeRegistryV2 — calendar schedule and signed registration limits', function () {
    it('starts paused and accepts stake only after the owner opens registration', async function () {
        const [, alice] = await ethers.getSigners();
        await network.provider.send('hardhat_setBalance', [alice.address, ethers.toBeHex(10n**36n)]);
        const r = await (await ethers.getContractFactory('NodeRegistryV2')).deploy();
        expect(await r.registrationPaused()).to.equal(true);
        await expect(join(r, alice)).to.be.revertedWith('Registration paused');
        await expect(r.connect(alice).setRegistrationPaused(false)).to.be.reverted;
        await r.setRegistrationPaused(false);
        await join(r, alice);
        expect(await r.totalStaked()).to.equal(10000n*E18);
    });
    it('stops at three years without a keeper; late catch-up cannot add a fourth year', async function () {
        const {r, alice, start} = await loadFixture(fixture);
        const joined = await join(r, alice);
        await time.increaseTo(start + 4n*YEAR);
        const rate = 10000n*E18*600n*E18/(10000n*YEAR);
        const expected = rate*(start+3n*YEAR-joined)/E18;
        expect(await r.pendingReward(alice.address)).to.equal(expected);
        expect(await r.currentYear()).to.equal(3);
        expect(await r.currentRewardPerSecond()).to.equal(0);
        expect((await r.getNetworkStats())[5]).to.equal(3);
        expect(await r.nodeRewardRate(2)).to.deep.equal([0n, 0n]);
        await r.advanceRewardYear();
        expect(await r.pendingReward(alice.address)).to.equal(expected);
        await r.fundRewardPool({value: 2000n*E18});
        await r.connect(alice).claimRewards();
        expect((await r.getNodeInfo(alice.address)).totalRewards).to.equal(expected);
        await r.connect(alice).deregisterNode();
        expect(await r.totalStaked()).to.equal(0);
    });

    it('integrates the three different emission rates when emission, rather than APR, is limiting', async function () {
        const {r, alice, start} = await loadFixture(fixture);
        const stake = 10n**12n*E18;
        await r.updateTierConfig(2, stake, 0, 7, 0, 1500);
        const joined = await join(r, alice, stake);
        for (const offset of [YEAR-1n, YEAR, YEAR+1n, 2n*YEAR+1n, 3n*YEAR, 7n*YEAR]) {
            await time.increaseTo(start+offset);
            let expected = 0n;
            const emissions = [600000000n,500000000n,300000000n];
            for (let y=0;y<3;y++) {
                const lo = joined > start+BigInt(y)*YEAR ? joined : start+BigInt(y)*YEAR;
                const hi = start+offset < start+BigInt(y+1)*YEAR ? start+offset : start+BigInt(y+1)*YEAR;
                if (hi>lo) expected += ((emissions[y]*E18/YEAR)*1500n/10000n)*(hi-lo);
            }
            expect(await r.pendingReward(alice.address)).to.equal(expected);
        }
    });

    it('settles old APR before a late owner change, preserving the schedule end', async function () {
        const {r, alice, start} = await loadFixture(fixture);
        await join(r, alice);
        await time.increaseTo(start+4n*YEAR);
        const before = await r.pendingReward(alice.address);
        await r.setTierAprCap(2, 5000);
        await time.increase(YEAR);
        expect(await r.pendingReward(alice.address)).to.equal(before);
    });

    it('a newcomer after the schedule ends accrues no rewards', async function () {
        const {r, alice, start} = await loadFixture(fixture);
        await time.increaseTo(start+4n*YEAR);
        await join(r, alice);
        await time.increase(YEAR);
        expect(await r.pendingReward(alice.address)).to.equal(0);
        await r.connect(alice).deregisterNode();
    });

    it('rejects a lock increase inserted before the signed registration', async function () {
        const {r, alice} = await loadFixture(fixture);
        await r.updateTierConfig(2, 10000n*E18, 0, 180, 0, 1500);
        await expect(join(r, alice)).to.be.revertedWith('Lock terms changed');
        expect(await r.totalStaked()).to.equal(0);
    });

    it('rejects a slash increase inserted before the signed registration', async function () {
        const {r, alice} = await loadFixture(fixture);
        await r.updateTierConfig(2, 10000n*E18, 0, 7, 1500, 1500);
        await expect(join(r, alice)).to.be.revertedWith('Slash terms changed');
    });

    it('accepts improved terms, records them, and rejects expired signatures', async function () {
        const {r, alice, bob} = await loadFixture(fixture);
        const deadline = BigInt(await time.latest())+100n;
        await r.updateTierConfig(2, 10000n*E18, 0, 1, 0, 1500);
        await r.connect(alice).registerNode(2,'node.example:30301',7,0,deadline,{value:10000n*E18});
        const n=await r.getNodeInfo(alice.address);
        expect(n.unlockAt-n.registeredAt).to.equal(86400);
        await time.increaseTo(deadline+1n);
        await expect(r.connect(bob).registerNode(2,'node.example:30301',7,0,deadline,{value:10000n*E18})).to.be.revertedWith('Registration expired');
    });

    it('does not expose the old unprotected selector', async function () {
        const {r,alice}=await loadFixture(fixture);
        const legacy=new ethers.Interface(['function registerNode(uint8,string) payable']);
        await expect(alice.sendTransaction({to:await r.getAddress(),data:legacy.encodeFunctionData('registerNode',[2,'node.example:30301']),value:10000n*E18})).to.be.reverted;
    });
});
