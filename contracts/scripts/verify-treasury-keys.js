#!/usr/bin/env node
/**
 * verify-treasury-keys.js — Phase 0 gate for regenesis.
 *
 * Proves the encrypted keystores in wallet-output/ actually open, and that the
 * address inside each one is the address genesis is about to hand coins to.
 *
 * This exists because a genesis allocation is immutable. If a keystore is
 * corrupt, or the password on paper is not the password that was used, the
 * discovery has to happen NOW — not after 6,960,000,000 TPIX is already
 * assigned to an address nobody can sign for. REGENESIS-RUNBOOK Phase 0.2
 * calls this out: "อย่าเชื่อว่าไฟล์ backup ใช้ได้โดยไม่เคยลอง".
 *
 * Privacy: the password is read with terminal echo off, private keys are never
 * printed, never logged, and never written to disk. Only addresses (public
 * information) and pass/fail status reach stdout, so the output is safe to
 * paste into a chat or a ticket.
 *
 *   cd contracts
 *   node scripts/verify-treasury-keys.js          # the 6 treasury wallets
 *   node scripts/verify-treasury-keys.js --all    # + validator stake wallets
 *
 * Exit code 0 = every wallet opened and matched. Non-zero = do not run genesis.
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { Wallet } = require('ethers');

const REPO = path.resolve(__dirname, '..', '..');
const KEYSTORE_FILE = path.join(REPO, 'wallet-output', 'master-wallet.keystores.json');
const ALLOC_ENV = path.join(REPO, 'infrastructure', 'chain', 'alloc.env');

const ALL = process.argv.includes('--all');

const C = {
  reset: '\x1b[0m', dim: '\x1b[2m', bold: '\x1b[1m',
  red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m', cyan: '\x1b[36m',
};

function die(msg) {
  console.error(`\n${C.red}✗ ${msg}${C.reset}\n`);
  process.exit(1);
}

/** Read a line from the terminal without echoing it. */
function askHidden(prompt) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    // readline writes the prompt, then _writeToOutput swallows every keystroke
    // so the password never appears on screen or in the scrollback buffer.
    let muted = false;
    rl._writeToOutput = function (s) {
      if (!muted) rl.output.write(s);
    };
    rl.question(prompt, (answer) => {
      muted = false;
      rl.output.write('\n');
      rl.close();
      resolve(answer);
    });
    muted = true;
  });
}

/** ALLOC_<SLUG>="<address>:<amount>" — same parser shape as build-genesis.sh. */
function parseAllocEnv(file) {
  const out = [];
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = raw.match(/^ALLOC_([A-Z_]+)\s*=\s*"?([^":]+):(\d+)"?/);
    if (m) out.push({ slug: m[1], address: m[2].trim(), amount: BigInt(m[3]) });
  }
  return out;
}

