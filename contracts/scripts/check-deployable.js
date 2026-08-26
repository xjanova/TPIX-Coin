/**
 * ตรวจว่า bytecode ที่คอมไพล์ออกมา "deploy ขึ้นเชน TPIX ได้จริงไหม" — โดยไม่ต้องมีคีย์
 *
 * วิธี: ยิง eth_estimateGas แบบ contract creation (ไม่มี field `to`) ไปที่ RPC ของเชนจริง
 * โหนดจะรัน constructor ให้จริง ๆ ถ้าเจอโอปโค้ดที่ไม่รู้จักจะตอบ "opcode not found"
 * เป็นการอ่านอย่างเดียว ไม่มีการเซ็น ไม่มี tx ขึ้นเชน
 *
 * ทำไมต้องมี: เชน TPIX = Polygon Edge v0.9.0 ที่ fork สูงสุดแค่ london
 * แต่ solc 0.8.20+ ตั้งต้นเป็น shanghai ซึ่งปล่อย PUSH0 ออกมา
 * สแกน bytecode เองไม่พอ เพราะ contract ที่ฝัง creationCode ของ contract อื่นไว้ข้างใน
 * จะถูกอ่านไบต์ข้อมูลเป็นโอปโค้ดจนแจ้งผิดพลาด — ถามเชนตรง ๆ จบเรื่อง
 *
 *   node scripts/check-deployable.js [rpcUrl]
 */
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

// rpc1 ไม่ใช่ rpc — rpc.tpix.online มี Cloudflare bot rule ที่ตอบ 403 ให้ client ที่ไม่มี UA
const RPC = process.argv[2] || process.env.TPIX_RPC_URL || "https://rpc1.tpix.online";

// กระเป๋าที่มียอดตั้งแต่ genesis — ใช้เป็น `from` เฉย ๆ ไม่มีการเซ็นอะไร
const FROM = "0xf54c0deE404ec728a03b467cba7bBA171CC77dad";

const ART = path.join(__dirname, "..", "artifacts", "src");

/** ค่าตัวอย่างของ constructor แต่ละสัญญา (แค่ให้ constructor รันผ่าน ไม่ได้ใช้จริง) */
const ZERO = "0x0000000000000000000000000000000000000000";
const SAMPLE = "0x1111111111111111111111111111111111111111";
const CTOR_ARGS = {
    ValidatorKYC: [ethers.keccak256(ethers.toUtf8Bytes("consent"))],
    TPIXTokenFactoryV2: [SAMPLE, SAMPLE, SAMPLE, SAMPLE, SAMPLE],
    TPIXNFTFactory: [SAMPLE, SAMPLE],
    TPIXDEXFactory: [SAMPLE],
    TPIXDEXRouter02: [SAMPLE, SAMPLE],
    TPIXRouter: [SAMPLE, SAMPLE, SAMPLE, SAMPLE],
    ValidatorGovernance: [SAMPLE],
    // TPIXBondingCurve(tpix, usdt, liquidityWallet, supply, startPrice, endPrice, raiseTarget, sellTarget)
    TPIXBondingCurve: [SAMPLE, SAMPLE, SAMPLE, 10n ** 26n, 10n ** 17n, 10n ** 18n, 5_000_000n * 10n ** 6n, 35n * 10n ** 25n],
};

function walk(dir, out = []) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith(".json") && !e.name.endsWith(".dbg.json")) out.push(p);
    }
    return out;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * ยิง JSON-RPC พร้อม retry
 * ถ้ายิงถี่ไป Cloudflare จะตอบหน้า HTML กลับมาแทน JSON — ต้องจับไว้ ไม่งั้นสคริปต์ตายกลางคัน
 * แล้วเราจะเข้าใจผิดว่า "ตรวจครบแล้ว" ทั้งที่ตรวจไปได้ครึ่งเดียว
 */
