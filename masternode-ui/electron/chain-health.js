/**
 * chain-health.js — วัดสุขภาพเชน TPIX จากของจริง ไม่ใช่จากค่าที่สมมติไว้
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  ทำไมไฟล์นี้เกิดขึ้น (2026-08-05)
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  ตรวจเชนจริงผ่าน explorer แล้วพบว่า:
 *
 *      blockTime ที่ตั้งใน genesis   = 2.0 วินาที
 *      blockTime ที่เกิดขึ้นจริง      = 6.0 วินาที   ← ช้ากว่า 3 เท่า
 *      indexer ของ Blockscout        = ตามทันแล้ว 100% (ไม่ใช่ปัญหา lag)
 *
 *  ดู timestamp บล็อกติดกัน: 2s, 2s, 14s วนซ้ำ
 *  รูปแบบนี้คือ IBFT หมุนไปถึงคิว validator ตัวที่ไม่ propose แล้ว timeout ~10 วินาที
 *  ก่อนข้ามไปตัวถัดไป → **validator 1 ใน 4 ตัวไม่ทำงาน**
 *
 *  ที่มันซ่อนอยู่ได้นานเพราะเครื่องมือเดิมถามผิดคำถาม:
 *    - health-check.yml (ทุก 4 ชม.)  ถาม "ออกบล็อกไหม" → ออก จึงตอบว่าปกติ
 *    - chain-watchdog.sh              รีสตาร์ทเมื่อ "หยุด" → ช่องว่าง 14s ไม่นับว่าหยุด
 *    - ไม่มีอะไรวัด "บล็อกช้าลงจากที่ควรเป็น" หรือ "validator ไหนหายไปจากคิว"
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  แก้อีกสองรอบหลังเชนใหม่ (2026-08-11)
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  หลัง regenesis 6 ส.ค. 2026 ตรวจเชนใหม่แล้วเจอว่าไฟล์นี้เองก็ถามผิดอยู่สองข้อ:
 *
 *  1. **เรียกเมธอดที่เชนไม่มี**
 *     `ibft_getValidatorsByBlockNumber` → `-32601 the method does not exist`
 *     polygon-edge v0.9.0 ไม่มีเมธอดตระกูล `ibft_*` เลย (ทั้ง getSnapshot / status)
 *     ไม่ใช่เรื่อง allow-list ของ nginx อย่างที่คอมเมนต์เดิมเดาไว้
 *     ผลคือ `report.validators` เป็น null ทุกครั้งตั้งแต่เขียนมา → ข้อ 5
 *     (ประมาณจำนวน proposer ที่หาย) **ไม่เคยทำงานเลยสักครั้ง** และล้มแบบไม่ส่งเสียง
 *     ตอนนี้ถอดรายชื่อจาก extraData ของบล็อกแทน (ดู ibft-extra.js) ซึ่งมีข้อมูลอยู่แล้ว
 *
 *  2. **เชนค้างสนิทถูกรายงานว่า "ปกติ"**  ← อันตรายกว่าข้อแรกมาก
 *     ของเดิมวัดแต่ "ช่องว่างระหว่างบล็อกที่มีอยู่" ถ้าเชนหยุดออกบล็อกไปเลย
 *     40 บล็อกสุดท้ายยังห่างกัน 2 วิเท่าเดิมทุกคู่ → สรุปว่า severity = ok
 *     เหตุการณ์ 7-8 ส.ค. 2026 ที่เชนค้าง 38 ชั่วโมง (IBFT round ไต่ถึง 13)
 *     ถ้าเปิดแอปดูตอนนั้นจะขึ้นไฟเขียวสวยงาม
 *     ตอนนี้เช็ค "บล็อกล่าสุดเก่าแค่ไหนเทียบกับเวลาปัจจุบัน" เป็นด่านแรกก่อนเสมอ
 *
 *  3. เพิ่มเช็ค chainId — หลัง regenesis ถ้าแอปไปชี้เชนเก่า/เชนอื่นค้างไว้
 *     ต้องรู้ทันที ไม่ใช่ปล่อยให้ยอดเงินกับ nonce เพี้ยนแล้วค่อยงง
 *
 *  ค่าที่วัดได้จริงบนเชนใหม่ 2026-08-11: บล็อกห่างกัน 2 วินาทีเป๊ะ 14 ช่วงติด
 *  peer = 3 · validator = 4 ตัว → EXPECTED_BLOCK_TIME = 2 ยังถูกต้อง
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  หมายเหตุเรื่อง RPC
 * ══════════════════════════════════════════════════════════════════════════════
 *  ต้องเรียกผ่าน rpc-client.js เท่านั้น เพราะที่นั่นมี browser User-Agent
 *  (Cloudflare ตอบ 403 ให้คำขอที่ไม่มี UA — โน้ต 2026-06-19) + rate limit
 *  + circuit breaker + การสลับไปปลายทางสำรองเมื่อตัวหลักล่ม
 */

