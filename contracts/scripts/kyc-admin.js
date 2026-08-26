/**
 * ValidatorKYC — เครื่องมือฝั่งทีมงาน (owner เท่านั้น)
 *
 * ชั้น Validator ใน NodeRegistryV2 ลงทะเบียนไม่ได้จนกว่าจะผ่าน KYC ครบ 3 ขั้น:
 *   1. ผู้สมัครกด giveConsent() เอง  ← ทำบนเว็บที่ /masternode (PDPA ทีมงานกดแทนไม่ได้)
 *   2. ทีมงาน submitKYC(applicant, hash)   ← สคริปต์นี้
 *   3. ทีมงาน approveKYC(applicant)        ← สคริปต์นี้
 *
 * คีย์ owner อยู่บนเครื่องคนสั่งเท่านั้น ไม่ต้องเอาขึ้นเซิร์ฟเวอร์
 *
 * ── วิธีใช้ ─────────────────────────────────────────────────────────
 *   export DEPLOYER_KEY=0x...                 # กระเป๋า owner ของ ValidatorKYC
 *   export KYC_ADDRESS=0x...                  # ที่อยู่สัญญา ValidatorKYC
 *
 *   # ดูสถานะผู้สมัคร
 *   KYC_ACTION=status KYC_APPLICANT=0xabc... npx hardhat run scripts/kyc-admin.js --network tpix
 *
 *   # ดูรายชื่อผู้สมัครทั้งหมด
 *   KYC_ACTION=list npx hardhat run scripts/kyc-admin.js --network tpix
 *
 *   # บันทึกเอกสารเข้าระบบ (hash ของชุดเอกสารที่เข้ารหัสแล้ว)
 *   KYC_ACTION=submit KYC_APPLICANT=0xabc... KYC_DOC_HASH=0x<32bytes> \
 *     npx hardhat run scripts/kyc-admin.js --network tpix
 *
 *   # อนุมัติ / ปฏิเสธ
 *   KYC_ACTION=approve KYC_APPLICANT=0xabc... npx hardhat run scripts/kyc-admin.js --network tpix
 *   KYC_ACTION=reject  KYC_APPLICANT=0xabc... KYC_REASON="เอกสารไม่ครบ" \
 *     npx hardhat run scripts/kyc-admin.js --network tpix
 */
const { ethers, network } = require("hardhat");

const STATUS = ["None", "ConsentGiven", "Submitted", "Approved", "Rejected", "Revoked"];

const ABI = [
    "function owner() view returns (address)",
    "function consentTextHash() view returns (bytes32)",
    "function getApplicantCount() view returns (uint256)",
    "function applicants(uint256) view returns (address)",
    "function getRecord(address) view returns (tuple(address applicant, uint8 status, bytes32 kycHash, uint256 consentAt, uint256 submittedAt, uint256 reviewedAt, address reviewer, string rejectReason))",
    "function isApproved(address) view returns (bool)",
    "function submitKYC(address _applicant, bytes32 _kycHash)",
    "function approveKYC(address _applicant)",
    "function rejectKYC(address _applicant, string _reason)",
];

function requireAddress(value, label) {
    if (!value || !ethers.isAddress(value)) {
        throw new Error(`${label} ต้องเป็นแอดเดรสที่ถูกต้อง (ได้: ${value || "ว่าง"})`);
    }
    return ethers.getAddress(value);
}

function fmtTime(seconds) {
    const n = Number(seconds);
    return n === 0 ? "—" : new Date(n * 1000).toISOString().replace("T", " ").slice(0, 19) + " UTC";
}

async function printRecord(kyc, applicant) {
    const r = await kyc.getRecord(applicant);
    console.log("  applicant   :", r.applicant === ethers.ZeroAddress ? "(ไม่เคยยื่น)" : r.applicant);
    console.log("  status      :", STATUS[Number(r.status)] ?? `unknown(${r.status})`);
    console.log("  consentAt   :", fmtTime(r.consentAt));
    console.log("  submittedAt :", fmtTime(r.submittedAt));
    console.log("  reviewedAt  :", fmtTime(r.reviewedAt));
    if (r.rejectReason) console.log("  rejectReason:", r.rejectReason);
    console.log("  isApproved  :", await kyc.isApproved(applicant));
}

