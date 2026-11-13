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

/* ── งบแก๊สต่อ IP ───────────────────────────────────────────────────────────
 * โควตาด้านบนนับ "จำนวนใบ" — โอนธรรมดา 21,000 gas กับธุรกรรม 10,000,000 gas กิน 1 หน่วยเท่ากัน
 * เชนรับได้ 10M gas / 2 วิ = 5M gas/วินาที ส่วน IP เดียวส่งได้เฉลี่ย 1 ใบ/วินาที
 * → IP เดียวที่ส่งใบละ 5M gas ทำให้ทุกบล็อกเต็มได้ โดยไม่เกินโควตาจำนวนใบเลย
 *   (security-review-2026-10-25 ข้อ F1 — คำนวณจาก config ยังไม่เคยยิงโหลดจริง)
 *
 * ด่านนี้อ่าน gas limit จากธุรกรรมที่เซ็นแล้ว (ดู rawTxGas) แล้วหักจากงบของ IP นั้น
 *   12M gas / 60 วิ = เฉลี่ย 0.2M gas/วินาที = 4% ของความจุเชน → ต้องมี ~25 IP ถึงจะเต็มเชน
 *   หน้าต่าง 60 วิ (ไม่ใช่ 10 วิ) เพราะงบต้อง ≥ MAX_TX_GAS เสมอ ไม่งั้นธุรกรรมใหญ่ใบเดียว
 *   (deploy สัญญา) จะไม่มีวันผ่าน — หน้าต่างสั้น + งบ ≥ 10M = IP เดียวได้ 20% ของเชน
 *
 * ⚠️ ค่าพวกนี้เป็นค่าตั้งต้น ยังไม่ได้ยืนยันด้วยโหลดจริงบน infrastructure/lab
 * ⚠️ ใช้โซนของตัวเอง (rpc_gas_budget, timeout=60s) ไม่ปนกับ rpc_write_budget (timeout=10s)
 *    ถ้าปน วันที่ njs รุ่นใหม่ทำให้ค่าที่ incr() สร้างหมดอายุตาม timeout ของโซน
 *    งบแก๊สจะกลายเป็น 12M ต่อ 10 วิ เงียบ ๆ
 */
var GAS_PER_WINDOW = 12000000;
var GAS_WINDOW_SECONDS = 60;

/* ต้องตรงกับ --block-gas-target ของ validator (single-host/docker-compose.yml)
 * ธุรกรรมที่ขอแก๊สเกินนี้ไม่มีวันลงบล็อกได้ — ตัดที่ขอบพร้อมบอกสาเหตุ
 * ⛔ ถ้าขยับ --block-gas-target ขึ้น ต้องขยับค่านี้ (และ GAS_PER_WINDOW) ตาม
 *    ไม่งั้นธุรกรรมใหญ่ที่เชนรับได้จะโดน 400 ที่ด่าน */
var MAX_TX_GAS = 10000000;

/* ธุรกรรมที่ถูกต้องทุกใบใช้อย่างน้อย 21,000 — ใบที่แจ้งต่ำกว่านี้โหนดปฏิเสธเอง
 * แต่ยังกินแรงโหนดตอนถอด จึงคิดขั้นต่ำเท่านี้ */
var MIN_TX_GAS = 21000;

/* ถอด gas limit ไม่ออก (ไม่ใช่ hex / RLP พัง / ชนิดธุรกรรมที่ไม่รู้จัก) → คิดเต็มเพดาน
 * ยังส่งต่อให้โหนดเพื่อให้ผู้ใช้ได้ข้อความ error ของโหนดเอง แต่ขยะแบบนี้ผ่านได้ ~1 ใบ/นาที/IP */
var UNPARSED_TX_GAS = MAX_TX_GAS;

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

var HEX_RE = /^[0-9a-fA-F]+$/;

