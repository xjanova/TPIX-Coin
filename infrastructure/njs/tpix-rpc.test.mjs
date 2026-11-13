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

const {
    classify, spendWrites, spendGas, rawTxGas,
    WRITE_PER_WINDOW, WINDOW_SECONDS,
    GAS_PER_WINDOW, GAS_WINDOW_SECONDS, MAX_TX_GAS, MIN_TX_GAS,
} = gate;

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

test('โควตาเต็มแล้วหน้าต่างถัดไปส่งได้อีก — แม้ค่าในโซนไม่หมดอายุเองเลย (njs 0.8.2)', () => {
    // fakeDict ไม่มีการหมดอายุ = พฤติกรรมจริงของ incr() บน libnginx-mod-http-js 0.8.2
    // รุ่นเดิม (กุญแจ = IP) ล้มตรงนี้: ใบที่ 11 ถูกปฏิเสธตลอดไป ไม่ว่าจะเว้นนานแค่ไหน
    const dict = fakeDict();
    const t0 = 1_800_000_000_000;
    for (let i = 0; i < WRITE_PER_WINDOW; i++) {
        assert.equal(spendWrites(dict, '1.2.3.4', 1, t0), true);
    }
    assert.equal(spendWrites(dict, '1.2.3.4', 1, t0 + 1000), false, 'หน้าต่างเดิมยังเต็ม');
    const later = t0 + WINDOW_SECONDS * 1000;
    assert.equal(spendWrites(dict, '1.2.3.4', 1, later), true, 'หน้าต่างใหม่ต้องเริ่มนับใหม่');
    assert.equal(spendWrites(dict, '1.2.3.4', 1, t0 + 7 * 60 * 1000), true, '7 นาทีต่อมาต้องส่งได้');
});

test('ครั้งที่ถูกปฏิเสธในหน้าต่างเดียวกันไม่ลามไปหน้าต่างถัดไป', () => {
    // hardhat ลองส่งซ้ำทุก 5 วินาทีหลังโดน 429 — เดิมแต่ละครั้งนับเพิ่มจนไม่มีวันหลุด
    const dict = fakeDict();
    const t0 = 1_800_000_000_000;
    spendWrites(dict, '1.2.3.4', WRITE_PER_WINDOW, t0);
    for (let i = 0; i < 50; i++) {
        assert.equal(spendWrites(dict, '1.2.3.4', 1, t0 + 100 + i), false);
    }
    assert.equal(spendWrites(dict, '1.2.3.4', 1, t0 + WINDOW_SECONDS * 1000 + 1), true);
});

test('โซนหาย = ปฏิเสธ ไม่ใช่ปล่อยผ่านเงียบ ๆ', () => {
    // ถ้า js_shared_dict_zone ตกหล่นจาก config ด่านต้องพังแบบเห็นได้
    assert.equal(spendWrites(undefined, '1.2.3.4', 1), false);
    assert.equal(spendWrites(null, '1.2.3.4', 1), false);
});

// ── งบแก๊ส: ถอด gas limit จากธุรกรรมที่เซ็นแล้ว ─────────────────────────────
//
// ธุรกรรมข้างล่างเซ็นจริงด้วย ethers 6.17 (กุญแจสุ่มทิ้ง, chainId 4289, gasPrice 0)
// ค่า gas คือค่าที่ ethers ถอดกลับได้จาก raw เดียวกัน — ไม่ได้มาจากตัวถอดของเราเอง

