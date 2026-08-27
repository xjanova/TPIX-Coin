/*
 * เทสต์ตรรกะของด่าน RPC — รันด้วย node ธรรมดา ไม่ต้องมี nginx
 *
 *   node --test infrastructure/njs/tpix-rpc.test.mjs
 *
 * ทำไมต้องมี: ตัวกรองรุ่นก่อนหน้าถูกคอมเมนต์ทิ้งเพราะ "ทดสอบไม่ได้จนกว่าจะขึ้นเซิร์ฟ"
 * แล้วพอขึ้นจริงมันบล็อกทุกคำขอ ตรรกะการตัดสินจึงถูกแยกออกมาเป็นฟังก์ชันบริสุทธิ์
 * เพื่อให้พิสูจน์ได้ก่อนแตะเซิร์ฟเวอร์
 *
 * ⚠️ เทสต์นี้ครอบ "ตรรกะการตัดสิน" เท่านั้น ส่วนที่ต้องพิสูจน์บนเซิร์ฟเวอร์จริง
 *    คือ nginx อ่าน body ให้ทันไหม + subrequest ทำงานไหม → scripts/verify-rpc-gate.sh
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import gate from './tpix-rpc.js';

const { classify, spendWrites, WRITE_PER_WINDOW } = gate;

const rpc = (method, params = []) =>
    JSON.stringify({ jsonrpc: '2.0', method, params, id: 1 });

const batch = (methods) =>
    JSON.stringify(methods.map((method, i) => ({ jsonrpc: '2.0', method, params: [], id: i })));

/** ถังจำลองแบบเดียวกับ ngx.shared.<zone> — incr คืนยอดสะสมหลังบวก */
function fakeDict() {
    const store = new Map();
    return {
        incr(key, delta, init) {
            const next = (store.has(key) ? store.get(key) : init) + delta;
            store.set(key, next);
            return next;
        },
    };
}

// ── เมธอดอ่าน ───────────────────────────────────────────────────────────────

test('เมธอดอ่านทั่วไปผ่าน และไม่กินโควตาเขียน', () => {
    for (const method of ['eth_blockNumber', 'eth_call', 'eth_getLogs', 'net_version']) {
        const v = classify(rpc(method));
        assert.equal(v.ok, true, method);
        assert.equal(v.writes, 0, method);
    }
});

test('ibft อ่านอย่างเดียวต้องผ่าน — masternode-ui พึ่งอันนี้', () => {
    // เคยได้ 403 มาตลอดเพราะ allow-list เดิมมีแค่ eth_/net_/web3_
    assert.equal(classify(rpc('ibft_getValidatorsByBlockNumber')).ok, true);
});

// ── deny-list ──────────────────────────────────────────────────────────────

test('namespace แอดมิน/ดีบักถูกปฏิเสธทั้งตระกูล', () => {
    for (const method of ['admin_peers', 'debug_traceTransaction', 'txpool_status',
                          'personal_unlockAccount', 'miner_start', 'engine_newPayloadV1']) {
        const v = classify(rpc(method));
        assert.equal(v.ok, false, method);
        assert.equal(v.code, 403, method);
    }
});

test('เมธอดที่ให้โหนดเซ็นแทนผู้ใช้ถูกปฏิเสธ', () => {
    for (const method of ['eth_sign', 'eth_sendTransaction', 'eth_signTransaction', 'eth_accounts']) {
        assert.equal(classify(rpc(method)).ok, false, method);
    }
});

test('เมธอดที่ไม่รู้จักถูกปฏิเสธ (default deny)', () => {
    const v = classify(rpc('eth_someFutureMethod'));
    assert.equal(v.ok, false);
    assert.equal(v.reason, 'method not allowed');
});

// ── ช่องที่ตัวกรองรุ่น regex เคยโดนเจาะ (audit N1/N2 2026-08-05) ──────────────

test('ยัดชื่อเมธอดที่อนุญาตลงใน params เพื่อหลอก allow-list ไม่ได้อีก', () => {
    // regex เดิมหา "สตริงที่ไหนก็ได้ในทั้ง body" จึงผ่านด่านด้วยท่านี้
    const evil = JSON.stringify({
        jsonrpc: '2.0',
        method: 'admin_addPeer',
        params: ['"method":"eth_call"'],
        id: 1,
    });
    const v = classify(evil);
    assert.equal(v.ok, false);
    assert.equal(v.code, 403);
});