/**
 * เลขจาก hex ช่วงไบต์ [from, to) — -1 ถ้าไม่ใช่ hex ล้วน
 *
 * ตรวจเฉพาะไบต์ที่อ่านจริง (ไม่เกิน 6 ไบต์ต่อครั้ง) โดยตั้งใจ:
 *   - parseInt('1z', 16) ได้ 1 ไม่ใช่ NaN → ถ้าไม่ตรวจ ขยะจะถูกอ่านเป็น "แก๊สน้อย" แล้วหลุดการคิดเต็มเพดาน
 *   - ไม่เอา regex ไปจับทั้งก้อน: ธุรกรรมยาวได้ถึง ~128k ตัวอักษร และ regex แบบวนกลุ่มบนสตริงยาวขนาดนั้น
 *     ยังไม่เคยลองบน njs/PCRE ของเครื่องจริง ถ้ามันโยน error ธุรกรรมใหญ่ทุกใบจะได้ 500
 */
function hexInt(hex, from, to) {
    var s = hex.substring(from * 2, to * 2);
    if (!HEX_RE.test(s)) {
        return -1;
    }
    return parseInt(s, 16);
}

/**
 * หัวของ RLP item ที่ตำแหน่ง pos (หน่วยเป็นไบต์) — อ่านจากสตริง hex ตรง ๆ
 * ไม่แปลงทั้งก้อนเป็น buffer เพราะต้องการแค่ 3-5 ช่องแรก ส่วน data อาจยาวหลายหมื่นไบต์
 *
 * @returns {{list: boolean, start: number, len: number}|null} null = RLP พัง/ล้นขอบ
 */
function rlpHead(hex, pos, end) {
    if (pos >= end) {
        return null;
    }

    var b = hexInt(hex, pos, pos + 1);
    if (b < 0) {
        return null;
    }
    var isList = b >= 0xc0;
    var start;
    var len;

    if (b < 0x80) {
        start = pos;          // ไบต์เดียว ค่าคือตัวมันเอง
        len = 1;
    } else {
        var short = b - (isList ? 0xc0 : 0x80);
        if (short <= 55) {
            start = pos + 1;
            len = short;
        } else {
            var lenOfLen = short - 55;
            /* body ถูกจำกัดที่ 128k → ความยาว 3 ไบต์ก็เกินพอ เกิน 4 คือของปลอม
             * (และกัน parseInt เกิน 2^53) */
            if (lenOfLen > 4 || pos + 1 + lenOfLen > end) {
                return null;
            }
            len = hexInt(hex, pos + 1, pos + 1 + lenOfLen);
            if (len < 0) {
                return null;
            }
            start = pos + 1 + lenOfLen;
        }
    }

    if (start + len > end) {
        return null;
    }
    return { list: isList, start: start, len: len };
}

/**
 * gas limit ของธุรกรรมที่เซ็นแล้ว (พารามิเตอร์ตัวแรกของ eth_sendRawTransaction)
 * ไม่ตรวจลายเซ็น ไม่ถอด field อื่น — โหนดทำส่วนนั้นเอง ที่นี่ต้องการแค่ "ใบนี้ขอแก๊สเท่าไร"
 *
 *   legacy        rlp([nonce, gasPrice, gasLimit, ...])                        ช่องที่ 2
 *   0x01 (2930)   0x01 || rlp([chainId, nonce, gasPrice, gasLimit, ...])        ช่องที่ 3
 *   0x02 (1559)   0x02 || rlp([chainId, nonce, tip, feeCap, gasLimit, ...])     ช่องที่ 4
 *
 * @returns {number} gas limit, หรือ -1 ถ้าถอดไม่ออก
 */
