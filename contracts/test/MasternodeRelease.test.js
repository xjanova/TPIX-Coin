const { expect } = require('chai');
const { ethers } = require('hardhat');
const { loadFixture, setBalance } = require('@nomicfoundation/hardhat-network-helpers');
const { stage } = require('../scripts/stage-masternode-release');

async function fixture() {
    const [signer, alice] = await ethers.getSigners();
    await setBalance(alice.address, ethers.parseEther('1000000'));
    const old = [];
    for (let i = 0; i < 2; i++) {
        const r = await (await ethers.getContractFactory('NodeRegistryV2')).deploy();
        await r.setRegistrationPaused(false);
        old.push(r);
    }
    const k = await (await ethers.getContractFactory('ValidatorKYC')).deploy(ethers.id('test consent'));
    return { signer, alice, old, oldAddresses: await Promise.all(old.map(r => r.getAddress())), kycAddress: await k.getAddress() };
}

describe('Masternode staged release', function () {
    it('pauses both empty predecessors, reuses KYC and leaves the new contract closed and unfunded', async function () {
        const ctx = await loadFixture(fixture);
        const out = await stage(ctx);
        for (const r of ctx.old) expect(await r.registrationPaused()).to.equal(true);
        const r = await ethers.getContractAt('NodeRegistryV2', out.address);
        expect(await r.registrationPaused()).to.equal(true);
        expect(await r.kycContract()).to.equal(ctx.kycAddress);
        expect(await r.owner()).to.equal(ctx.signer.address);
        expect(await r.totalStaked()).to.equal(0);
        expect(await r.availableRewardFunds()).to.equal(0);
        expect(await r.uptimeOracle()).to.equal(ethers.ZeroAddress);
        expect(out.discoveryPublished).to.equal(false);
    });
    it('rejects a different build before changing previous registries', async function () {
        const ctx = await loadFixture(fixture);
        await expect(stage({ ...ctx, expectedHash: ethers.ZeroHash })).to.be.rejectedWith('Build hash mismatch');
        for (const r of ctx.old) expect(await r.registrationPaused()).to.equal(false);
    });
    it('refuses automatic migration if a previous registry has an operator or funded pool', async function () {
        const ctx = await loadFixture(fixture);
        await ctx.old[1].connect(ctx.alice).registerNode(2, 'node.example:30303', 7, 0, ethers.MaxUint256, { value: ethers.parseEther('10000') });
        await expect(stage(ctx)).to.be.rejectedWith('explicit migration');
        expect(await ctx.old[0].registrationPaused()).to.equal(false);
    });
    it('rejects an unavailable KYC contract before any pause', async function () {
        const ctx = await loadFixture(fixture);
        await expect(stage({ ...ctx, kycAddress: ctx.alice.address })).to.be.rejectedWith('KYC has no code');
        for (const r of ctx.old) expect(await r.registrationPaused()).to.equal(false);
    });
});
