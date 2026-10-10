/**
 * โอน native TPIX จากกระเป๋า allocation (keystore ใน wallet-output/) ไปที่อยู่ปลายทาง
 *
 * เจ้าของเป็นคนรันเองเสมอผ่าน send-tpix.ps1 — ตัวนั้นถามรหัสผ่าน/คำ 12 คำแบบซ่อน
 * แล้วส่งผ่าน env ให้ process นี้ตัวเดียว (ไม่ลงไฟล์ ไม่ขึ้นจอ ไม่เข้า history)
 *
 * ทำไมไม่ให้ import เข้า MetaMask: กระเป๋า allocation แต่ละใบถือหลักร้อยล้าน TPIX
 * import แล้วกุญแจจะค้างอยู่ใน hot wallet ไปตลอด สคริปต์นี้ถอดรหัสในหน่วยความจำแค่ตอนรัน
 *
 * Env:
 *   SEND_ROLE          role ใน master-wallet.keystores.json (ค่าปริยาย liquidity-market-making)
 *   SEND_TO            ที่อยู่ปลายทาง (พิมพ์ผสมต้อง checksum ถูก — กันพิมพ์ผิด)
 *   SEND_AMOUNT        จำนวน TPIX หน่วยเต็ม เช่น 210
 *   KEYSTORE_PASSWORD  รหัสผ่าน keystore ที่ตั้งตอน generate-master-wallet.js
 *   MASTER_MNEMONIC    คำ 12 คำ — ใช้เมื่อไม่มีรหัสผ่าน (derive ตาม path ใน wallets.json)
 *   TPIX_RPC_URL       ค่าปริยาย https://rpc1.tpix.online (rpc.tpix.online โดน Cloudflare 403)
 *   TPIX_CHAIN_ID      ค่าปริยาย 4289
 *   WALLET_DIR         ค่าปริยาย ../../wallet-output (เปลี่ยนได้ตอนเทสต์)
 *
 * Developed by Xman Studio
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const WALLET_DIR = process.env.WALLET_DIR || path.join(__dirname, "..", "..", "wallet-output");
const RPC_URL = process.env.TPIX_RPC_URL || "https://rpc1.tpix.online";
const CHAIN_ID = Number(process.env.TPIX_CHAIN_ID || 4289);

function fail(message) {
    console.error(`\n❌ ${message}`);
    process.exit(1);
}

/** ที่อยู่พิมพ์ผสมต้อง checksum ถูก (getAddress โยน error ถ้าผิด) · พิมพ์เล็กล้วนรับได้ */
function parseRecipient(raw) {
    try {
        return ethers.getAddress(raw.trim());
    } catch {
        return null;
    }
}

async function loadSigner(entry, keystoreJson) {
    const password = process.env.KEYSTORE_PASSWORD;
    const mnemonic = process.env.MASTER_MNEMONIC;
    delete process.env.KEYSTORE_PASSWORD;
    delete process.env.MASTER_MNEMONIC;

    if (password) {
        console.log("กำลังถอดรหัส keystore (ใช้เวลาประมาณ 10-30 วินาที) ...");
        try {
            return await ethers.Wallet.fromEncryptedJson(keystoreJson, password);
        } catch {
            fail("รหัสผ่าน keystore ไม่ถูกต้อง — ยังไม่มีอะไรถูกส่งขึ้นเชน");
        }
    }
    if (mnemonic) {
        const phrase = mnemonic.trim().toLowerCase().split(/\s+/).join(" ");
        try {
            return ethers.HDNodeWallet.fromPhrase(phrase, undefined, entry.path);
        } catch {
            fail("คำ 12 คำไม่ถูกต้อง (สะกดผิดหรือลำดับผิด) — ยังไม่มีอะไรถูกส่งขึ้นเชน");
        }
    }
    fail("ไม่ได้ใส่ทั้งรหัสผ่าน keystore และคำ 12 คำ");
}

async function main() {
    const role = (process.env.SEND_ROLE || "liquidity-market-making").trim();
    const to = parseRecipient(process.env.SEND_TO || "");
    if (!to) fail(`ที่อยู่ปลายทางไม่ถูกต้อง (หรือ checksum ผิด): ${process.env.SEND_TO || "(ว่าง)"}`);

    const amountRaw = (process.env.SEND_AMOUNT || "").trim();
    if (!/^\d+(\.\d{1,18})?$/.test(amountRaw)) fail(`จำนวนไม่ถูกต้อง: ${amountRaw || "(ว่าง)"}`);
    const value = ethers.parseEther(amountRaw);
    if (value === 0n) fail("จำนวนต้องมากกว่า 0");

    const wallets = JSON.parse(fs.readFileSync(path.join(WALLET_DIR, "wallets.json"), "utf8"));
    const entry = wallets.find((w) => w.role === role);
    if (!entry) fail(`ไม่พบ role "${role}" ใน wallets.json`);

    const keystores = JSON.parse(fs.readFileSync(path.join(WALLET_DIR, "master-wallet.keystores.json"), "utf8"));
    const keystoreJson = keystores[role];
    if (!keystoreJson) fail(`ไม่พบ keystore ของ "${role}"`);

    if (to.toLowerCase() === entry.address.toLowerCase()) fail("ปลายทางเป็นกระเป๋าเดียวกับต้นทาง");

    const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID, { staticNetwork: true });
    const liveChainId = Number(await provider.send("eth_chainId", []));
    if (liveChainId !== CHAIN_ID) fail(`RPC ตอบ chainId ${liveChainId} ไม่ใช่ ${CHAIN_ID}`);

    const signer = await loadSigner(entry, keystoreJson);
    // กุญแจที่ถอดได้ต้องเป็นของกระเป๋าที่ตั้งใจจริง — กันหยิบ role ผิดหรือคำ 12 คำของชุดอื่น
    if (signer.address.toLowerCase() !== entry.address.toLowerCase()) {
        fail(`กุญแจที่ได้คือ ${signer.address} ไม่ใช่กระเป๋า ${role} (${entry.address})`);
    }

    // เชน TPIX ไม่มี baseFee (legacy gas) และ eth_gasPrice = 0 — ใช้ค่าที่เชนบอก ไม่เดาเอง
    const gasPrice = BigInt(await provider.send("eth_gasPrice", []));
    const gasLimit = 21000n;
    const balance = await provider.getBalance(signer.address);
    if (balance < value + gasPrice * gasLimit) {
        fail(`ยอดไม่พอ: กระเป๋ามี ${ethers.formatEther(balance)} TPIX`);
    }

    console.log(`\nจาก   ${role} ${signer.address}`);
    console.log(`ไปที่  ${to}`);
    console.log(`จำนวน ${ethers.formatEther(value)} TPIX · ค่าแก๊ส ${ethers.formatEther(gasPrice * gasLimit)} TPIX`);

    const tx = await signer.connect(provider).sendTransaction({ to, value, type: 0, gasPrice, gasLimit });
    console.log(`\nส่งแล้ว tx: ${tx.hash}`);
    const receipt = await tx.wait(1, 120_000);
    if (!receipt || receipt.status !== 1) fail(`ธุรกรรมไม่สำเร็จ (tx ${tx.hash})`);

    console.log(`ยืนยันในบล็อก ${receipt.blockNumber}`);
    console.log(`ยอดปลายทางตอนนี้: ${ethers.formatEther(await provider.getBalance(to))} TPIX`);
}

main().catch((error) => fail(error.shortMessage || error.message || String(error)));