function rawTxGas(raw) {
    if (typeof raw !== 'string' || raw.length < 4 || raw.length % 2 !== 0
        || raw.charAt(0) !== '0' || raw.charAt(1) !== 'x') {
        return -1;
    }

    var hex = raw.substring(2);
    var end = hex.length / 2;
    var pos = 0;
    var gasIndex = 2;

    var first = hexInt(hex, 0, 1);
    if (first < 0) {
        return -1;
    }
    if (first < 0xc0) {
        if (first === 0x01) {
            gasIndex = 3;
        } else if (first === 0x02) {
            gasIndex = 4;
        } else {
            return -1;        // รวม 0x7f (state tx ของ polygon-edge) — ไม่ควรมาทาง RPC สาธารณะ
        }
        pos = 1;
    }

    var outer = rlpHead(hex, pos, end);
    if (outer === null || !outer.list || outer.start + outer.len !== end) {
        return -1;
    }

    var p = outer.start;
    for (var i = 0; i <= gasIndex; i++) {
        var item = rlpHead(hex, p, end);
        if (item === null || item.list) {
            return -1;
        }
        if (i === gasIndex) {
            if (item.len === 0) {
                return 0;     // จำนวนเต็ม 0 ใน RLP คือสตริงว่าง
            }
            if (item.len > 6) {
                return Number.MAX_SAFE_INTEGER;   // เกิน 2^48 — เกินเพดานแน่นอน ไม่ต้องรู้ค่าจริง
            }
            return hexInt(hex, item.start, item.start + item.len);
        }
        p = item.start + item.len;
    }

    return -1;
}

/**
 * ตัดสินคำขอจากเนื้อ body — ฟังก์ชันบริสุทธิ์ ไม่แตะ nginx เลย
 * แยกออกมาเพื่อให้ node เทสต์ได้จริง (ดู tpix-rpc.test.mjs)
 *
 * gas = แก๊สรวมที่ธุรกรรมในคำขอนี้ขอ (ใช้หักงบแก๊ส) — มีเฉพาะเมื่อ ok
 *
 * @returns {{ok: boolean, code?: number, reason?: string, writes: number, gas?: number, methods: string[]}}
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
    var gas = 0;

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

            var txGas = rawTxGas(Array.isArray(call.params) ? call.params[0] : undefined);
            if (txGas < 0) {
                txGas = UNPARSED_TX_GAS;
            } else if (txGas > MAX_TX_GAS) {
                return {
                    ok: false, code: 400, reason: 'transaction gas limit above block gas limit',
                    writes: 0, methods: [],
                };
            } else if (txGas < MIN_TX_GAS) {
                txGas = MIN_TX_GAS;
            }
            gas += txGas;
        } else if (READ_SET[method] !== true) {
            return { ok: false, code: 403, reason: 'method not allowed', writes: 0, methods: [] };
        }

        methods.push(method);
    }

    return { ok: true, writes: writes, gas: gas, methods: methods };
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
 * ถังโควตาเขียน — หน้าต่างคงที่ WINDOW_SECONDS วินาที ผูกเลขหน้าต่างไว้ในกุญแจ
 *
 * ⚠️ เดิมใช้กุญแจ = IP อย่างเดียว แล้วหวังให้ timeout ของ js_shared_dict_zone ล้างค่าเอง
 *    แต่บน njs 0.8.2 (libnginx-mod-http-js ของ Ubuntu) ค่าที่สร้างด้วย incr() ไม่หมดอายุ
 *    → ทุก IP ส่งธุรกรรมได้ 10 ใบ "ตลอดไป" จน nginx restart (เจอจริง 2026-10-22: deploy Token Factory
 *    ค้างหลังธุรกรรมที่ 10 แล้วรอบใหม่ 7 นาทีต่อมาก็ยังโดน 429 ตั้งแต่ใบแรก)
 *    ตอนนี้หน้าต่างใหม่ = กุญแจใหม่ เริ่มนับจาก 0 เสมอ ไม่ว่า timeout จะทำงานหรือไม่
 *    กุญแจของหน้าต่างเก่าไม่มีใครอ่านอีก — โซนตั้ง evict ไว้ ตัวเก่าสุดถูกเขี่ยเมื่อเต็ม
 *    (ไม่ส่ง timeout เป็นอาร์กิวเมนต์ที่ 4 ของ incr — ไม่แน่ใจว่า 0.8.2 รับ ถ้าโยน error ทุกธุรกรรมจะได้ 500)
 *
 * @param {number} [nowMs] เวลาปัจจุบัน (มิลลิวินาที) — ใส่ได้เพื่อเทสต์
 * @returns {boolean} true = ยังอยู่ในโควตา
 */
