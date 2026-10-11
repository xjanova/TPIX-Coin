/**
 * อ่าน/เติม reward pool ของ NodeRegistryV2 — ใช้ร่วมกันระหว่าง fund-reward-pool.js กับเทสต์
 *
 * แยกออกมาเป็นฟังก์ชันที่รับ provider/signer จากข้างนอก เพื่อให้เทสต์ใน hardhat
 * เรียกเส้นทางเดียวกับของจริงได้ (ของจริงใช้ JsonRpcProvider + กุญแจจาก keystore)
 *
 * ⚠️ ห้ามเติมพูลด้วยการโอนธรรมดา 21,000 gas (send-tpix.ps1) — receive() ของสัญญา
 *    เขียน storage + ยิง event ใช้แก๊สราว 30,000 → tx ล้มเพราะแก๊สหมด
 *    ต้องเรียก fundRewardPool() พร้อม gas limit ที่ประเมินจากเชน
 */
const { ethers } = require("ethers");

const YEAR = 365n * 24n * 60n * 60n;
const TIER_NAMES = ["Guardian", "Sentinel", "Light", "Validator"];

const REGISTRY_ABI = [
    "function fundRewardPool() payable",
    "function rewardPoolStatus() view returns (uint256 fundedBalance, uint256 totalFunded, uint256 distributed, uint256 scheduleCap)",
    "function getTierInfo(uint8) view returns (tuple(uint256 minStake, uint256 maxNodes, uint256 activeNodes, uint256 lockDays, uint256 slashPercent, uint256 rewardShare))",
    "function tierAprCapBps(uint8) view returns (uint256)",
    "function nodeRewardRate(uint8) view returns (uint256 currentPerNode, uint256 ifOneMoreJoins)",
    "function registrationPaused() view returns (bool)",
    "function totalStaked() view returns (uint256)",
    "function owner() view returns (address)",
];

/**
 * ตรวจว่าที่อยู่นี้คือ NodeRegistryV2 รุ่นที่ผ่านการตรวจ (มีเพดาน APR) บนเชนที่ถูกต้อง
 * แล้วคืนสถานะพูล + อัตราจ่ายรางวัลต่อปีตอนนี้ (ใช้คำนวณว่าเงินที่เติมพอกี่วัน)
 */
async function inspectRegistry(provider, address, expectedChainId = 4289) {
    // ถาม eth_chainId จาก RPC ตรง ๆ — fund-reward-pool.js ใช้ staticNetwork ซึ่งทำให้
    // getNetwork() ตอบเลขที่เราตั้งเองโดยไม่ถาม RPC เลย (ด่านนี้จะผ่านเสมอ)
    const chainId = Number(BigInt(await provider.send("eth_chainId", [])));
    if (chainId !== expectedChainId) {
        throw new Error(`RPC ตอบ chainId ${chainId} ไม่ใช่ ${expectedChainId}`);
    }
    if (!ethers.isAddress(address)) throw new Error(`ที่อยู่สัญญาไม่ถูกต้อง: ${address}`);

    // polygon-edge 0.9 ตอบ error "unable to fetch code" (ไม่ใช่ "0x") เมื่อที่อยู่เป็นบัญชีธรรมดา
    // ที่มียอด/nonce — ยืนยันสดกับ rpc1 2026-10-11 → นับเป็น "ไม่มีโค้ด" เหมือนกัน
    let code;
    try {
        code = await provider.getCode(address);
    } catch (e) {
        const msg = `${e?.message || ""} ${JSON.stringify(e?.error || e?.info || {})}`;
        if (/unable to fetch code|could not coalesce/i.test(msg)) code = "0x";
        else throw e;
    }
    if (!code || code === "0x") throw new Error(`ไม่มีสัญญาอยู่ที่ ${address} (eth_getCode = 0x)`);

    const c = new ethers.Contract(address, REGISTRY_ABI, provider);

    // tierAprCapBps มีเฉพาะรุ่นที่ผ่านการตรวจ 2026-10 — รุ่นเก่าจ่ายรางวัลไม่จำกัด ห้ามเติมเงินให้
    let aprCaps;
    try {
        aprCaps = await Promise.all([0, 1, 2, 3].map((t) => c.tierAprCapBps(t)));
    } catch {
        throw new Error(
            `${address} ไม่มี tierAprCapBps() — ไม่ใช่ NodeRegistryV2 รุ่นที่มีเพดาน APR ห้ามเติมเงินเข้าสัญญานี้`
        );
    }

    const [pool, paused, owner] = await Promise.all([
        c.rewardPoolStatus(),
        c.registrationPaused(),
        c.owner(),
    ]);

    // อัตราจ่ายต่อปีตอนนี้ = Σ (wei/วินาที ต่อโหนด × จำนวนโหนด) × 1 ปี (คิดที่ uptime 100%)
    const tiers = [];
    let annualOutflowWei = 0n;
    for (let t = 0; t < 4; t++) {
        const [info, rate] = await Promise.all([c.getTierInfo(t), c.nodeRewardRate(t)]);
        const perYear = rate.currentPerNode * info.activeNodes * YEAR;
        annualOutflowWei += perYear;
        tiers.push({
            tier: t,
            name: TIER_NAMES[t],
            activeNodes: Number(info.activeNodes),
            minStakeWei: info.minStake,
            aprCapBps: Number(aprCaps[t]),
            perYearWei: perYear,
        });
    }

    return {
        chainId,
        address: ethers.getAddress(address),
        owner,
        paused,
        fundedBalanceWei: pool.fundedBalance,
        totalFundedWei: pool.totalFunded,
        distributedWei: pool.distributed,
        scheduleCapWei: pool.scheduleCap,
        annualOutflowWei,
        tiers,
    };
}

/** เงินในพูลพอจ่ายกี่วันที่อัตราตอนนี้ (null = ยังไม่มีใคร stake อัตราเป็นศูนย์) */
function runwayDays(fundedWei, annualOutflowWei) {
    if (annualOutflowWei === 0n) return null;
    return Number((fundedWei * 365n * 100n) / annualOutflowWei) / 100;
}

/**
 * เรียก fundRewardPool() — ประเมินแก๊สจากเชนจริง +30% แทนการเดา
 * dryRun = ประเมินแก๊สอย่างเดียว ไม่ส่ง
 */
async function fundPool(signer, address, amountWei, { dryRun = false, gasPrice } = {}) {
    if (amountWei <= 0n) throw new Error("จำนวนต้องมากกว่า 0");
    const c = new ethers.Contract(address, REGISTRY_ABI, signer);

    const est = await c.fundRewardPool.estimateGas({ value: amountWei });
    const gasLimit = (est * 13n) / 10n + 10000n;
    if (dryRun) return { dryRun: true, gasEstimate: est, gasLimit };

    const price = gasPrice ?? BigInt(await signer.provider.send("eth_gasPrice", []));
    const tx = await c.fundRewardPool({ value: amountWei, gasLimit, gasPrice: price, type: 0 });
    const receipt = await tx.wait(1, 120_000);
    if (!receipt || receipt.status !== 1) throw new Error(`ธุรกรรมไม่สำเร็จ (tx ${tx.hash})`);
    return { dryRun: false, txHash: tx.hash, blockNumber: receipt.blockNumber, gasUsed: receipt.gasUsed, gasLimit };
}

module.exports = { inspectRegistry, runwayDays, fundPool, REGISTRY_ABI, TIER_NAMES };
