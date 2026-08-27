/*
 * TPIX JSON-RPC gate — njs 0.8.x
 * ติดตั้งที่ /etc/nginx/njs/tpix-rpc.js (ต้นฉบับอยู่ใน repo: infrastructure/njs/)
 *
 * ทำไมต้องเป็น njs ไม่ใช่ map + if
 * ─────────────────────────────────
 * map ทั้งสามตัวเดิมอ่าน $request_body ใน rewrite phase ซึ่ง **ยังว่างเปล่า**
 * (nginx อ่าน body ใน content phase) วัดจริงบนเซิร์ฟเวอร์ 2026-08-06 แล้ว:
 * content_length=63 แต่ $request_body = "-" → allow-list ไม่มีวันแมตช์ → 403 ทุกคำขอ
 * ตัวกรองเลยถูกคอมเมนต์ทิ้งมาตั้งแต่นั้น = ทุกวันนี้ไม่มีด่านเมธอดเลย
 *
 * js_content ทำงานใน content phase และ nginx อ่าน body ให้เสร็จก่อนเรียก handler
 * จึงเป็นที่เดียวที่ตัดสินจากเนื้อคำขอได้จริง
 *
 * และ map ยังแยกไม่ได้ว่าอันไหน "อ่าน" อันไหน "เขียน" ซึ่งเป็นแกนของงานนี้
 * ─────────────────────────────────────────────────────────────────────────
 * เชนนี้ค่าแก๊ส 0 → ไม่มีต้นทุนต่อธุรกรรม → ผู้ใช้จริง **แซงคิวสแปมด้วยการจ่ายแพงกว่าไม่ได้**
 * (บนเชนปกติจะ bid gas สูงขึ้นเพื่อแซง) ด่านกันสแปมจึงต้องอยู่นอกเชนทั้งหมด
 * และต้องจำกัดที่ "อัตรา" ไม่ใช่ที่ "ราคา"
 *
 * ตัวเลขที่ใช้ตัดสิน (คำนวณจาก config จริง):
 *   เชนรับได้   20,000,000 gas / 21,000 / 2 วิ   ≈ 476 tx/วินาที
 *   nginx เดิม  30 r/s × batch 20                = 600 tx/วินาที จาก IP เดียว
 *   txpool      --max-slots 4096                 → เต็มใน ~7 วินาที
 * → IP เดียว ต้นทุน 0 บาท ยิงเกินความจุเชน และเซ็นเซอร์ผู้ใช้จริงได้ทั้งเชน
 *
 * ไฟล์นี้แยกโควตา "เขียน" ออกจาก "อ่าน" คนละถัง:
 *   อ่าน   — ปล่อยตาม limit_req ของ nginx (30 r/s) พอแล้ว ไม่แตะ mempool
 *   เขียน  — WRITE_PER_WINDOW ครั้ง/WINDOW_SECONDS วินาที/IP นับ **รายธุรกรรม**
 *            ไม่ใช่รายคำขอ (batch 20 ใบ = 20 หน่วย ไม่ใช่ 1) ไม่งั้นโดนเลี่ยง 20 เท่า
 *
 * ⚠️ ที่อยู่ผู้ใช้จริงมาจาก CF-Connecting-IP ซึ่ง **ปลอมได้ถ้ายิงตรงเข้า origin**
 *    ต้องรัน scripts/allow-cloudflare-only.sh ก่อน ไม่งั้นด่านนี้เดินอ้อมได้ทั้งดุ้น
 *    (พิสูจน์แล้ว 2026-08-27: curl -k https://123.253.62.252 -H 'Host: rpc.tpix.online'
 *     ตอบ 200 พร้อมเลขบล็อกจริง)
 */

/* ── งบเขียนต่อ IP ─────────────────────────────────────────────────────────
 * 10 ธุรกรรม / 10 วินาที = เฉลี่ย 1 tx/วินาที แต่ยิงรวดเดียว 10 ใบได้
 * คนใช้จริงส่งไม่กี่ใบต่อนาที ส่วนคนยิงถล่มต้องหา ~400 IP ถึงจะถึงความจุเชน
 * ซึ่งตอนนั้น Cloudflare + fail2ban ถึงจะเริ่มมีความหมาย
 */
var WRITE_PER_WINDOW = 10;
var WINDOW_SECONDS = 10;

/* ต้องตรงกับ --json-rpc-batch-request-limit ของ polygon-edge (ค่าเริ่มต้น 20)
 * ตัดที่ขอบก่อน เพื่อไม่ให้ upstream เสียเวลาแกะคำขอที่ยังไงก็ถูกปฏิเสธ */
var MAX_BATCH = 20;

