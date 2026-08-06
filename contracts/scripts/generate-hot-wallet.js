#!/usr/bin/env node
/**
 * generate-hot-wallet.js — สร้างกระเป๋าร้อนสำหรับหลังบ้าน tpix.online
 *
 * กระเป๋าร้อนคือใบที่ถือเงินหมุนเวียนจำกัด ให้หลังบ้านจ่ายเงินอัตโนมัติได้
 * โดยที่กระเป๋าคลังทั้ง 6 ใบยังอยู่เย็นและเว็บแตะไม่ถึง
 *
 * ── ทำไมต้องเป็นคีย์สุ่มอิสระ ไม่ derive จาก mnemonic ของคลัง ──────────────
 *
 * กระเป๋าคลังใช้ path m/44'/60'/0'/0/N ซึ่งระดับสุดท้าย (N) เป็น **non-hardened**
 * คุณสมบัติของ non-hardened derivation คือ:
 *
 *     child private key + parent extended public key  →  คำนวณ private key
 *                                                        ของพี่น้องได้ "ทุกใบ"
 *
 * กระเป๋าร้อนคือใบที่มีโอกาสหลุดสูงที่สุดในระบบ (คีย์ต้องอยู่ให้เว็บเซิร์ฟเวอร์
 * เข้าถึงได้เพื่อเซ็นธุรกรรม) ถ้าเอามาจากต้นเดียวกับคลัง = เอาชะตาของ
 * 6,960,000,000 TPIX ไปผูกกับใบที่เสี่ยงที่สุด
 *
 * คีย์สุ่มอิสระทำให้ความเสียหายสูงสุดเท่ากับ "เงินหมุนเวียนที่อยู่ในใบนั้น" เท่านั้น
 *
 * ── ผลลัพธ์ ───────────────────────────────────────────────────────────────
 *
 *   <outdir>/tpix-hot-wallet-<วันที่>.SECRET.txt      ← address + private key + passphrase
 *   <outdir>/tpix-hot-wallet-<วันที่>.keystore.json   ← keystore เข้ารหัส (ขึ้นเซิร์ฟเวอร์)
 *
 * private key จะไม่ถูกพิมพ์ออก stdout เด็ดขาด เพราะ stdout ไปโผล่ใน log,
 * terminal scrollback และ transcript ของเครื่องมือที่รันมันได้
 *
 * ค่า outdir ปริยายคือ ../../chain-key-backups (นอก git repo โดยตั้งใจ)
 *
 *   node scripts/generate-hot-wallet.js [--out <dir>]
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Wallet } = require('ethers');

const argOut = process.argv.indexOf('--out');
const OUT = argOut > -1 && process.argv[argOut + 1]
  ? path.resolve(process.argv[argOut + 1])
  : path.resolve(__dirname, '..', '..', '..', 'chain-key-backups');

(async function main() {
  fs.mkdirSync(OUT, { recursive: true });

  const wallet = Wallet.createRandom();
  // 24 ไบต์สุ่มจาก CSPRNG — ไม่ใช่รหัสที่คนคิดเอง เพราะ keystore นี้จะถูกวางบน
  // เครื่องที่ต่ออินเทอร์เน็ต passphrase จึงต้องทนการเดาแบบออฟไลน์
  const passphrase = crypto.randomBytes(24).toString('base64url');
  const keystore = await wallet.encrypt(passphrase);

  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const secretPath = path.join(OUT, `tpix-hot-wallet-${stamp}.SECRET.txt`);
  const ksPath = path.join(OUT, `tpix-hot-wallet-${stamp}.keystore.json`);

  const body = [
    `TPIX HOT WALLET (operational float) - created ${new Date().toISOString()}`,
    '='.repeat(66),
    'เก็บออฟไลน์ ห้ามอัปขึ้น Drive / คลาวด์ / แชท / git',
    '',
    `ADDRESS       : ${wallet.address}`,
    `PRIVATE KEY   : ${wallet.privateKey}`,
    `KEYSTORE PASS : ${passphrase}`,
    '',
    'สร้างเป็นคีย์สุ่มอิสระโดยตั้งใจ ไม่ได้ derive จาก mnemonic ของกระเป๋าคลัง',
    '',
    "เหตุผล: กระเป๋าคลังใช้ path m/44'/60'/0'/0/N ซึ่งระดับสุดท้ายเป็น non-hardened",
    'ถ้า private key ของลูกใบใดใบหนึ่งหลุดพร้อม extended public key ของแม่',
    'จะคำนวณ private key ของพี่น้องได้ทุกใบ',
    'กระเป๋าร้อนคือใบที่เสี่ยงหลุดที่สุด (คีย์ต้องให้เว็บเซิร์ฟเวอร์เข้าถึงได้)',
    'จึงต้องไม่อยู่ต้นเดียวกับคลัง มิฉะนั้นเสียใบเดียว = เสีย 6,960,000,000 TPIX',
    '',
    'วิธีใช้บนเซิร์ฟเวอร์:',
    `  1. อัป ${path.basename(ksPath)} ไปไว้นอก document root (เช่น /etc/tpix/)`,
    '  2. ใส่ KEYSTORE PASS ข้างบนลง .env ของ Laravel เป็น TPIX_HOT_WALLET_PASS',
    '     ห้ามเก็บใน database ห้าม commit',
    '  3. แอปถอดรหัสตอนรันไทม์เท่านั้น ไม่เขียน private key ลงดิสก์หรือ log',
    '',
    'เติมเงินเข้ากระเป๋านี้เท่าที่จำเป็นต่อการจ่ายจริง (แนะนำ 10-20M TPIX)',
    'ยอดที่เกินความจำเป็นคือความเสียหายที่รอเกิดขึ้นเปล่า ๆ',
    ''
  ].join('\n');

  fs.writeFileSync(secretPath, body, { mode: 0o600 });
  fs.writeFileSync(ksPath, keystore, { mode: 0o600 });

  console.log('');
  console.log('  สร้างกระเป๋าร้อนแล้ว');
  console.log('  ADDRESS          :', wallet.address);
  console.log('  ไฟล์ความลับ       :', secretPath);
  console.log('  keystore เข้ารหัส :', ksPath);
  console.log('');
  console.log('  private key ไม่ถูกพิมพ์ออกหน้าจอโดยตั้งใจ — เปิดอ่านจากไฟล์');
  console.log('');
})().catch((e) => { console.error('ผิดพลาด:', e.message); process.exit(1); });
