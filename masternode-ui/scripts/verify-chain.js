#!/usr/bin/env node
/**
 * verify-chain.js — ตรวจว่าโปรแกรม masternode ยังคุยกับเชนจริงได้ครบทุกอย่าง
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  ทำไมต้องมีสคริปต์นี้
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  เชน TPIX ถูกเปลี่ยนใต้เท้าแอปมาแล้วหลายรอบ (regenesis, ย้ายเครื่อง, สลับ RPC,
 *  Cloudflare เปลี่ยนกฎ) แล้วแอปเพิ่งมารู้ตอนผู้ใช้บ่นว่า "เปิดมาแล้วไม่ขึ้นอะไรเลย"
 *
 *  ที่แย่กว่านั้นคือเคยมีรอบที่แพตช์ User-Agent หายไปจาก rpc-client.js
 *  แล้ว node-manager.js ยัง import `BROWSER_UA` จากที่นั่นอยู่ ได้ค่า undefined
 *  → Node โยน ERR_HTTP_INVALID_HEADER_VALUE ทุกครั้งที่เรียก RPC
 *  ไม่มีเทสต์ตัวไหนจับได้ เพราะไม่มีเทสต์เลย
 *
 *  สคริปต์นี้ยิงของจริงทั้งหมด ไม่มี mock:  `node scripts/verify-chain.js`
 *  ควรรันทุกครั้งหลังแตะ rpc-client / chain-health / node-manager
 *  หรือหลังมีการเปลี่ยนแปลงฝั่งเชน
 */

'use strict';

const rc = require('../electron/rpc-client');
const { decodeValidators } = require('../electron/ibft-extra');
const chainHealth = require('../electron/chain-health');

const EXPECTED_CHAIN_ID = 4289;

let pass = 0;
let fail = 0;

function check(name, ok, detail) {
    if (ok) {
        pass++;
        console.log('  ✓ ' + name + (detail ? '  — ' + detail : ''));
    } else {
        fail++;
        console.log('  ✗ ' + name + (detail ? '  — ' + detail : ''));
    }
}

