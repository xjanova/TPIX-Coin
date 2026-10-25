/** Stage the reviewed registry; never publish discovery, fund, or open registration.
 * Rehearsal: npx hardhat run scripts/stage-masternode-release.js
 * Mainnet: DEPLOYER_KEY in the local process, then add --network tpix.
 * Keep the key out of command arguments, files, and chat.
 */
const fs = require('fs');
const path = require('path');
const hre = require('hardhat');
const release = require('../masternode-release-hash.json');

async function stage({ signer, oldAddresses, kycAddress, expectedHash = release.runtimeCodeHash }) {
    const { ethers, artifacts } = hre;
    const provider = signer.provider;
    if ((await provider.getNetwork()).chainId !== 4289n) throw new Error('Wrong chain');
    if (!oldAddresses.length) throw new Error('Previous registries required');
    const artifact = await artifacts.readArtifact('NodeRegistryV2');
    if (ethers.keccak256(artifact.deployedBytecode) !== expectedHash) throw new Error('Build hash mismatch');
    const owner = await signer.getAddress();
    const old = oldAddresses.map(a => new ethers.Contract(a, artifact.abi, signer));
    const requireEmpty = async r => {
        const [count, stake, active, funded, distributed] = await Promise.all([
            r.getOperatorCount(), r.totalStaked(), r.totalActiveNodes(), r.totalRewardFunded(), r.totalRewardsDistributed(),
        ]);
        if ([count, stake, active, funded, distributed].some(v => v !== 0n) ||
            await provider.getBalance(await r.getAddress()) !== 0n) {
            throw new Error('Previous registry has history or funds; an explicit migration is required');
        }
    };
    // Validate everything before the first write. A pause keeps exits/claims available.
    for (const r of old) {
        if ((await r.owner()).toLowerCase() !== owner.toLowerCase()) throw new Error('Previous registry owner mismatch');
        await requireEmpty(r);
    }
    if (await provider.getCode(kycAddress) === '0x') throw new Error('KYC has no code');
    const kyc = new ethers.Contract(kycAddress, ['function owner() view returns(address)'], provider);
    if ((await kyc.owner()).toLowerCase() !== owner.toLowerCase()) throw new Error('KYC owner mismatch');
    const transactions = [];
    for (const r of old) {
        if (!await r.registrationPaused()) {
            const tx = await r.setRegistrationPaused(true, { gasPrice: 0 });
            await tx.wait(); transactions.push({ action: 'pause previous registry', to: await r.getAddress(), hash: tx.hash });
        }
        // Catch registrations/funding mined between inspection and the pause.
        await requireEmpty(r);
    }
    const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, signer);
    const registry = await factory.deploy({ gasPrice: 0 });
    await registry.waitForDeployment();
    const address = await registry.getAddress();
    transactions.push({ action: 'deploy paused registry', to: address, hash: registry.deploymentTransaction().hash });
    if (ethers.keccak256(await provider.getCode(address)) !== expectedHash || !await registry.registrationPaused()) {
        throw new Error('Deployment verification failed; do not publish');
    }
    const tx = await registry.setKYCContract(kycAddress, { gasPrice: 0 });
    await tx.wait(); transactions.push({ action: 'reuse existing KYC', to: address, hash: tx.hash });
    if ((await registry.kycContract()).toLowerCase() !== kycAddress.toLowerCase()) throw new Error('KYC verification failed');
    return { chainId: 4289, address, owner, kycAddress, previousRegistries: oldAddresses,
        runtimeCodeHash: expectedHash, registrationPaused: true, discoveryPublished: false,
        rewardPoolFunded: false, uptimeOracleActivated: false, transactions };
}

async function main() {
    const { ethers, network } = hre;
    const [signer] = await ethers.getSigners();
    if (!signer) throw new Error('Owner signer required in DEPLOYER_KEY; never paste it into chat');
    const rehearsal = network.name === 'hardhat';
    let oldAddresses, kycAddress;
    if (rehearsal) {
        oldAddresses = [];
        for (let i = 0; i < 2; i++) {
            const r = await (await ethers.getContractFactory('NodeRegistryV2')).deploy();
            await r.setRegistrationPaused(false);
            oldAddresses.push(await r.getAddress());
        }
        const k = await (await ethers.getContractFactory('ValidatorKYC')).deploy(ethers.id('rehearsal consent'));
        kycAddress = await k.getAddress();
    } else {
        if (network.name !== 'tpix') throw new Error('Only hardhat rehearsal or tpix is supported');
        const deployed = require('../deployed-contracts.json');
        oldAddresses = [...deployed.contracts, ...(deployed.retired || [])]
            .filter(c => c.name === 'NodeRegistryV2').map(c => c.address);
        // Include the historical registry even if a metadata schema renamed the retired collection.
        const historical = '0x9c3662972921705FeFa9E9bF0d91190d7B514A2B';
        if (!oldAddresses.some(a => a.toLowerCase() === historical.toLowerCase())) oldAddresses.push(historical);
        kycAddress = deployed.contracts.find(c => c.name === 'ValidatorKYC').address;
    }
    const result = await stage({ signer, oldAddresses, kycAddress });
    console.log(JSON.stringify(result, null, 2));
    if (!rehearsal) {
        const out = path.join(__dirname, '..', `masternode-staged-${result.address}.json`);
        fs.writeFileSync(out, JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
        console.log(`Staged only. Manifest: ${out}. Follow docs/MASTERNODE-RELEASE.md before opening registration.`);
    }
}
if (require.main === module) main().catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { stage };