function spendWrites(dict, key, units, nowMs) {
    if (units <= 0) {
        return true;
    }

    /* โซนหาย = config ไม่ครบ ต้อง fail-closed ไม่ใช่ปล่อยผ่านเงียบ ๆ
     * (บทเรียนจาก deploy ที่ขึ้นเขียวทั้งที่ของจริงพัง — deploy_silent_failure_trap) */
    if (dict === undefined || dict === null) {
        return false;
    }

    var now = typeof nowMs === 'number' ? nowMs : Date.now();
    var windowNo = Math.floor(now / (WINDOW_SECONDS * 1000));
    var used = dict.incr(key + '|' + windowNo, units, 0);
    return used <= WRITE_PER_WINDOW;
}

/**
 * ถังงบแก๊ส — หน้าต่างคงที่ GAS_WINDOW_SECONDS วินาที กุญแจผูกเลขหน้าต่างแบบเดียวกับ spendWrites
 *
 * ต่างจาก spendWrites จุดเดียว: ใบที่ไม่ผ่าน **คืนงบ** (หักแล้วบวกกลับ)
 * ไม่งั้นผู้ใช้ที่ลองส่งใบใหญ่เกินงบที่เหลือครั้งเดียว จะโดนปฏิเสธใบเล็กไปทั้งหน้าต่าง
 * คนยิงถล่มไม่ได้อะไรจากการคืนนี้ — ใบที่ถูกปฏิเสธไปไม่ถึงโหนด และยังกินโควตาจำนวนใบอยู่
 *
 * @param {number} [nowMs] เวลาปัจจุบัน (มิลลิวินาที) — ใส่ได้เพื่อเทสต์
 * @returns {boolean} true = ยังอยู่ในงบ
 */
function spendGas(dict, key, gas, nowMs) {
    if (gas <= 0) {
        return true;
    }

    /* โซนหาย = fail-closed เหมือน spendWrites
     * ⛔ ลำดับ deploy: ต้องลง nginx-njs.conf (ที่ประกาศ rpc_gas_budget) **ก่อน** ไฟล์นี้
     *    ลงไฟล์นี้อย่างเดียว = ธุรกรรมทุกใบได้ 429 */
    if (dict === undefined || dict === null) {
        return false;
    }

    var now = typeof nowMs === 'number' ? nowMs : Date.now();
    var windowNo = Math.floor(now / (GAS_WINDOW_SECONDS * 1000));
    var slot = key + '|' + windowNo;
    var used = dict.incr(slot, gas, 0);
    if (used <= GAS_PER_WINDOW) {
        return true;
    }

    /* ยังไม่ได้ยืนยันบน njs 0.8.2 ว่า incr รับค่าลบ — ถ้าโยน error ให้ถือว่าไม่ได้คืนงบ
     * (ผลคือเข้มขึ้น ไม่ใช่หลวมลง) ดีกว่าปล่อยให้คำขอที่ควรได้ 429 กลายเป็น 500 */
    try {
        dict.incr(slot, -gas, 0);
    } catch (e) {
        /* ตั้งใจปล่อยผ่าน */
    }
    return false;
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

    if (!spendGas(ngx.shared.rpc_gas_budget, clientKey(r), verdict.gas)) {
        fail(r, 429, 'gas rate limit exceeded');
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
    spendGas,
    rawTxGas,
    clientKey,
    WRITE_PER_WINDOW,
    WINDOW_SECONDS,
    MAX_BATCH,
    GAS_PER_WINDOW,
    GAS_WINDOW_SECONDS,
    MAX_TX_GAS,
    MIN_TX_GAS,
};