const SIGNED = {
    transfer21k: '0xf861808082520894000000000000000000000000000000000000dead01808221a6a07a281bdae8308daa52e66517bb4e8bdb8d7a403d633e6a0cc15750bc287f1f9da062bfd4b92be3d1dafa914a63054407dd111273562e11e5de038645cfa97fdf28',
    // data 300 ไบต์ → หัว list แบบยาว (0xf9 + ความยาว 2 ไบต์)
    call5m: '0xf901900780834c4b4094000000000000000000000000000000000000dead80b9012c' + 'ab'.repeat(300)
        + '8221a5a0733bde569d256e9138eddda17dfd253e7e41998ed1f9fc825c2daef59d29f956a055f0b20f7633d1df3be2c1f08fcbd78f95620ccafaacfdd0dc45db9fa9ba4187',
    // nonce 200 → nonce ไม่ใช่ไบต์เดียว (0x81c8) ตัวถอดต้องข้ามให้ถูก
    max10m: '0xf88b81c8808398968094000000000000000000000000000000000000dead80a8000000000000000000000000000000000000000000000000000000000000000000000000000000008221a6a062a28c492decf1e095b819749faeaec71d067302a1660b5f548df034b728b246a022f3c056630791507e2d5f72b3a10c4775af5c97d4ee76ee372b85e9cb9786fe',
    overBlock: '0xf86202808398968194000000000000000000000000000000000000dead80808221a6a06af2e63aaa09a2a8c415fd612a33b9497cf3747d6bef21f12ff6612dfdc37305a023e88bf43dd68553279ed1e4fa2a11e86809c8771a770140c5d017a435555771',
    gasZero: '0xf85f03808094000000000000000000000000000000000000dead80808221a5a0a2fe9cb8f02e1dab5fb201c05455824883858edb1685674f82f5fffbedcd45daa0135fba4f83dc2565a739dee51e228a94541623204a0b40cb1a6aa967ad47f547',
    type1: '0x01f8648210c104808309fbf194000000000000000000000000000000000000dead8080c080a0aaaa6f717259522fb12aff45be7e269dbedf0dcccfc2223a2634a528e965fbc5a0068466bcbef21e446c132eed6d63d912d97388b4b0f48895e2045c390e3df5bb',
    type2: '0x02f8658210c10580808301e24094000000000000000000000000000000000000dead8080c001a0e5b1ca0df36148c04e39f8d8359a1b57ee69868448ab98ce56d13f07ed3c6360a07a7e66905ad4f5e63ef26657b9408fe4b0e8338afd862e79ba127ec0403d87b0',
};

/** ตัวเข้ารหัส RLP ขั้นต่ำ — ใช้สร้างธุรกรรมรูปร่างแปลก ๆ ที่ไม่อยากฝัง hex ยาวเป็นแสนตัว */
const rlpLen = (len, base) => {
    if (len <= 55) return (base + len).toString(16).padStart(2, '0');
    let h = len.toString(16);
    if (h.length % 2) h = '0' + h;
    return (base + 55 + h.length / 2).toString(16) + h;
};
const rlpStr = (hex) => (hex.length === 2 && parseInt(hex, 16) < 0x80 ? hex : rlpLen(hex.length / 2, 0x80) + hex);
const rlpList = (items) => rlpLen(items.join('').length / 2, 0xc0) + items.join('');
const intHex = (n) => {
    if (n === 0) return '';
    const h = n.toString(16);
    return h.length % 2 ? '0' + h : h;
};
const legacyTx = (gasHex, dataHex = '') => '0x' + rlpList([
    rlpStr(intHex(1)), rlpStr(''), rlpStr(gasHex), rlpStr('00'.repeat(19) + 'ad'),
    rlpStr(''), rlpStr(dataHex), rlpStr('21a5'), rlpStr('11'.repeat(32)), rlpStr('22'.repeat(32)),
]);

const sendRaw = (raw) => rpc('eth_sendRawTransaction', [raw]);

test('ตัวเข้ารหัสของเทสต์ให้ผลตรงกับธุรกรรมที่ ethers เซ็นจริง (กันเทสต์หลอกตัวเอง)', () => {
    const mine = '0x' + rlpList([
        rlpStr(''), rlpStr(''), rlpStr(intHex(21000)), rlpStr('00'.repeat(18) + 'dead'),
        rlpStr('01'), rlpStr(''), rlpStr('21a6'),
        rlpStr('7a281bdae8308daa52e66517bb4e8bdb8d7a403d633e6a0cc15750bc287f1f9d'),
        rlpStr('62bfd4b92be3d1dafa914a63054407dd111273562e11e5de038645cfa97fdf28'),
    ]);
    assert.equal(mine, SIGNED.transfer21k);
});

test('ถอด gas limit จากธุรกรรมจริงได้ตรงทุกชนิด', () => {
    assert.equal(rawTxGas(SIGNED.transfer21k), 21000);
    assert.equal(rawTxGas(SIGNED.call5m), 5000000);
    assert.equal(rawTxGas(SIGNED.max10m), 10000000);
    assert.equal(rawTxGas(SIGNED.overBlock), 10000001);
    assert.equal(rawTxGas(SIGNED.gasZero), 0);
    assert.equal(rawTxGas(SIGNED.type1), 654321, 'EIP-2930: gas อยู่ช่องที่ 3');
    assert.equal(rawTxGas(SIGNED.type2), 123456, 'EIP-1559: gas อยู่ช่องที่ 4');
});

test('ธุรกรรม deploy ขนาดใหญ่ (หัว list ยาว 3 ไบต์) ถอดได้โดยไม่ต้องอ่าน data ทั้งก้อน', () => {
    const raw = legacyTx(intHex(3200000), '60'.repeat(70000));
    assert.equal(raw.slice(2, 4), 'fa', 'ต้องเป็นหัว list ที่มีความยาว 3 ไบต์');
    assert.equal(rawTxGas(raw), 3200000);
});

