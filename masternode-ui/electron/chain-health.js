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
 *  เชนจึงวิ่งด้วย 3/4 = quorum พอดี **ไม่มี fault tolerance เหลือเลย**
 *  ตัวไหนสะดุดอีกตัวเดียว เชนหยุดทันที
 *
 *  ที่มันซ่อนอยู่ได้นานเพราะเครื่องมือเดิมถามผิดคำถาม:
 *    - health-check.yml (ทุก 4 ชม.)  ถาม "ออกบล็อกไหม" → ออก จึงตอบว่าปกติ
 *    - chain-watchdog.sh              รีสตาร์ทเมื่อ "หยุด" → ช่องว่าง 14s ไม่นับว่าหยุด
 *    - ไม่มีอะไรวัด "บล็อกช้าลงจากที่ควรเป็น" หรือ "validator ไหนหายไปจากคิว"
 *
 *  ไฟล์นี้ถามคำถามที่ถูก แล้วบอกผู้ใช้ตรงๆ
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  หมายเหตุเรื่อง RPC
 * ══════════════════════════════════════════════════════════════════════════════
 *  ต้องเรียกผ่าน rpc-client.js เท่านั้น (มี browser UA + circuit breaker)
 *  เพราะ Cloudflare WAF บล็อกคำขอที่ไม่มี User-Agent — ดูโน้ต 2026-06-19
 *
 *  `ibft_getValidatorsByBlockNumber` เพิ่งถูกเพิ่มเข้า allow-list ของ nginx
 *  เมื่อ 2026-08-05 (ก่อนหน้านั้นได้ 403 มาตลอดโดยไม่มีใครทัก) ถ้ายังได้ 403
 *  แปลว่า nginx-rpc.conf บนเซิร์ฟเวอร์ยังไม่ได้ reload
 */

'use strict';

const { rpcCall } = require('./rpc-client');

/** blockTime ที่ genesis ตั้งไว้ (วินาที) — ใช้เป็นฐานเทียบ ไม่ใช่ค่าที่เชื่อว่าเป็นจริง */
const EXPECTED_BLOCK_TIME = 2;

/** ช้ากว่าที่ควรเกินกี่เท่าถึงถือว่าผิดปกติ */
const SLOW_RATIO_WARN = 1.5;
const SLOW_RATIO_CRIT = 2.5;

/** ช่องว่างระหว่างบล็อกที่ถือว่า "รอบนั้นหมดเวลา" ไม่ใช่แค่ช้า */
const ROUND_TIMEOUT_HINT = EXPECTED_BLOCK_TIME * 4;

/** จำนวนบล็อกที่สุ่มมาวัด — มากพอให้เห็นรูปแบบ น้อยพอไม่ถล่ม RPC */
const DEFAULT_SAMPLE = 40;

const hexToInt = (h) => (typeof h === 'string' ? parseInt(h, 16) : Number(h));

/**
 * ดึง timestamp ของบล็อก N ก้อนล่าสุด แล้วคำนวณช่องว่างระหว่างกัน
 *
 * @returns {Promise<{blocks: Array<{height:number,ts:number}>, gaps:number[]}>}
 */