'use strict';

const { rpcCall } = require('./rpc-client');
const { decodeValidators } = require('./ibft-extra');

/** blockTime ที่ genesis ตั้งไว้ (วินาที) — ใช้เป็นฐานเทียบ ไม่ใช่ค่าที่เชื่อว่าเป็นจริง */
const EXPECTED_BLOCK_TIME = 2;

/** chainId ที่แอปนี้ถูกสร้างมาให้คุยด้วย — เจอค่าอื่นแปลว่าชี้ผิดเชน */
const EXPECTED_CHAIN_ID = 4289;

/** ช้ากว่าที่ควรเกินกี่เท่าถึงถือว่าผิดปกติ */
const SLOW_RATIO_WARN = 1.5;
const SLOW_RATIO_CRIT = 2.5;

/** บล็อกล่าสุดเก่ากว่านี้ (วินาที) = เชนสะดุด / หยุดเดิน */
const STALL_WARN_SECONDS = EXPECTED_BLOCK_TIME * 5;   // 10s
const STALL_CRIT_SECONDS = EXPECTED_BLOCK_TIME * 15;  // 30s

/** ช่องว่างระหว่างบล็อกที่ถือว่า "รอบนั้นหมดเวลา" ไม่ใช่แค่ช้า */
const ROUND_TIMEOUT_HINT = EXPECTED_BLOCK_TIME * 4;

/** จำนวนบล็อกที่สุ่มมาวัด — มากพอให้เห็นรูปแบบ น้อยพอไม่ถล่ม RPC */
const DEFAULT_SAMPLE = 40;

const hexToInt = (h) => (typeof h === 'string' ? parseInt(h, 16) : Number(h));

/**
 * ดึงบล็อก N ก้อนล่าสุด แล้วคำนวณช่องว่างระหว่างกัน
 *
 * คืน `head` (บล็อกล่าสุดแบบเต็ม) มาด้วย เพราะผู้เรียกต้องใช้ extraData
 * ถอดรายชื่อ validator ต่อ — จะได้ไม่ต้องยิง RPC ซ้ำอีกรอบ
 *
 * @returns {Promise<{tip:number, head:object|null, blocks:Array<{height:number,ts:number}>, gaps:number[]}>}
 */
async function sampleRecentBlocks(sampleSize = DEFAULT_SAMPLE) {
    const tipHex = await rpcCall('eth_blockNumber');
    const tip = hexToInt(tipHex);
    if (!Number.isFinite(tip) || tip <= 0) {
        throw new Error('อ่าน eth_blockNumber ไม่ได้');
    }

    const from = Math.max(0, tip - sampleSize + 1);
    const blocks = [];
    let head = null;

    // ดึงทีละก้อนแบบต่อเนื่อง — rpc-client มี rate limit + circuit breaker อยู่แล้ว
    // ไม่ยิงขนานเพื่อไม่ให้ชน limit_req ของ nginx (30r/s burst 60)
    for (let h = from; h <= tip; h++) {
        const b = await rpcCall('eth_getBlockByNumber', ['0x' + h.toString(16), false]);
        if (!b || !b.timestamp) continue;
        blocks.push({ height: hexToInt(b.number), ts: hexToInt(b.timestamp) });
        if (hexToInt(b.number) === tip) head = b;
    }

    blocks.sort((a, b) => a.height - b.height);

    const gaps = [];
    for (let i = 1; i < blocks.length; i++) {
        gaps.push(blocks[i].ts - blocks[i - 1].ts);
    }

    return { tip, head, blocks, gaps };
}