test('ของที่ไม่ใช่ธุรกรรม / RLP พัง ได้ -1 เสมอ ไม่โยน exception', () => {
    const cut = SIGNED.transfer21k.slice(0, -20);          // ขาดท้าย
    const extra = SIGNED.transfer21k + '00';               // มีไบต์เกินท้าย
    const garbage = [
        undefined, null, 123, {}, [], '', '0x', '0xzz', '0xabc', 'f861808082520894',
        cut, extra,
        '0xc0',                                             // list ว่าง
        '0x80',                                             // ไม่ใช่ list
        '0xf8ff01',                                         // แจ้งยาว 255 แต่มีไบต์เดียว
        '0xffffffffffffffffff',                             // ความยาวของความยาว 8 ไบต์
        '0x7f' + SIGNED.transfer21k.slice(2),               // state tx ของ polygon-edge
        '0x03' + SIGNED.type2.slice(4),                     // ชนิดที่ไม่รู้จัก
        '0x' + rlpList([rlpStr('01'), rlpStr(''), rlpList([rlpStr('01')])]),   // ช่อง gas เป็น list
        '0x' + rlpList([rlpStr('01'), rlpStr('')]),         // ไม่มีช่อง gas
        // ไม่ใช่ hex ตรงไบต์ที่ตัวถอดอ่าน — parseInt('5z',16) ได้ 5 ถ้าไม่ตรวจจะถูกอ่านเป็นแก๊สน้อย
        SIGNED.transfer21k.replace('825208', '825z08'),
        SIGNED.transfer21k.replace('0xf861', '0xfz61'),
        SIGNED.call5m.replace('0xf90190', '0xf9019g'),
    ];
    for (const raw of garbage) {
        assert.equal(rawTxGas(raw), -1, JSON.stringify(raw));
    }
});

test('gas limit ที่ใหญ่เกิน 2^48 ไม่ล้นเป็นเลขเล็ก', () => {
    const raw = legacyTx('ff'.repeat(8));
    assert.ok(rawTxGas(raw) > MAX_TX_GAS);
    assert.equal(classify(sendRaw(raw)).code, 400);
});

// ── งบแก๊ส: classify รวมแก๊สของคำขอ ─────────────────────────────────────────

test('classify รวมแก๊สของธุรกรรมทุกใบใน batch — การอ่านไม่กินแก๊ส', () => {
    assert.equal(classify(rpc('eth_call')).gas, 0);
    assert.equal(classify(sendRaw(SIGNED.transfer21k)).gas, 21000);

    const body = JSON.stringify([
        { jsonrpc: '2.0', method: 'eth_blockNumber', params: [], id: 0 },
        { jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [SIGNED.transfer21k], id: 1 },
        { jsonrpc: '2.0', method: 'eth_sendRawTransaction', params: [SIGNED.call5m], id: 2 },
    ]);
    const v = classify(body);
    assert.equal(v.ok, true);
    assert.equal(v.writes, 2);
    assert.equal(v.gas, 5021000);
});

test('ธุรกรรมที่ขอแก๊สเกินเพดานบล็อกถูกตัดที่ด่าน พร้อมบอกสาเหตุ', () => {
    assert.equal(classify(sendRaw(SIGNED.max10m)).ok, true, 'เท่าเพดานพอดีต้องผ่าน');
    const v = classify(sendRaw(SIGNED.overBlock));
    assert.equal(v.ok, false);
    assert.equal(v.code, 400);
    assert.equal(v.reason, 'transaction gas limit above block gas limit');
});

test('ธุรกรรมที่ถอดแก๊สไม่ออกยังส่งต่อได้ แต่ถูกคิดเต็มเพดาน', () => {
    for (const params of [[], ['0xdeadbeef'], ['not hex'], [123], undefined, 'x', [null]]) {
        const body = JSON.stringify({ jsonrpc: '2.0', method: 'eth_sendRawTransaction', params, id: 1 });
        const v = classify(body);
        assert.equal(v.ok, true, JSON.stringify(params));
        assert.equal(v.gas, MAX_TX_GAS, JSON.stringify(params));
    }
});

test('ธุรกรรมที่แจ้งแก๊สต่ำกว่า 21,000 ถูกคิดขั้นต่ำ ไม่ใช่ฟรี', () => {
    assert.equal(classify(sendRaw(SIGNED.gasZero)).gas, MIN_TX_GAS);
});

// ── งบแก๊ส: ถังต่อ IP ───────────────────────────────────────────────────────