async function main() {
    console.log('ตรวจการเชื่อมต่อเชนของโปรแกรม masternode');
    console.log('ปลายทางเริ่มต้น: ' + rc.getEndpoint());
    console.log('');

    // ── 1. ปลายทางทางการทุกตัวต้องตอบได้ ─────────────────────────────────────
    console.log('1. ปลายทาง RPC');
    for (const url of [rc.TPIX_RPC, ...rc.FALLBACK_RPC]) {
        rc.setEndpoint(url);
        try {
            const id = parseInt(await rc.rpcCallOn(url, 'eth_chainId', [], 10000), 16);
            check(url, id === EXPECTED_CHAIN_ID, 'chainId ' + id);
        } catch (err) {
            check(url, false, err.message);
        }
    }

    // ── 2. User-Agent ยังอยู่จริงไหม ───────────────────────────────────────────
    //    ยิงดิบแบบไม่ส่ง UA เทียบกับที่ rpc-client ส่ง — ถ้าอันแรกโดน 403
    //    แสดงว่ากฎของ Cloudflare ยังอยู่ และแพตช์ UA ยัง "จำเป็น" อยู่
    console.log('');
    console.log('2. User-Agent (กฎ Cloudflare)');
    const https = require('https');
    const rawStatus = (host, ua) => new Promise((resolve) => {
        const body = JSON.stringify({ jsonrpc: '2.0', method: 'eth_chainId', params: [], id: 1 });
        const headers = { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) };
        if (ua) headers['User-Agent'] = ua;
        const req = https.request(
            { hostname: host, port: 443, path: '/', method: 'POST', headers, timeout: 10000 },
            (res) => { res.resume(); resolve(res.statusCode); },
        );
        req.on('error', () => resolve('ERR'));
        req.on('timeout', () => { req.destroy(); resolve('TIMEOUT'); });
        req.write(body);
        req.end();
    });

    const host = new URL(rc.FALLBACK_RPC[0] || rc.TPIX_RPC).hostname;
    const noUa = await rawStatus(host, null);
    const productUa = await rawStatus(host, rc.PRODUCT_UA);
    const browserUa = await rawStatus(host, rc.BROWSER_UA);

    check(host + ' รับ UA ตามจริงของแอป', productUa === 200, rc.PRODUCT_UA + ' → HTTP ' + productUa);
    check(host + ' รับ UA แบบเบราว์เซอร์ (ทางถอย)', browserUa === 200, 'HTTP ' + browserUa);
    check('แอปกำลังใช้ UA ตามจริงอยู่', rc.activeUserAgent() === rc.PRODUCT_UA, rc.activeUserAgent());

    if (productUa !== 200 && browserUa === 200) {
        console.log('    ⚠ กฎ Cloudflare เข้มขึ้นแล้ว — UA ตามจริงโดนบล็อก แอปจะถอยไปใช้ UA เบราว์เซอร์เอง');
        console.log('      ทางแก้ที่ถูกต้องคือเพิ่มกฎ Skip ให้ header ' + rc.CLIENT_HEADER + ': ' + rc.CLIENT_ID);
    }
    if (noUa === 403) {
        console.log('    หมายเหตุ: ไม่ส่ง UA ยังได้ 403 → กฎยังเปิดอยู่ ห้ามถอด UA ออก');
    } else {
        console.log('    หมายเหตุ: ไม่ส่ง UA ได้ HTTP ' + noUa + ' → กฎอาจถูกปิดแล้ว แต่ยังควรส่ง UA ไว้');
    }

    // ── 3. เมธอดที่โปรแกรมพึ่งพา ──────────────────────────────────────────────
    console.log('');
    console.log('3. เมธอด RPC ที่โปรแกรมใช้จริง');
    rc.setEndpoint(rc.TPIX_RPC);
    const required = [
        ['eth_blockNumber', []],
        ['eth_chainId', []],
        ['net_version', []],
        ['net_peerCount', []],
        ['eth_getBalance', ['0x0000000000000000000000000000000000000000', 'latest']],
        ['eth_getTransactionCount', ['0x0000000000000000000000000000000000000000', 'pending']],
        ['eth_gasPrice', []],
        ['eth_getBlockByNumber', ['latest', false]],
        ['web3_clientVersion', []],
    ];

    for (const [method, params] of required) {
        try {
            await rc.rpcCall(method, params, 10000);
            check(method, true);
        } catch (err) {
            check(method, false, err.message);
        }
    }

    // ── 4. ถอดรายชื่อ validator จาก extraData ─────────────────────────────────
    console.log('');
    console.log('4. รายชื่อ validator (ถอดจาก extraData — เชนไม่มีเมธอด ibft_*)');
    const head = await rc.rpcCall('eth_getBlockByNumber', ['latest', false]);
    const vals = decodeValidators(head.extraData);
    check('ถอดได้อย่างน้อย 1 ตัว', vals.length > 0, vals.length + ' ตัว');
    vals.forEach(v => console.log('      ' + v));

    // ── 5. รายงานสุขภาพเชน ───────────────────────────────────────────────────
    console.log('');
    console.log('5. รายงานสุขภาพเชน');
    const report = await chainHealth.assess(20);
    check('อ่านรายงานได้', !!report.tip, 'บล็อกล่าสุด ' + report.tip);
    check('chainId ตรงกับที่แอปรองรับ', report.chainId === EXPECTED_CHAIN_ID, String(report.chainId));
    check('เชนยังเดินอยู่ (ไม่ค้าง)', !report.stalled, 'บล็อกล่าสุดเก่า ' + report.headAge + ' วิ');
    check('จังหวะบล็อกใกล้เคียงที่ตั้งไว้', report.slowRatio !== null && report.slowRatio < 1.5,
        report.actualBlockTime + 's (ตั้งไว้ ' + report.expectedBlockTime + 's)');
    console.log('    ระดับ: ' + report.severity + ' · peer ' + report.peerCount + ' · validator ' + report.validators);
    report.messages.forEach(m => console.log('    [' + m.level + '] ' + m.text));

    console.log('');
    console.log('─'.repeat(60));
    console.log('ผ่าน ' + pass + ' · ไม่ผ่าน ' + fail);

    process.exit(fail > 0 ? 1 : 0);
}

main().catch((err) => {
    console.error('ตรวจไม่จบ: ' + (err && err.message ? err.message : err));
    process.exit(1);
});