/**
 * วิเคราะห์ว่าเชนสุขภาพดีไหม และถ้าไม่ดี ผิดปกติแบบไหน
 *
 * @returns {Promise<object>} รายงานพร้อมใช้แสดงใน UI
 */
async function assess(sampleSize = DEFAULT_SAMPLE) {
    const report = {
        checkedAt: Date.now(),
        ok: false,
        severity: 'unknown',   // ok | warn | critical | unknown
        messages: [],
        expectedBlockTime: EXPECTED_BLOCK_TIME,
        actualBlockTime: null,
        slowRatio: null,
        timeouts: 0,
        peerCount: null,
        validators: null,
        validatorAddresses: [],
        missingProposers: null,
        tip: null,
        headAge: null,
        chainId: null,
        clientVersion: null,
        stalled: false,
    };

    const raise = (level, text) => {
        report.messages.push({ level, text });
        if (level === 'critical') report.severity = 'critical';
        else if (level === 'warn' && report.severity !== 'critical') report.severity = 'warn';
    };

    // ── 0. เชนที่คุยอยู่ใช่เชนที่ตั้งใจไหม ────────────────────────────────────
    // ต้องถามก่อนทุกอย่าง — ถ้าชี้ผิดเชน ตัวเลขที่เหลือก็ไม่มีความหมาย
    try {
        report.chainId = hexToInt(await rpcCall('eth_chainId'));
        if (report.chainId !== EXPECTED_CHAIN_ID) {
            raise('critical',
                `ปลายทาง RPC ตอบว่าเป็น chainId ${report.chainId} `
                + `แต่แอปนี้ทำงานกับ TPIX Chain (${EXPECTED_CHAIN_ID}) — กำลังชี้ผิดเชนอยู่`);
        }
    } catch (err) {
        report.severity = 'critical';
        raise('critical', 'ติดต่อเชนไม่ได้: ' + err.message);

        return report;
    }

    let sample;
    try {
        sample = await sampleRecentBlocks(sampleSize);
    } catch (err) {
        report.severity = 'critical';
        report.messages.push({ level: 'critical', text: 'ติดต่อเชนไม่ได้: ' + err.message });

        return report;
    }

    report.tip = sample.tip;

    // ── 1. บล็อกล่าสุดเก่าแค่ไหน — ด่านสำคัญที่สุด ─────────────────────────────
    //
    // ถ้าเชนหยุดเดิน ช่องว่างของบล็อกเก่าจะยังสวยเหมือนเดิมทุกคู่
    // ต้องเทียบกับ "เวลาตอนนี้" เท่านั้นถึงจะจับได้ (เหตุการณ์ค้าง 38 ชม. 8 ส.ค. 69)
    //
    // ต้องอ่านบล็อกล่าสุด **สดตรงนี้** ห้ามใช้ก้อนที่ดึงไว้ตอนเริ่มสุ่ม
    // เพราะการสุ่มกินเวลาหลายวินาที ถ้าเอาก้อนเก่ามาเทียบเวลาปัจจุบัน
    // จะกลายเป็นวัด "ความช้าของตัวเอง" แล้วรายงานว่าเชนสะดุดทั้งที่เชนปกติดี
    // (เจอจริงตอนทดสอบ 2026-08-11: สุ่ม 20 ก้อนใช้ 17 วิ → รายงาน headAge 13 วิ)
    let latest = sample.head;
    try {
        latest = await rpcCall('eth_getBlockByNumber', ['latest', false]);
    } catch {
        // อ่านไม่ได้ก็ใช้ก้อนสุดท้ายจากการสุ่มไปก่อน — ค่าจะเก่ากว่าความจริงเล็กน้อย
    }

    const head = latest && latest.timestamp
        ? { height: hexToInt(latest.number), ts: hexToInt(latest.timestamp) }
        : sample.blocks[sample.blocks.length - 1];

    if (head) {
        const age = Math.floor(Date.now() / 1000) - head.ts;
        report.headAge = age;

        if (age < -STALL_WARN_SECONDS) {
            // นาฬิกาเครื่องผู้ใช้ช้ากว่าเชน — ไม่ใช่ความผิดของเชน แต่ต้องบอก
            raise('warn',
                `นาฬิกาเครื่องนี้ช้ากว่าเชนอยู่ ${Math.abs(age)} วินาที `
                + '— ค่าที่วัดเรื่องเวลาอาจเพี้ยน ลองเทียบเวลาเครื่องกับอินเทอร์เน็ต');
        } else if (age >= STALL_CRIT_SECONDS) {
            report.stalled = true;
            raise('critical',
                `เชนหยุดออกบล็อก — บล็อกล่าสุด (#${head.height}) เก่าไปแล้ว ${formatAge(age)} `
                + `ทั้งที่ควรออกทุก ${EXPECTED_BLOCK_TIME} วินาที`);
        } else if (age >= STALL_WARN_SECONDS) {
            raise('warn',
                `บล็อกล่าสุดเก่าไปแล้ว ${age} วินาที (ควรไม่เกิน ${EXPECTED_BLOCK_TIME * 2}) `
                + '— เชนอาจกำลังสะดุด');
        }
    }

    if (sample.gaps.length === 0) {
        if (report.severity === 'unknown') report.severity = 'unknown';
        report.messages.push({ level: 'warn', text: 'ตัวอย่างบล็อกไม่พอสำหรับวิเคราะห์' });

        return report;
    }

    // ── 2. blockTime จริงเทียบกับที่ควรเป็น ────────────────────────────────────
    const avg = sample.gaps.reduce((a, b) => a + b, 0) / sample.gaps.length;
    report.actualBlockTime = Number(avg.toFixed(2));
    report.slowRatio = Number((avg / EXPECTED_BLOCK_TIME).toFixed(2));

    // ── 3. นับรอบที่หมดเวลา (ช่องว่างยาวผิดปกติ) ───────────────────────────────
    const timeoutGaps = sample.gaps.filter((g) => g >= ROUND_TIMEOUT_HINT);
    report.timeouts = timeoutGaps.length;

    // ── 4. peer count ─────────────────────────────────────────────────────────
    try {
        report.peerCount = hexToInt(await rpcCall('net_peerCount'));
    } catch {
        report.peerCount = null;
    }

    // ── 5. validator set — ถอดจาก extraData ไม่ใช่เรียก ibft_* ที่ไม่มีจริง ────
    const addrs = decodeValidators((latest && latest.extraData) || (sample.head && sample.head.extraData));
    if (addrs.length > 0) {
        report.validatorAddresses = addrs;
        report.validators = addrs.length;
    } else {
        report.messages.push({
            level: 'info',
            text: 'อ่านรายชื่อ validator จาก extraData ไม่ได้ — '
                + 'รูปแบบบล็อกอาจเปลี่ยนไปจากที่ ibft-extra.js รองรับ',
        });
    }

    // ── 6. ประมาณว่ามี proposer หายไปกี่ตัว ────────────────────────────────────
    // ถ้ามี V validator และ M ตัวไม่ propose รูปแบบที่เห็นคือ (V-M) บล็อกเร็ว
    // สลับกับ M ช่องว่างที่หมดเวลา ต่อหนึ่งรอบ
    // → สัดส่วนช่องว่างที่หมดเวลา ≈ M / V
    if (report.validators && report.validators > 0 && sample.gaps.length >= report.validators) {
        const timeoutShare = report.timeouts / sample.gaps.length;
        const estimated = Math.round(timeoutShare * report.validators);
        report.missingProposers = estimated;

        if (estimated > 0) {
            const faultBudget = Math.floor((report.validators - 1) / 3); // IBFT ทน f ตัว
            const level = estimated >= faultBudget ? 'critical' : 'warn';
            raise(level,
                `คาดว่ามี validator ประมาณ ${estimated} ตัวจาก ${report.validators} `
                + `ไม่ propose บล็อก (พบช่องว่างที่หมดเวลา ${report.timeouts} ครั้ง `
                + `ใน ${sample.gaps.length} ช่วง)`
                + (estimated >= faultBudget
                    ? ` — IBFT ชุดนี้ทนพังได้แค่ ${faultBudget} ตัว `
                      + 'เท่ากับไม่เหลือ fault tolerance แล้ว ตัวไหนสะดุดอีกตัวเชนหยุด'
                    : ''));
        }
    }

    // ── 7. สรุประดับความรุนแรงจาก blockTime ────────────────────────────────────
    // ข้ามถ้าเชนค้างอยู่แล้ว — ค่าเฉลี่ยของบล็อกเก่าไม่ได้บอกอะไรเพิ่ม
    if (!report.stalled) {
        if (report.slowRatio >= SLOW_RATIO_CRIT) {
            raise('critical',
                `บล็อกช้ากว่าที่ตั้งไว้ ${report.slowRatio} เท่า `
                + `(จริง ${report.actualBlockTime}s / ควรเป็น ${EXPECTED_BLOCK_TIME}s)`);
        } else if (report.slowRatio >= SLOW_RATIO_WARN) {
            raise('warn',
                `บล็อกช้ากว่าที่ตั้งไว้ ${report.slowRatio} เท่า `
                + `(จริง ${report.actualBlockTime}s / ควรเป็น ${EXPECTED_BLOCK_TIME}s)`);
        }
    }

    if (report.peerCount !== null && report.peerCount < 2) {
        raise('critical', `peer เหลือ ${report.peerCount} — โหนดกำลังหลุดจากเครือข่าย`);
    }

    // ── 8. รุ่นของโหนด — ไว้ยืนยันว่าคุยกับ tpix-chain จริง ────────────────────
    try {
        report.clientVersion = await rpcCall('web3_clientVersion');
    } catch {
        // ไม่จำเป็นต่อการตัดสินสุขภาพ — ไม่มีก็ได้
    }

    if (report.severity === 'unknown') report.severity = 'ok';
    report.ok = report.severity === 'ok';

    if (report.ok) {
        report.messages.push({
            level: 'info',
            text: `เชนปกติ — บล็อก ${report.actualBlockTime}s, peer ${report.peerCount}`
                + (report.validators ? `, validator ${report.validators} ตัว` : ''),
        });
    }

    return report;
}