async function rpc(method, params, attempt = 0) {
    const res = await fetch(RPC, {
        method: "POST",
        headers: { "Content-Type": "application/json", "User-Agent": "TPIX-deploy-check/1.0" },
        body: JSON.stringify({ jsonrpc: "2.0", method, params, id: 1 }),
    });
    const text = await res.text();
    try {
        return JSON.parse(text);
    } catch {
        // 413 = ตัว proxy หน้า RPC จำกัดขนาด body ไม่ใช่ปัญหาของเชน
        // สัญญาที่ฝัง creationCode ของสัญญาอื่นไว้ข้างในจะตัวใหญ่จนชนลิมิตนี้
        if (/413|Request Entity Too Large/i.test(text)) {
            return { __tooLarge: true };
        }
        if (attempt < 4) {
            await sleep(1500 * (attempt + 1));
            return rpc(method, params, attempt + 1);
        }
        throw new Error(`RPC ตอบไม่ใช่ JSON หลังลอง ${attempt + 1} ครั้ง (น่าจะโดน rate limit): ${text.slice(0, 80)}`);
    }
}

async function main() {
    const net = await rpc("web3_clientVersion", []);
    console.log("RPC     :", RPC);
    console.log("client  :", net.result);
    console.log("─".repeat(72));

    // EIP-170: โค้ดที่ลงเชนได้ต้องไม่เกิน 24,576 ไบต์ (Polygon Edge ใช้ค่าเริ่มต้นนี้
    // เพราะ genesis ไม่ได้ตั้ง params.contractSizeLimit ทับ)
    const EIP170 = 24576;

    let ok = 0, blocked = 0, skipped = 0, oversize = 0;

    for (const file of walk(ART)) {
        const a = JSON.parse(fs.readFileSync(file, "utf8"));
        if (!a.bytecode || a.bytecode === "0x") continue;
        if (a.bytecode.includes("__$")) { skipped++; continue; } // library ต้อง link ก่อน

        // ตรวจขนาดโค้ดก่อน — ตัวใหญ่เกิน EIP-170 deploy ไม่ขึ้นไม่ว่าโอปโค้ดจะถูกแค่ไหน
        const runtimeBytes = ((a.deployedBytecode || "0x").length - 2) / 2;
        if (runtimeBytes > EIP170) {
            oversize++;
            console.log("ใหญ่เกินลิมิต", a.contractName,
                `${runtimeBytes.toLocaleString()} ไบต์ > ${EIP170.toLocaleString()} (EIP-170)`);
            continue;
        }

        const ctor = (a.abi || []).find((x) => x.type === "constructor");
        const inputs = ctor ? ctor.inputs : [];
        let data = a.bytecode;

        if (inputs.length) {
            const args = CTOR_ARGS[a.contractName];
            if (!args || args.length !== inputs.length) {
                console.log("ข้าม        ", a.contractName, `(constructor ${inputs.length} args — ไม่มีค่าตัวอย่าง)`);
                skipped++;
                continue;
            }
            data += ethers.AbiCoder.defaultAbiCoder()
                .encode(inputs.map((i) => i.type), args).slice(2);
        }

        await sleep(250); // เว้นจังหวะไม่ให้โดน rate limit
        const r = await rpc("eth_estimateGas", [{ from: FROM, data, gasPrice: "0x0" }]);

        if (r.__tooLarge) {
            // ถามเชนไม่ได้เพราะ proxy ตัด แต่ขนาดโค้ดผ่าน EIP-170 แล้ว
            // และคอมไพล์ด้วย evmVersion london จึงไม่มีทางมี PUSH0/MCOPY
            skipped++;
            console.log("ถาม RPC ไม่ได้", a.contractName,
                `(body ${(data.length / 2 / 1024).toFixed(0)}KB เกินลิมิตของ proxy — ตรวจตอน deploy จริงแทน)`);
            continue;
        }

        const err = r.error?.message || "";

        // "opcode not found" = โอปโค้ดที่เชนไม่รู้จัก (PUSH0/MCOPY/TSTORE) → deploy ไม่ได้แน่นอน
        if (/opcode not found|invalid opcode/i.test(err)) {
            blocked++;
            console.log("DEPLOY ไม่ได้", a.contractName, "→", err);
        } else if (r.error) {
            // error อื่น (gas/limit) แปลว่าโค้ดผ่านด่านโอปโค้ดแล้ว
            ok++;
            console.log("ผ่านโอปโค้ด ", a.contractName, `(${err.slice(0, 48)})`);
        } else {
            ok++;
            console.log("deploy ได้   ", a.contractName, "gas", parseInt(r.result, 16).toLocaleString());
        }
    }

    console.log("─".repeat(72));
    console.log(`ผ่าน ${ok} · deploy ไม่ได้ ${blocked} · ใหญ่เกินลิมิต ${oversize} · ข้าม ${skipped}`);
    if (blocked > 0 || oversize > 0) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