async function main() {
    const action = (process.env.KYC_ACTION || "status").toLowerCase();
    const kycAddress = requireAddress(process.env.KYC_ADDRESS, "KYC_ADDRESS");

    const [signer] = await ethers.getSigners();
    if (!signer) throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน");

    // เชนนี้ค่าแก๊สเป็น 0 แต่ยังต้องมีบัญชีอยู่จริง
    const kyc = new ethers.Contract(kycAddress, ABI, signer);

    const code = await ethers.provider.getCode(kycAddress);
    if (code === "0x") {
        throw new Error(`ไม่มีโค้ดสัญญาที่ ${kycAddress} บนเครือข่าย ${network.name} — deploy ก่อน`);
    }

    const owner = await kyc.owner();
    console.log("─".repeat(64));
    console.log("network  :", network.name);
    console.log("KYC      :", kycAddress);
    console.log("owner    :", owner);
    console.log("signer   :", signer.address);
    console.log("─".repeat(64));

    // อ่านอย่างเดียวไม่ต้องเป็น owner
    if (action === "list") {
        const count = Number(await kyc.getApplicantCount());
        console.log(`ผู้สมัครทั้งหมด ${count} ราย\n`);
        for (let i = 0; i < count; i++) {
            const a = await kyc.applicants(i);
            const r = await kyc.getRecord(a);
            console.log(`  ${String(i + 1).padStart(3)}. ${a}  ${STATUS[Number(r.status)]}`);
        }
        return;
    }

    const applicant = requireAddress(process.env.KYC_APPLICANT, "KYC_APPLICANT");

    if (action === "status") {
        await printRecord(kyc, applicant);
        return;
    }

    // ── ทุกอย่างที่เหลือเป็น onlyOwner ─────────────────────────────
    if (owner.toLowerCase() !== signer.address.toLowerCase()) {
        throw new Error(
            `signer ไม่ใช่ owner ของสัญญานี้ — ต้องใช้คีย์ของ ${owner}\n` +
            `(ตอนนี้ DEPLOYER_KEY เป็นของ ${signer.address})`
        );
    }

    const before = await kyc.getRecord(applicant);
    console.log("ก่อนทำรายการ:");
    await printRecord(kyc, applicant);
    console.log("");

    let tx;
    switch (action) {
        case "submit": {
            if (Number(before.status) !== 1) {
                throw new Error(
                    `ผู้สมัครต้องอยู่สถานะ ConsentGiven ก่อน (ตอนนี้ ${STATUS[Number(before.status)]})\n` +
                    `ให้ผู้สมัครเข้า /masternode แล้วกด "ให้ความยินยอม PDPA" ด้วยกระเป๋าตัวเองก่อน`
                );
            }
            const hash = process.env.KYC_DOC_HASH;
            if (!hash || !/^0x[0-9a-fA-F]{64}$/.test(hash)) {
                throw new Error("ต้องตั้ง KYC_DOC_HASH เป็น keccak256 ของชุดเอกสาร (0x + 64 hex)");
            }
            tx = await kyc.submitKYC(applicant, hash, { gasPrice: 0 });
            break;
        }
        case "approve": {
            if (Number(before.status) !== 2) {
                throw new Error(
                    `ต้อง submitKYC ก่อนอนุมัติ (ตอนนี้ ${STATUS[Number(before.status)]})`
                );
            }
            tx = await kyc.approveKYC(applicant, { gasPrice: 0 });
            break;
        }
        case "reject": {
            const reason = process.env.KYC_REASON || "";
            if (!reason) throw new Error("ต้องตั้ง KYC_REASON บอกเหตุผลที่ไม่ผ่าน");
            tx = await kyc.rejectKYC(applicant, reason, { gasPrice: 0 });
            break;
        }
        default:
            throw new Error(`ไม่รู้จัก KYC_ACTION=${action} (ใช้ได้: status | list | submit | approve | reject)`);
    }

    console.log("ส่ง tx:", tx.hash);
    await tx.wait();
    console.log("ยืนยันแล้ว\n");
    console.log("หลังทำรายการ:");
    await printRecord(kyc, applicant);
}

main()
    .then(() => process.exit(0))
    .catch((e) => {
        console.error("\n❌", e.message);
        process.exit(1);
    });