(async function main() {
  if (!fs.existsSync(KEYSTORE_FILE)) die(`ไม่พบ keystore: ${KEYSTORE_FILE}`);
  if (!fs.existsSync(ALLOC_ENV)) die(`ไม่พบ alloc.env: ${ALLOC_ENV}`);

  const keystores = JSON.parse(fs.readFileSync(KEYSTORE_FILE, 'utf8'));
  const alloc = parseAllocEnv(ALLOC_ENV);
  if (!alloc.length) die('อ่าน alloc.env แล้วไม่เจอรายการ ALLOC_* เลย');

  const roles = Object.keys(keystores);
  const wanted = new Set(alloc.map((a) => a.address.toLowerCase()));

  console.log(`\n${C.bold}ทดสอบปลดล็อกกระเป๋าคลัง TPIX${C.reset}`);
  console.log(`${C.dim}keystore : ${KEYSTORE_FILE}`);
  console.log(`alloc    : ${ALLOC_ENV}`);
  console.log(`กระเป๋าใน keystore ${roles.length} ใบ · ใน alloc.env ${alloc.length} ใบ${C.reset}\n`);
  console.log(`${C.yellow}รหัสผ่านจะไม่แสดงบนหน้าจอ และ private key จะไม่ถูกพิมพ์ออกมาไม่ว่ากรณีใด${C.reset}`);

  const password = await askHidden('\nรหัสผ่าน keystore: ');
  if (!password) die('ไม่ได้ใส่รหัสผ่าน');

  // Decrypt every role once, then match by address. Matching on address rather
  // than on role name is deliberate: wallets.json and alloc.env disagree on
  // three role labels, so trusting the names would report a false mismatch on
  // wallets whose keys are perfectly fine.
  const byAddress = new Map();
  const failed = [];

  console.log(`\n${C.dim}กำลังถอดรหัส (scrypt ใช้เวลาใบละไม่กี่วินาที)...${C.reset}\n`);

  for (const role of roles) {
    let json = keystores[role];
    if (typeof json !== 'string') json = JSON.stringify(json);

    try {
      const w = await Wallet.fromEncryptedJson(json, password);
      byAddress.set(w.address.toLowerCase(), role);
      const inAlloc = wanted.has(w.address.toLowerCase());
      if (inAlloc || ALL) {
        console.log(`  ${C.green}✓${C.reset} ${role.padEnd(26)} ${w.address}${inAlloc ? '' : `  ${C.dim}(ไม่อยู่ใน alloc.env)${C.reset}`}`);
      }
      // The Wallet object holds the private key in memory. Drop the only
      // reference we kept so it is collectable as soon as possible.
    } catch (e) {
      failed.push({ role, reason: e.shortMessage || e.message });
      console.log(`  ${C.red}✗${C.reset} ${role.padEnd(26)} ${C.red}ถอดรหัสไม่ผ่าน${C.reset} — ${e.shortMessage || e.message}`);
    }
  }

  // ---- the actual verdict: every address genesis will fund must be openable
  console.log(`\n${C.bold}ตรวจทีละรายการใน alloc.env${C.reset}\n`);
  console.log(`  ${'SLUG'.padEnd(22)} ${'ADDRESS'.padEnd(44)} ${'TPIX'.padStart(15)}  ผล`);
  console.log(`  ${'-'.repeat(22)} ${'-'.repeat(44)} ${'-'.repeat(15)}  ---`);

  let bad = 0;
  let total = 0n;
  for (const a of alloc) {
    const role = byAddress.get(a.address.toLowerCase());
    const ok = Boolean(role);
    if (!ok) bad++;
    total += a.amount;
    const mark = ok ? `${C.green}เปิดได้${C.reset} ${C.dim}(${role})${C.reset}` : `${C.red}เปิดไม่ได้${C.reset}`;
    console.log(`  ${a.slug.padEnd(22)} ${a.address.padEnd(44)} ${a.amount.toLocaleString('en-US').padStart(15)}  ${mark}`);
  }

  console.log(`  ${'-'.repeat(22)} ${'-'.repeat(44)} ${'-'.repeat(15)}`);
  console.log(`  ${'รวม'.padEnd(22)} ${''.padEnd(44)} ${total.toLocaleString('en-US').padStart(15)}\n`);

  if (bad > 0) {
    die(`มี ${bad} กระเป๋าใน alloc.env ที่เปิดไม่ได้ — ห้ามสร้าง genesis
     ถ้าเป็นเพราะรหัสผ่านผิด ลองใหม่ได้ ถ้าไฟล์เสียให้กู้จาก mnemonic ที่จดไว้`);
  }
  if (failed.length && ALL) {
    console.log(`${C.yellow}⚠ กระเป๋าที่ไม่ได้อยู่ใน alloc.env เปิดไม่ได้ ${failed.length} ใบ — ไม่บล็อก genesis แต่ควรตามดู${C.reset}\n`);
  }

  console.log(`${C.green}${C.bold}✓ ผ่าน — ปลดล็อกได้ครบทุกกระเป๋าที่ genesis จะจ่ายเงินให้${C.reset}`);
  console.log(`${C.dim}  เอาผลนี้ไปเป็นหลักฐานสำหรับ ALLOC_CONFIRMED=YES ตอนรัน build-genesis.sh${C.reset}\n`);
})().catch((e) => die(e.stack || e.message));