test('unicode escape เลี่ยง deny-list ไม่ได้ — JSON.parse ถอดให้ก่อนเทียบ', () => {
    // "admin_peers" = "admin_peers"
    const evil = '{"jsonrpc":"2.0","method":"\\u0061dmin_peers","params":[],"id":1}';
    assert.equal(classify(evil).ok, false);
});

test('batch ที่มีตัวแรกถูกต้อง แต่ซ่อนเมธอดต้องห้ามไว้ข้างหลัง ถูกปฏิเสธทั้งชุด', () => {
    const v = classify(batch(['eth_blockNumber', 'eth_chainId', 'debug_traceTransaction']));
    assert.equal(v.ok, false);
    assert.equal(v.code, 403);
});

// ── batch ──────────────────────────────────────────────────────────────────

test('batch ปกติผ่าน และนับจำนวนธุรกรรมที่เขียนได้ถูกต้อง', () => {
    const v = classify(batch(['eth_blockNumber', 'eth_sendRawTransaction', 'eth_sendRawTransaction']));
    assert.equal(v.ok, true);
    assert.equal(v.writes, 2, 'batch 20 ใบต้องกิน 20 หน่วย ไม่ใช่ 1 ไม่งั้นโดนเลี่ยง 20 เท่า');
});

test('batch เกิน 20 ถูกตัดที่ขอบ ไม่ส่งต่อ upstream', () => {
    const v = classify(batch(new Array(21).fill('eth_chainId')));
    assert.equal(v.ok, false);
    assert.equal(v.code, 413);
});

// ── input พัง ──────────────────────────────────────────────────────────────

test('body ว่าง / JSON พัง / ไม่ใช่ก้อน jsonrpc ถูกปฏิเสธโดยไม่โยน exception', () => {
    for (const body of ['', '{', '[]', 'null', '[1,2,3]', '{"jsonrpc":"2.0","id":1}']) {
        const v = classify(body);
        assert.equal(v.ok, false, JSON.stringify(body));
        assert.equal(typeof v.code, 'number');
    }
});

test('method ที่ไม่ใช่สตริงถูกปฏิเสธ', () => {
    assert.equal(classify('{"jsonrpc":"2.0","method":123,"id":1}').ok, false);
    assert.equal(classify('{"jsonrpc":"2.0","method":null,"id":1}').ok, false);
});

// ── โควตาเขียน ─────────────────────────────────────────────────────────────

test('เขียนได้ครบโควตาแล้วตัว ' + (WRITE_PER_WINDOW + 1) + ' ถูกปฏิเสธ', () => {
    const dict = fakeDict();
    for (let i = 1; i <= WRITE_PER_WINDOW; i++) {
        assert.equal(spendWrites(dict, '1.2.3.4', 1), true, 'ใบที่ ' + i);
    }
    assert.equal(spendWrites(dict, '1.2.3.4', 1), false, 'ใบที่เกินโควตา');
});

test('การอ่านไม่กินโควตาเขียนเลย แม้ยิงรัว', () => {
    const dict = fakeDict();
    for (let i = 0; i < 1000; i++) {
        assert.equal(spendWrites(dict, '1.2.3.4', 0), true);
    }
    assert.equal(spendWrites(dict, '1.2.3.4', WRITE_PER_WINDOW), true, 'โควตายังเต็มอยู่');
});

test('batch ใหญ่กินโควตาทีเดียวหมดแล้วโดนปฏิเสธรอบถัดไป', () => {
    const dict = fakeDict();
    assert.equal(spendWrites(dict, '1.2.3.4', WRITE_PER_WINDOW), true);
    assert.equal(spendWrites(dict, '1.2.3.4', 1), false);
});

test('คนละ IP คนละถัง — คนยิงถล่มต้องหา IP จริงเยอะถึงจะได้ปริมาณ', () => {
    const dict = fakeDict();
    for (let i = 0; i < WRITE_PER_WINDOW; i++) {
        spendWrites(dict, 'attacker', 1);
    }
    assert.equal(spendWrites(dict, 'attacker', 1), false);
    assert.equal(spendWrites(dict, 'ผู้ใช้จริง', 1), true, 'ผู้ใช้คนอื่นต้องไม่โดนหางเลข');
});

test('โซนหาย = ปฏิเสธ ไม่ใช่ปล่อยผ่านเงียบ ๆ', () => {
    // ถ้า js_shared_dict_zone ตกหล่นจาก config ด่านต้องพังแบบเห็นได้
    assert.equal(spendWrites(undefined, '1.2.3.4', 1), false);
    assert.equal(spendWrites(null, '1.2.3.4', 1), false);
});
