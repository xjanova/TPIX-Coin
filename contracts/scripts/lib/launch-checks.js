/**
 * ด่านตรวจของ scripts/launch-token.js — แยกไว้ให้เทสต์ได้ (test/LaunchScriptChecks.test.js)
 *
 * ทุกฟังก์ชันคืน "รายการปัญหา" (array ของข้อความ) — ว่าง = ผ่าน · สคริปต์เป็นคนตัดสินว่าจะหยุดหรือไม่
 *
 * ทำไมต้องมี (ออดิทก่อน deploy 2026-10-11): รันซ้ำโดยแก้ BENEFICIARY / VESTING_START / SALE_TREASURY
 * สคริปต์เดิมพิมพ์ค่าใหม่ แต่หยิบสัญญาเดิมใน registry มาใช้ (เทียบแค่ token กับยอดรวม)
 * แล้วบอกให้โอน 770B เข้าสัญญาล็อกที่ยังจ่ายให้ผู้รับเดิมตามวันเริ่มเดิม — โอนแล้วแก้ไม่ได้
 */

const same = (x, y) => String(x).toLowerCase() === String(y).toLowerCase();
const big = (v) => BigInt(v);

/** สัญญาล็อกที่มีอยู่แล้วตรงกับค่าที่ตั้งไว้ทุกตัวไหม */
async function vestingMismatches(vesting, exp) {
    const out = [];
    const [token, beneficiary, start, period, count, label] = await Promise.all([
        vesting.token(), vesting.beneficiary(), vesting.start(), vesting.period(), vesting.trancheCount(), vesting.label(),
    ]);
    if (!same(token, exp.token)) out.push(`token: บนเชน ${token} ≠ ที่ตั้ง ${exp.token}`);
    if (!same(beneficiary, exp.beneficiary)) out.push(`beneficiary (ผู้รับ): บนเชน ${beneficiary} ≠ ที่ตั้ง ${exp.beneficiary}`);
    if (big(start) !== big(exp.start)) out.push(`start (วันเริ่มนับ): บนเชน ${start} ≠ ที่ตั้ง ${exp.start}`);
    if (big(period) !== big(exp.period)) out.push(`period: บนเชน ${period} ≠ ที่ตั้ง ${exp.period}`);
    if (label !== exp.label) out.push(`label: บนเชน "${label}" ≠ ที่ตั้ง "${exp.label}"`);
    if (Number(count) !== exp.tranches.length) {
        out.push(`tranche count: บนเชน ${count} ก้อน ≠ ที่ตั้ง ${exp.tranches.length} ก้อน`);
        return out;
    }
    for (let i = 0; i < exp.tranches.length; i++) {
        const t = await vesting.tranche(i);
        const e = exp.tranches[i];
        if (big(t.amount) !== big(e.amount) || Number(t.cliffPeriods) !== Number(e.cliffPeriods)
            || Number(t.releasePeriods) !== Number(e.releasePeriods)) {
            out.push(`tranche ${i}: บนเชน ${t.amount}/${t.cliffPeriods}/${t.releasePeriods} ≠ ที่ตั้ง ${e.amount}/${e.cliffPeriods}/${e.releasePeriods}`);
        }
    }
    return out;
}

/** presale ที่มีอยู่แล้วตรงกับค่าที่ตั้งไว้ทุกตัวไหม (รวมค่าที่เจ้าของแก้ได้ — ให้คนตัดสินใจเอง ไม่ใช้ของเดิมเงียบ ๆ) */
async function saleMismatches(sale, exp) {
    const out = [];
    const [saleToken, payToken, num, den, cap, treasury, start, end, owner] = await Promise.all([
        sale.saleToken(), sale.payToken(), sale.rateNumerator(), sale.rateDenominator(), sale.saleCap(),
        sale.treasury(), sale.startTime(), sale.endTime(), sale.owner(),
    ]);
    if (!same(saleToken, exp.saleToken)) out.push(`saleToken: บนเชน ${saleToken} ≠ ที่ตั้ง ${exp.saleToken}`);
    if (!same(payToken, exp.payToken)) out.push(`payToken: บนเชน ${payToken} ≠ ที่ตั้ง ${exp.payToken}`);
    if (big(num) !== big(exp.num) || big(den) !== big(exp.den)) out.push(`rate: บนเชน ${num}/${den} ≠ ที่ตั้ง ${exp.num}/${exp.den} (แก้ไม่ได้ ต้อง deploy ใหม่)`);
    if (big(cap) !== big(exp.cap)) out.push(`saleCap: บนเชน ${cap} ≠ ที่ตั้ง ${exp.cap} (แก้ไม่ได้ ต้อง deploy ใหม่)`);
    if (!same(treasury, exp.treasury)) out.push(`treasury (รับเงิน): บนเชน ${treasury} ≠ ที่ตั้ง ${exp.treasury}`);
    if (big(start) !== big(exp.start)) out.push(`startTime: บนเชน ${start} ≠ ที่ตั้ง ${exp.start}`);
    if (big(end) !== big(exp.end)) out.push(`endTime: บนเชน ${end} ≠ ที่ตั้ง ${exp.end}`);
    if (!same(owner, exp.owner)) out.push(`owner (ผู้คุม): บนเชน ${owner} ≠ ที่ตั้ง ${exp.owner}`);
    return out;
}