/* ── ด่านที่ 1 — DENY (ข้ามไม่ได้ ต่อให้อยู่ใน allow-list ก็ตาม) ──────────────
 * polygon-edge 0.9.0 ไม่เปิด namespace พวกนี้อยู่แล้ว แต่:
 *   - อัปเกรดรุ่นแล้วอาจเปิด
 *   - วันหน้าอาจเอา nginx ตัวนี้ไปวางหน้า geth/erigon/besu
 * ปิดไว้ก่อนไม่มีข้อเสีย frontend ไม่เคยเรียกอะไรในนี้
 *
 * ⚠️ ห้ามใส่ ibft — polygon-edge เปิด ibft บน JSON-RPC เป็นอ่านอย่างเดียว
 *    คำสั่งเปลี่ยน validator set (ibft propose) วิ่งผ่าน gRPC 10000 ไม่ใช่ทางนี้
 *    บล็อกทั้ง namespace = masternode-ui พังโดยไม่ได้ปลอดภัยขึ้นเลยสักนิด
 */
var DENY_NAMESPACE = /^(admin|debug|personal|txpool|miner|clique|les|engine|dev|erigon|trace|parity)_/;
var DENY_EXACT = [
    'eth_sign',              // เซ็นอะไรก็ได้ด้วยคีย์ของโหนด
    'eth_sendTransaction',   // ให้โหนดเซ็นให้ — โหนดเราไม่ควรถือคีย์ผู้ใช้อยู่แล้ว
    'eth_signTransaction',
    'eth_accounts',
];

/* ── ด่านที่ 2 — ALLOW (ทุกอย่างนอกรายการนี้ถูกปฏิเสธ) ───────────────────── */
var READ_METHODS = [
    'eth_blockNumber', 'eth_chainId', 'eth_call', 'eth_getBalance',
    'eth_getCode', 'eth_getStorageAt', 'eth_getTransactionCount',
    'eth_getTransactionByHash', 'eth_getTransactionReceipt',
    'eth_getBlockByNumber', 'eth_getBlockByHash',
    'eth_getBlockTransactionCountByNumber', 'eth_getBlockTransactionCountByHash',
    'eth_getLogs', 'eth_estimateGas', 'eth_gasPrice',
    'eth_maxPriorityFeePerGas', 'eth_feeHistory', 'eth_syncing',
    'eth_subscribe', 'eth_unsubscribe', 'eth_newFilter', 'eth_newBlockFilter',
    'eth_getFilterChanges', 'eth_getFilterLogs', 'eth_uninstallFilter',
    'net_version', 'net_listening', 'net_peerCount',
    'web3_clientVersion', 'web3_sha3',
    // ibft อ่านอย่างเดียว — masternode-ui ใช้โชว์รายชื่อ validator
    // เคยได้ 403 มาตลอดเพราะ allow-list เดิมมีแค่ eth_/net_/web3_
    'ibft_getValidatorsByBlockNumber', 'ibft_getSnapshot',
    'ibft_candidates', 'ibft_status', 'ibft_quorum',
];

/* เมธอดที่แตะ mempool — ทุกใบในนี้กินโควตาเขียน 1 หน่วย */
var WRITE_METHODS = ['eth_sendRawTransaction'];

function toSet(list) {
    var set = {};
    for (var i = 0; i < list.length; i++) {
        set[list[i]] = true;
    }
    return set;
}

var DENY_SET = toSet(DENY_EXACT);
var READ_SET = toSet(READ_METHODS);
var WRITE_SET = toSet(WRITE_METHODS);

/**
 * ตัดสินคำขอจากเนื้อ body — ฟังก์ชันบริสุทธิ์ ไม่แตะ nginx เลย
 * แยกออกมาเพื่อให้ node เทสต์ได้จริง (ดู tpix-rpc.test.mjs)
 *
 * @returns {{ok: boolean, code?: number, reason?: string, writes: number, methods: string[]}}
 */
function classify(bodyText) {
    if (typeof bodyText !== 'string' || bodyText.length === 0) {
        return { ok: false, code: 400, reason: 'empty body', writes: 0, methods: [] };
    }

    var payload;
    try {
        payload = JSON.parse(bodyText);
    } catch (e) {
        return { ok: false, code: 400, reason: 'malformed json', writes: 0, methods: [] };
    }

    /* แกะ JSON จริงแทนการ regex หาสตริงทั้งก้อน — ท่าเดิมข้ามได้ด้วยการยัด
     * "method":"eth_call" ลงใน params แล้วเรียกอะไรก็ได้ (audit N1/N2 2026-08-05)
     * และไม่ต้องดัก \uXXXX แยกอีก เพราะ JSON.parse ถอด escape ให้ก่อนเทียบชื่อแล้ว */
    var calls = Array.isArray(payload) ? payload : [payload];

    if (calls.length === 0) {
        return { ok: false, code: 400, reason: 'empty batch', writes: 0, methods: [] };
    }
    if (calls.length > MAX_BATCH) {
        return { ok: false, code: 413, reason: 'batch too large', writes: 0, methods: [] };
    }

    var methods = [];
    var writes = 0;

    for (var i = 0; i < calls.length; i++) {
        var call = calls[i];
        if (call === null || typeof call !== 'object' || Array.isArray(call)) {
            return { ok: false, code: 400, reason: 'not a jsonrpc call', writes: 0, methods: [] };
        }

        var method = call.method;
        if (typeof method !== 'string' || method.length === 0) {
            return { ok: false, code: 400, reason: 'missing method', writes: 0, methods: [] };
        }

        if (DENY_SET[method] === true || DENY_NAMESPACE.test(method)) {
            return { ok: false, code: 403, reason: 'method blocked', writes: 0, methods: [] };
        }

        if (WRITE_SET[method] === true) {
            writes += 1;
        } else if (READ_SET[method] !== true) {
            return { ok: false, code: 403, reason: 'method not allowed', writes: 0, methods: [] };
        }

        methods.push(method);
    }

    return { ok: true, writes: writes, methods: methods };
}