async function sampleRecentBlocks(sampleSize = DEFAULT_SAMPLE) {
    const tipHex = await rpcCall('eth_blockNumber');
    const tip = hexToInt(tipHex);
    if (!Number.isFinite(tip) || tip <= 0) {
        throw new Error('อ่าน eth_blockNumber ไม่ได้');
    }

    const from = Math.max(0, tip - sampleSize + 1);
    const blocks = [];

    // ดึงทีละก้อนแบบต่อเนื่อง — rpc-client มี rate limit + circuit breaker อยู่แล้ว
    // ไม่ยิงขนานเพื่อไม่ให้ชน limit_req ของ nginx (30r/s burst 60)
    for (let h = from; h <= tip; h++) {
        const b = await rpcCall('eth_getBlockByNumber', ['0x' + h.toString(16), false]);
        if (!b || !b.timestamp) continue;
        blocks.push({ height: hexToInt(b.number), ts: hexToInt(b.timestamp) });
    }

    blocks.sort((a, b) => a.height - b.height);

    const gaps = [];
    for (let i = 1; i < blocks.length; i++) {
        gaps.push(blocks[i].ts - blocks[i - 1].ts);
    }

    return { tip, blocks, gaps };
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
        missingProposers: null,
        tip: null,
    };

    let sample;
    try {
        sample = await sampleRecentBlocks(sampleSize);
    } catch (err) {
        report.severity = 'critical';
        report.messages.push({
            level: 'critical',
            text: 'ติดต่อเชนไม่ได้: ' + err.message,
        });

        return report;
    }

    report.tip = sample.tip;

    if (sample.gaps.length === 0) {
        report.severity = 'unknown';
        report.messages.push({ level: 'warn', text: 'ตัวอย่างบล็อกไม่พอสำหรับวิเคราะห์' });

        return report;
    }

    // ── 1. blockTime จริงเทียบกับที่ควรเป็น ────────────────────────────────────
    const avg = sample.gaps.reduce((a, b) => a + b, 0) / sample.gaps.length;
    report.actualBlockTime = Number(avg.toFixed(2));
    report.slowRatio = Number((avg / EXPECTED_BLOCK_TIME).toFixed(2));

    // ── 2. นับรอบที่หมดเวลา (ช่องว่างยาวผิดปกติ) ───────────────────────────────
    const timeoutGaps = sample.gaps.filter((g) => g >= ROUND_TIMEOUT_HINT);
    report.timeouts = timeoutGaps.length;

    // ── 3. peer count ─────────────────────────────────────────────────────────
    try {
        report.peerCount = hexToInt(await rpcCall('net_peerCount'));
    } catch {
        report.peerCount = null;
    }

    // ── 4. validator set ──────────────────────────────────────────────────────
    try {
        const vals = await rpcCall('ibft_getValidatorsByBlockNumber', ['latest']);
        if (Array.isArray(vals)) {
            report.validators = vals.length;
        }
    } catch (err) {
        report.messages.push({
            level: 'info',
            text: 'อ่านรายชื่อ validator ไม่ได้ (' + err.message + ') — '
                + 'ถ้าเป็น 403 แปลว่า nginx-rpc.conf บนเซิร์ฟเวอร์ยังไม่ได้ reload '
                + 'หลังเพิ่ม ibft_* เข้า allow-list',
        });
    }

    // ── 5. ประมาณว่ามี proposer หายไปกี่ตัว ────────────────────────────────────
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
            report.messages.push({
                level,
                text: `คาดว่ามี validator ประมาณ ${estimated} ตัวจาก ${report.validators} `
                    + `ไม่ propose บล็อก (พบช่องว่างที่หมดเวลา ${report.timeouts} ครั้ง `
                    + `ใน ${sample.gaps.length} ช่วง)`
                    + (estimated >= faultBudget
                        ? ` — IBFT ชุดนี้ทนพังได้แค่ ${faultBudget} ตัว `
                          + 'เท่ากับไม่เหลือ fault tolerance แล้ว ตัวไหนสะดุดอีกตัวเชนหยุด'
                        : ''),
            });
            if (level === 'critical') report.severity = 'critical';
        }
    }

    // ── 6. สรุประดับความรุนแรงจาก blockTime ────────────────────────────────────
    if (report.slowRatio >= SLOW_RATIO_CRIT) {
        report.severity = 'critical';
        report.messages.push({
            level: 'critical',
            text: `บล็อกช้ากว่าที่ตั้งไว้ ${report.slowRatio} เท่า `
                + `(จริง ${report.actualBlockTime}s / ควรเป็น ${EXPECTED_BLOCK_TIME}s)`,
        });
    } else if (report.slowRatio >= SLOW_RATIO_WARN) {
        if (report.severity !== 'critical') report.severity = 'warn';
        report.messages.push({
            level: 'warn',
            text: `บล็อกช้ากว่าที่ตั้งไว้ ${report.slowRatio} เท่า `
                + `(จริง ${report.actualBlockTime}s / ควรเป็น ${EXPECTED_BLOCK_TIME}s)`,
        });
    }

    if (report.peerCount !== null && report.peerCount < 2) {
        report.severity = 'critical';
        report.messages.push({
            level: 'critical',
            text: `peer เหลือ ${report.peerCount} — โหนดกำลังหลุดจากเครือข่าย`,
        });
    }

    if (report.severity === 'unknown') report.severity = 'ok';
    report.ok = report.severity === 'ok';

    if (report.ok) {
        report.messages.push({
            level: 'info',
            text: `เชนปกติ — บล็อก ${report.actualBlockTime}s, peer ${report.peerCount}`,
        });
    }

    return report;
}

/**
 * blockTime จริงที่วัดได้ พร้อม cache — ใช้แทนการ hardcode 2 วินาที
 *
 * เดิม node-manager.js ใช้ `BLOCK_TIME = 2` ประมาณ block number ตอน RPC ล่ม:
 *     blockNumber = last_reward_block + Math.floor(elapsedSeconds / BLOCK_TIME)
 * ซึ่งบนเชนจริงที่บล็อกออกทุก 6 วินาที จะ**ประมาณเกินไป 3 เท่า**
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
    EXPECTED_BLOCK_TIME,
};