/** ตัด CBOR metadata ท้ายโค้ด (ความยาวอยู่ใน 2 ไบต์สุดท้าย) — metadata เปลี่ยนตามคอมเมนต์ ไม่ใช่โค้ดที่รันจริง */
function stripMetadata(hex) {
    const h = hex.startsWith("0x") ? hex.slice(2) : hex;
    const n = parseInt(h.slice(-4), 16);
    return Number.isFinite(n) && (n + 2) * 2 <= h.length ? h.slice(0, h.length - (n + 2) * 2) : h;
}

/** ปิดช่อง immutable (ค่าที่ constructor ฝัง เช่น decimals/flags) เป็น 00 ทั้งสองฝั่งก่อนเทียบ */
function maskImmutables(hex, refs) {
    const chars = hex.split("");
    for (const ranges of Object.values(refs || {})) {
        for (const { start, length } of ranges) {
            for (let i = start * 2; i < (start + length) * 2 && i < chars.length; i++) chars[i] = "0";
        }
    }
    return chars.join("");
}

const FQN = "src/token-factory/FactoryERC20V2.sol:FactoryERC20V2";

/**
 * เหรียญต้องเป็น FactoryERC20V2 จาก build ที่ตรวจแล้ว และเป็นแบบ standard จริง
 * (ไม่มี mint / pause / blacklist / auto-burn) — เดิมสคริปต์แค่พิมพ์ตัวแดงแล้วไปต่อ
 */
async function tokenProblems(token, { artifacts, provider }) {
    const out = [];
    const flag = async (fn) => { try { return await token[fn](); } catch { return null; } };
    const flags = {
        mint: await flag("isMintable"),
        pause: await flag("isPausable"),
        blacklist: await flag("isBlacklistEnabled"),
        "auto-burn": await flag("isAutoBurnEnabled"),
    };
    for (const [k, v] of Object.entries(flags)) {
        if (v === null) out.push(`${k}: เหรียญไม่มีฟังก์ชันบอกสถานะ — ไม่ใช่ FactoryERC20V2`);
        else if (v) out.push(`${k}: เปิดอยู่ — เจ้าของเหรียญยังมีอำนาจ ${k} (แผนนี้ต้องเป็น standard)`);
    }

    const art = await artifacts.readArtifact("FactoryERC20V2");
    const bi = await artifacts.getBuildInfo(FQN);
    const refs = bi?.output?.contracts?.[art.sourceName]?.[art.contractName]?.evm?.deployedBytecode?.immutableReferences;
    const address = token.target ?? (await token.getAddress());
    const onChain = (await provider.getCode(address)).toLowerCase();
    const expected = art.deployedBytecode.toLowerCase();
    const a = stripMetadata(maskImmutables(onChain.slice(2), refs));
    const b = stripMetadata(maskImmutables(expected.slice(2), refs));
    if (!refs || onChain.length !== expected.length || a !== b) {
        out.push(`code: โค้ดบนเชนของ ${address} ไม่ตรงกับ FactoryERC20V2 ที่คอมไพล์จาก repo นี้ (${(onChain.length - 2) / 2} ≠ ${(expected.length - 2) / 2} ไบต์)`);
    }
    return out;
}

module.exports = { vestingMismatches, saleMismatches, tokenProblems, stripMetadata, maskImmutables };
