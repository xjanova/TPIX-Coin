/**
 * ลงทะเบียนที่อยู่สัญญากับเว็บ (ThaiXTrade `/api/infra/contracts`) — ขั้นตอนที่เคยต้องทำมือแล้วลืมบ่อยที่สุด
 *
 * ใช้ร่วมกันทั้ง deploy-all.js และ deploy-dex.js เพื่อไม่ให้สองสคริปต์ยิงคนละแบบ
 *
 *   TPIX_SITE_URL             เช่น https://tpix.online
 *   CONTRACT_REGISTRY_TOKEN   ค่าเดียวกับใน .env ของเว็บ
 *
 * คีย์ที่เว็บรู้จัก (App\Services\ContractRegistry::CONTRACTS):
 *   masternode_registry · validator_kyc · token_factory_v2 · nft_factory · token_factory_v1
 *   wtpix · usdt_tpix · dex_factory · dex_router
 *
 * เว็บตรวจ eth_getCode กับเชนจริงก่อนรับทุกที่อยู่ และจดลายนิ้วมือ bytecode ไว้
 * ย้ายไปสัญญาที่ bytecode ต่างจากเดิมต้องส่ง force=true มาโดยตั้งใจ (REGISTRY_FORCE=1)
 */

/**
 * @param {Record<string,string>} payload  key → address
 * @returns {Promise<boolean>} true = เว็บรับครบทุกตัว
 */
async function registerWithSite(payload) {
    const siteUrl = (process.env.TPIX_SITE_URL || "").replace(/\/+$/, "");
    const token = process.env.CONTRACT_REGISTRY_TOKEN || "";
    const force = process.env.REGISTRY_FORCE === "1";

    const contracts = Object.fromEntries(Object.entries(payload).filter(([, v]) => !!v));
    if (Object.keys(contracts).length === 0) return false;

    if (!siteUrl || !token) {
        console.log("\n[ข้าม] ไม่ได้ตั้ง TPIX_SITE_URL + CONTRACT_REGISTRY_TOKEN");
        console.log("       ตั้งสองตัวนี้แล้วรันใหม่ สคริปต์จะลงทะเบียนที่อยู่ให้เว็บเอง");
        console.log("       (หรือเอาที่อยู่ด้านล่างไปใส่ .env เองก็ได้)");
        return false;
    }

    console.log(`\nลงทะเบียนที่อยู่กับ ${siteUrl} ...`);

    try {
        const res = await fetch(`${siteUrl}/api/infra/contracts`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${token}`,
                "User-Agent": "TPIX-deploy/1.0",
            },
            body: JSON.stringify(force ? { contracts, force: true } : { contracts }),
        });

        const text = await res.text();
        let body;
        try {
            body = JSON.parse(text);
        } catch {
            console.log(`      ❌ เว็บตอบไม่ใช่ JSON (HTTP ${res.status}): ${text.slice(0, 120)}`);
            return false;
        }

        for (const [k, info] of Object.entries(body.applied || {})) {
            const from = info.previous ? ` (เดิม ${info.previous})` : "";
            console.log(`      ✅ ${k} → ${info.address}${from}`);
        }

        if (!res.ok || !body.ok) {
            console.log(`      ❌ ลงทะเบียนไม่ครบ (HTTP ${res.status})`);
            for (const [k, why] of Object.entries(body.rejected || {})) {
                console.log(`         ${k}: ${why}`);
            }
            if (body.error) console.log(`         ${body.error}`);
            if (body.hint) console.log(`         ${body.hint}`);
            return false;
        }

        console.log("      เว็บรับที่อยู่แล้ว — ไม่ต้องแก้ .env หรือ config:cache");
        return true;
    } catch (e) {
        console.log(`      ❌ ยิงไปที่เว็บไม่สำเร็จ: ${e.message}`);
        return false;
    }
}

/** บรรทัด .env สำหรับกรณีลงทะเบียนอัตโนมัติไม่ได้ */
const ENV_KEYS = {
    masternode_registry: "MASTERNODE_REGISTRY_ADDRESS",
    token_factory_v2: "TOKEN_FACTORY_V2_ADDRESS",
    nft_factory: "NFT_FACTORY_ADDRESS",
    wtpix: "TPIX_DEX_WTPIX_ADDRESS",
    usdt_tpix: "TPIX_DEX_USDT_ADDRESS",
    dex_factory: "TPIX_DEX_FACTORY_ADDRESS",
    dex_router: "TPIX_DEX_ROUTER_ADDRESS",
};

function printEnvFallback(payload) {
    console.log("\n" + "─".repeat(72));
    console.log("ยังไม่ได้ลงทะเบียนกับเว็บ — เอาบรรทัดนี้ไปใส่ .env แล้วรัน php artisan config:cache");
    console.log("─".repeat(72));
    for (const [k, v] of Object.entries(payload)) {
        if (v && ENV_KEYS[k]) console.log(`${ENV_KEYS[k]}=${v}`);
    }
}

module.exports = { registerWithSite, printEnvFallback, ENV_KEYS };