/** แปลงวินาทีเป็นข้อความอ่านง่าย — ใช้ตอนบอกว่าบล็อกล่าสุดเก่าแค่ไหน */
function formatAge(seconds) {
    if (seconds < 60) return `${seconds} วินาที`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)} นาที`;
    // ถึง 2 วันยังบอกเป็นชั่วโมง — "38 ชั่วโมง" สื่อความรุนแรงได้ตรงกว่า "1 วัน"
    if (seconds < 172800) return `${Math.floor(seconds / 3600)} ชั่วโมง`;

    return `${Math.floor(seconds / 86400)} วัน`;
}

/**
 * blockTime จริงที่วัดได้ พร้อม cache — ใช้แทนการ hardcode 2 วินาที
 *
 * เดิม node-manager.js ใช้ `BLOCK_TIME = 2` ประมาณ block number ตอน RPC ล่ม:
 *     blockNumber = last_reward_block + Math.floor(elapsedSeconds / BLOCK_TIME)
 * ซึ่งบนเชนที่บล็อกออกทุก 6 วินาที จะ**ประมาณเกินไป 3 เท่า**
 * และค่านั้นไปลงเป็น checkpoint การจ่ายรางวัล staking (updateStakingRewardCheckpoint)
 */
let _cached = { value: EXPECTED_BLOCK_TIME, at: 0 };
const CACHE_TTL_MS = 5 * 60 * 1000;

async function measuredBlockTime(sampleSize = 20) {
    if (Date.now() - _cached.at < CACHE_TTL_MS) return _cached.value;

    try {
        const { gaps } = await sampleRecentBlocks(sampleSize);
        if (gaps.length > 0) {
            // ใช้ median ไม่ใช่ mean — ช่องว่างจาก round timeout เป็น outlier
            // ที่ทำให้ mean เพี้ยน ส่วน median บอก "จังหวะปกติ" ได้ตรงกว่า
            const sorted = [...gaps].sort((a, b) => a - b);
            const median = sorted[Math.floor(sorted.length / 2)];
            if (median > 0) {
                _cached = { value: median, at: Date.now() };
            }
        }
    } catch {
        // ใช้ค่า cache เดิม / ค่าเริ่มต้นต่อไป — อย่าให้ตัววัดทำงานหลักล้ม
    }

    return _cached.value;
}

module.exports = {
    assess,
    sampleRecentBlocks,
    measuredBlockTime,
    formatAge,
    EXPECTED_BLOCK_TIME,
    EXPECTED_CHAIN_ID,
    STALL_CRIT_SECONDS,
};