test('งบแก๊สต้องไม่น้อยกว่าธุรกรรมใหญ่สุดที่เชนรับได้ — ไม่งั้น deploy ใบใหญ่ไม่มีวันผ่าน', () => {
    assert.ok(GAS_PER_WINDOW >= MAX_TX_GAS);
});

test('IP เดียวส่งใบละ 5M gas ได้ไม่เกินงบ — ช่องที่ทำให้ทุกบล็อกเต็มจาก IP เดียว (F1)', () => {
    const dict = fakeDict();
    const t0 = 1_800_000_000_000 - (1_800_000_000_000 % (GAS_WINDOW_SECONDS * 1000));
    let passed = 0;
    // 1 ใบ/วินาที ตลอดหนึ่งหน้าต่าง = เท่าที่โควตาจำนวนใบยอมให้พอดี
    for (let s = 0; s < GAS_WINDOW_SECONDS; s++) {
        if (spendGas(dict, '1.2.3.4', 5000000, t0 + s * 1000)) passed++;
    }
    assert.equal(passed, Math.floor(GAS_PER_WINDOW / 5000000));
    // ความจุเชน 5M gas/วินาที — IP เดียวต้องได้ไม่เกิน 5% ของมัน
    const chainGasPerWindow = 5000000 * GAS_WINDOW_SECONDS;
    assert.ok(passed * 5000000 <= chainGasPerWindow * 0.05);
});

test('ใบใหญ่ที่ไม่ผ่านไม่กินงบ — ใบเล็กที่ตามมายังส่งได้', () => {
    const dict = fakeDict();
    const t0 = 1_800_000_000_000 - (1_800_000_000_000 % (GAS_WINDOW_SECONDS * 1000));
    assert.equal(spendGas(dict, '1.2.3.4', 5000000, t0), true);
    assert.equal(spendGas(dict, '1.2.3.4', 10000000, t0 + 1), false, '5M + 10M เกินงบ');
    assert.equal(spendGas(dict, '1.2.3.4', 21000, t0 + 2), true, 'ใบเล็กต้องไม่โดนหางเลข');
    assert.equal(spendGas(dict, '1.2.3.4', GAS_PER_WINDOW - 5021000, t0 + 3), true, 'ใช้ได้ครบงบพอดี');
    assert.equal(spendGas(dict, '1.2.3.4', 21000, t0 + 4), false, 'งบหมดแล้ว');
});

test('ธุรกรรมใหญ่สุดที่เชนรับได้ผ่านได้ในหน้าต่างว่าง', () => {
    assert.equal(spendGas(fakeDict(), '1.2.3.4', MAX_TX_GAS, 1_800_000_000_000), true);
});

test('งบแก๊สแยกถังต่อ IP และเริ่มใหม่เมื่อขึ้นหน้าต่างใหม่', () => {
    const dict = fakeDict();
    const t0 = 1_800_000_000_000 - (1_800_000_000_000 % (GAS_WINDOW_SECONDS * 1000));
    assert.equal(spendGas(dict, 'attacker', GAS_PER_WINDOW, t0), true);
    assert.equal(spendGas(dict, 'attacker', 21000, t0 + 1000), false);
    assert.equal(spendGas(dict, 'ผู้ใช้จริง', 21000, t0 + 1000), true);
    assert.equal(spendGas(dict, 'attacker', 21000, t0 + GAS_WINDOW_SECONDS * 1000 - 1), false, 'ยังหน้าต่างเดิม');
    assert.equal(spendGas(dict, 'attacker', 21000, t0 + GAS_WINDOW_SECONDS * 1000), true, 'หน้าต่างใหม่');
});

test('การอ่าน (แก๊ส 0) ไม่แตะถังแก๊ส และโซนหาย = ปฏิเสธ', () => {
    assert.equal(spendGas(undefined, '1.2.3.4', 0), true, 'อ่านอย่างเดียวต้องไม่พึ่งโซน');
    assert.equal(spendGas(undefined, '1.2.3.4', 21000), false);
    assert.equal(spendGas(null, '1.2.3.4', 21000), false);
});

test('ถ้า incr ไม่รับค่าลบ (ยังไม่ได้ยืนยันบน njs 0.8.2) ต้องได้ปฏิเสธ ไม่ใช่ exception', () => {
    const inner = fakeDict();
    const dict = {
        incr(key, delta, init) {
            if (delta < 0) throw new TypeError('negative delta');
            return inner.incr(key, delta, init);
        },
    };
    const t0 = 1_800_000_000_000;
    assert.equal(spendGas(dict, '1.2.3.4', GAS_PER_WINDOW, t0), true);
    assert.equal(spendGas(dict, '1.2.3.4', 21000, t0 + 1), false);
});
