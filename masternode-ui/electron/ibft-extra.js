/**
 * ibft-extra.js — อ่านรายชื่อ validator ออกจาก extraData ของบล็อก IBFT
 *
 * ══════════════════════════════════════════════════════════════════════════════
 *  ทำไมต้องถอดเอง ไม่เรียก RPC ตรงๆ
 * ══════════════════════════════════════════════════════════════════════════════
 *
 *  polygon-edge v0.9.0 ที่เชน TPIX ใช้อยู่ **ไม่มี** เมธอดตระกูล `ibft_*` เลย
 *  ยืนยันกับเชนจริง 2026-08-11:
 *
 *      ibft_getValidatorsByBlockNumber → -32601 the method does not exist
 *      ibft_getSnapshot               → -32601
 *      ibft_status                    → -32601
 *
 *  เดิม chain-health.js เรียก `ibft_getValidatorsByBlockNumber` แล้ว catch เงียบๆ
 *  ผลคือ `validators` เป็น null ตลอดกาล → ตรรกะ "หา validator ที่หายไป" ไม่เคยทำงาน
 *  สักครั้งเดียวนับตั้งแต่เขียนมา และไม่มีใครเห็นเพราะมันล้มแบบไม่ส่งเสียง
 *
 *  ข้อมูลชุดเดียวกันอยู่ใน `extraData` ของทุกบล็อกอยู่แล้ว จึงถอดจากตรงนั้นแทน
 *  ใช้ได้กับทุกโหนดโดยไม่ต้องพึ่ง allow-list ของ nginx และไม่ต้องรอเปิดเมธอดเพิ่ม
 *
 *  รูปแบบข้อมูล (polygon-edge IBFT):
 *      [0:32]  vanity
 *      [32:]   RLP([ validators[], proposerSeal, committedSeals[], ... ])
 *
 *  สมาชิกใน validators[] เป็นได้ 2 แบบ
 *      - ที่อยู่เปล่า 20 ไบต์            (validator_type: ecdsa)
 *      - ลิสต์ [address, blsPubKey]      (validator_type: bls ← เชน TPIX ใช้แบบนี้)
 */

'use strict';

/**
 * อ่านหัว RLP หนึ่งตัวที่ตำแหน่ง p
 * @returns {{ds:number, dl:number, tl:number}} ds=จุดเริ่มข้อมูล dl=ความยาวข้อมูล tl=ความยาวรวมทั้งหัว
 */
function readRlpHeader(b, p) {
    const x = b[p];
    if (x === undefined) throw new Error('RLP: อ่านเกินท้ายบัฟเฟอร์');

    if (x <= 0x7f) return { ds: p, dl: 1, tl: 1 };
    if (x <= 0xb7) { const l = x - 0x80; return { ds: p + 1, dl: l, tl: 1 + l }; }
    if (x <= 0xbf) {
        const n = x - 0xb7;
        let l = 0;
        for (let i = 0; i < n; i++) l = l * 256 + b[p + 1 + i];

        return { ds: p + 1 + n, dl: l, tl: 1 + n + l };
    }
    if (x <= 0xf7) { const l = x - 0xc0; return { ds: p + 1, dl: l, tl: 1 + l }; }

    const n = x - 0xf7;
    let l = 0;
    for (let i = 0; i < n; i++) l = l * 256 + b[p + 1 + i];

    return { ds: p + 1 + n, dl: l, tl: 1 + n + l };
}

const isRlpList = (b, p) => b[p] >= 0xc0;

/**
 * ถอดรายชื่อ validator ออกจาก extraData
 *
 * @param {string} extraData — hex ขึ้นต้นด้วย 0x
 * @returns {string[]} ที่อยู่ validator ตัวพิมพ์เล็ก (ลิสต์ว่างถ้าถอดไม่ได้)
 */
function decodeValidators(extraData) {
    if (typeof extraData !== 'string' || extraData.length <= 66) return [];

    try {
        const buf = Buffer.from(extraData.slice(2), 'hex');
        if (buf.length <= 32) return [];

        const outer = readRlpHeader(buf, 32);      // ลิสต์นอกสุด
        const valList = readRlpHeader(buf, outer.ds); // สมาชิกตัวแรก = ลิสต์ validator
        if (!isRlpList(buf, outer.ds)) return [];

        const out = [];
        let pos = valList.ds;
        const end = Math.min(valList.ds + valList.dl, buf.length);

        while (pos < end) {
            const item = readRlpHeader(buf, pos);
            if (item.tl <= 0) break; // กันลูปไม่รู้จบเมื่อข้อมูลเพี้ยน

            if (isRlpList(buf, pos)) {
                // [address, blsPubKey] — เอาตัวแรก
                const inner = readRlpHeader(buf, item.ds);
                if (inner.dl === 20) {
                    out.push('0x' + buf.slice(inner.ds, inner.ds + 20).toString('hex'));
                }
            } else if (item.dl === 20) {
                out.push('0x' + buf.slice(item.ds, item.ds + 20).toString('hex'));
            }

            pos += item.tl;
        }

        return out;
    } catch {
        return [];
    }
}

module.exports = { decodeValidators };
