/**
 * เปิดคลังสะพาน TPIX ↔ wTPIX ให้รับล็อก/ปล่อยเงิน (unpause) — รันเมื่อฝั่งเว็บพร้อมแล้วเท่านั้น
 *
 * Usage:
 *   export DEPLOYER_KEY=0x...                      # เจ้าของคลัง
 *   export WTPIX_BRIDGE_VAULT_ADDRESS=0x...        # ที่อยู่ TPIXBridgeVault
 *   npx hardhat run scripts/unpause-bridge-vault.js --network tpix
 *
 * ตรวจก่อนเปิด: เจ้าของตรง · มี relayer อย่างน้อยหนึ่งตัวที่ระบุไว้ (RELAYER_ADDRESS)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");

async function main() {
    const [owner] = await hre.ethers.getSigners();
    if (!owner) throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน");

    const address = (process.env.WTPIX_BRIDGE_VAULT_ADDRESS || "").trim();
    if (!/^0x[0-9a-fA-F]{40}$/.test(address)) throw new Error("ตั้ง WTPIX_BRIDGE_VAULT_ADDRESS เป็นที่อยู่คลังก่อน");

    const vault = await hre.ethers.getContractAt("TPIXBridgeVault", address, owner);
    const vaultOwner = await vault.owner();
    if (vaultOwner.toLowerCase() !== owner.address.toLowerCase()) {
        throw new Error(`คลังเป็นของ ${vaultOwner} ไม่ใช่กระเป๋านี้ (${owner.address})`);
    }

    const relayer = (process.env.RELAYER_ADDRESS || "").trim();
    if (relayer && !(await vault.relayers(relayer))) {
        throw new Error(`${relayer} ยังไม่เป็น relayer ของคลัง — เปิดไปก็ไม่มีใครปล่อยเงินคืนได้`);
    }

    if (!(await vault.paused())) {
        console.log("คลังเปิดอยู่แล้ว — ไม่ต้องทำอะไร");
        return;
    }

    const isTpix = Number((await hre.ethers.provider.getNetwork()).chainId) === 4289;
    await (await vault.unpause(isTpix ? { type: 0, gasPrice: 0 } : {})).wait();
    console.log(`✅ เปิดคลัง ${address} แล้ว — รับล็อกและปล่อยเงินได้ (หยุดฉุกเฉิน: guardian/เจ้าของเรียก pause())`);
}

main().catch((error) => {
    console.error("\n❌ unpause ไม่สำเร็จ:", error.message || error);
    process.exitCode = 1;
});
