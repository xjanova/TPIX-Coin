/**
 * กุญแจผ่านด่านยืนยันซอร์สของ explorer.tpix.online
 *
 * ตั้งแต่ 2026-10-27 nginx หน้า Blockscout ปิดช่อง verify สาธารณะ (infrastructure/blockscout/08-tpix-verify-gate.conf)
 * — การยืนยันซอร์สเป็นบริการเสียเงินของ Token Factory บน tpix.online
 * POST ไป /api/v2/smart-contracts/<addr>/verification/... หรือ /api/ แบบ etherscan
 * ที่ไม่มี header นี้ = 403 · อ่านสถานะ (GET) ใช้ได้ตามปกติไม่ต้องมีกุญแจ
 *
 * ทีมที่ verify สัญญาของระบบเองตั้ง env TPIX_VERIFY_KEY
 * (ค่าเดียวกับ BLOCKSCOUT_VERIFY_KEY ใน .env ของ tpix.online — ขอจากเจ้าของ ห้าม commit)
 */

const VERIFY_KEY_HEADER = "X-TPIX-Verify-Key";

/** header สำหรับคำขอ verify — ไม่มีกุญแจ = หยุดก่อนส่ง จะได้ไม่ไปเจอ 403 กลางทาง */
function verifyKeyHeaders() {
    const key = (process.env.TPIX_VERIFY_KEY || process.env.BLOCKSCOUT_VERIFY_KEY || "").trim();
    if (!key) {
        throw new Error(
            "ไม่ได้ตั้ง TPIX_VERIFY_KEY — explorer ปิดช่อง verify สาธารณะแล้ว " +
                "(ค่าเดียวกับ BLOCKSCOUT_VERIFY_KEY ใน .env ของ tpix.online)",
        );
    }
    return { [VERIFY_KEY_HEADER]: key };
}

/** ข้อความอธิบายเมื่อด่านตอบ 403 — กุญแจผิด/หมดอายุ ไม่ใช่ปัญหาซอร์สโค้ด */
function gateRejected(status) {
    return status === 403
        ? "explorer ปฏิเสธ (403) — TPIX_VERIFY_KEY ไม่ตรงกับ /etc/nginx/tpix-verify-key.map บนเครื่อง explorer"
        : null;
}

module.exports = { VERIFY_KEY_HEADER, verifyKeyHeaders, gateRejected };