/**
 * ที่อยู่ผู้ใช้จริง — หลัง Cloudflare ตัว $remote_addr คือ edge ของ CF ทุกคน
 * ถ้าใช้ค่านั้นเป็นกุญแจ ทุกคนทั้งโลกจะแชร์ถังใบเดียว = ผู้ใช้จริงล็อกกันเอง
 *
 * header ปลอมได้ถ้ายิงตรงเข้า origin → ต้องปิดทางนั้นที่ไฟร์วอลล์ก่อนเสมอ
 */
function clientKey(r) {
    var cf = r.headersIn['CF-Connecting-IP'];
    if (cf && cf.length > 0 && cf.length < 64) {
        return cf;
    }
    return r.remoteAddress;
}

/**
 * ถังโควตาเขียน — ใช้ js_shared_dict_zone ที่ timeout เท่ากับความกว้างหน้าต่าง
 * คีย์หมดอายุเองเมื่อเงียบครบหน้าต่าง จึงไม่ต้องมีตัวเก็บกวาด
 *
 * @returns {boolean} true = ยังอยู่ในโควตา
 */
function spendWrites(dict, key, units) {
    if (units <= 0) {
        return true;
    }

    /* โซนหาย = config ไม่ครบ ต้อง fail-closed ไม่ใช่ปล่อยผ่านเงียบ ๆ
     * (บทเรียนจาก deploy ที่ขึ้นเขียวทั้งที่ของจริงพัง — deploy_silent_failure_trap) */
    if (dict === undefined || dict === null) {
        return false;
    }

    var used = dict.incr(key, units, 0);
    return used <= WRITE_PER_WINDOW;
}

function corsHeaders(r) {
    var origin = r.headersIn['Origin'];
    if (origin) {
        /* ต้องซ่อนของ upstream ก่อนเติมของเรา — polygon-edge ใส่ * มาเองทุก response
         * เบราว์เซอร์เห็นสองค่าแล้วบล็อกทั้ง request โดย server ตอบ 200 ปกติ
         * (เจอจริง 2026-08-08: การ์ดกระเป๋าคลังบน explorer อ่านยอดไม่ได้ทั้ง 6 ใบ) */
        r.headersOut['Access-Control-Allow-Origin'] = origin;
        r.headersOut['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
        r.headersOut['Access-Control-Allow-Headers'] = 'Content-Type, Authorization';
    }
}

function fail(r, code, message) {
    corsHeaders(r);
    r.headersOut['Content-Type'] = 'application/json';
    /* คืน error รูปแบบ JSON-RPC เสมอ — client อย่าง ethers อ่าน HTML ไม่เป็น
     * แล้วจะโยน error คนละเรื่องจนตามต้นตอไม่เจอ
     * ส่วนรหัส HTTP ยังเป็นตัวจริงเพื่อให้ fail2ban จับได้จาก access log */
    r.return(code, JSON.stringify({
        jsonrpc: '2.0',
        error: { code: -32600, message: message },
        id: null,
    }));
}

async function gate(r) {
    if (r.method === 'OPTIONS') {
        corsHeaders(r);
        r.headersOut['Access-Control-Max-Age'] = '86400';
        r.return(204);
        return;
    }

    if (r.method !== 'POST') {
        fail(r, 405, 'method not allowed');
        return;
    }

    var body = r.requestText;

    /* body ที่ใหญ่เกิน client_body_buffer_size จะถูกเทลงไฟล์ชั่วคราว requestText จะว่าง
     * ต้องตอบด้วยรหัสที่ "บอกสาเหตุได้" ไม่ใช่ 403 ลอย ๆ เพราะอาการเดียวกันนี้
     * เคยทำให้ทุกคำขอโดนปฏิเสธแล้วไล่หาสาเหตุกันอยู่นาน */
    if (body === undefined || body === null) {
        fail(r, 413, 'request body not buffered - raise client_body_buffer_size');
        return;
    }

    var verdict = classify(body);
    if (!verdict.ok) {
        fail(r, verdict.code, verdict.reason);
        return;
    }

    if (!spendWrites(ngx.shared.rpc_write_budget, clientKey(r), verdict.writes)) {
        fail(r, 429, 'write rate limit exceeded');
        return;
    }

    var reply = await r.subrequest('/__rpc_upstream', { method: 'POST', body: body });

    corsHeaders(r);
    r.headersOut['Content-Type'] = 'application/json';
    r.return(reply.status, reply.responseText);
}

export default {
    gate,
    classify,
    spendWrites,
    clientKey,
    WRITE_PER_WINDOW,
    WINDOW_SECONDS,
    MAX_BATCH,
};
