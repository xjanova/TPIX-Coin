/**
 * ฝากเหรียญเข้าสัญญาล็อกและ presale ที่ launch-token.js deploy ไว้ — โอน "เฉพาะส่วนที่ยังขาด" แล้วตรวจซ้ำบนเชน
 *
 *   npx hardhat run scripts/fund-launch.js --network tpix      (ผ่าน launch-idtc.ps1)
 *
 * environment: LAUNCH_PLAN (ค่าปริยาย idtc) · TOKEN (ต้องตรงกับเหรียญที่สัญญาทั้งสองผูกไว้)
 * กระเป๋าที่รันต้องถือเหรียญ · รันซ้ำได้: สัญญาที่ครบแล้วจะไม่ถูกโอนเพิ่ม
 *
 * Developed by Xman Studio
 */
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");
const fmt = (wei, dec) => Number(ethers.formatUnits(wei, dec)).toLocaleString("en-US", { maximumFractionDigits: 6 });

async function main() {
    if (network.name === "hardhat") throw new Error("สคริปต์นี้ใช้กับเชนจริงเท่านั้น — การซ้อมทั้งสายอยู่ใน launch-token.js");
    const [signer] = await ethers.getSigners();
    if ((await ethers.provider.getNetwork()).chainId !== 4289n) throw new Error("ไม่ใช่ TPIX Chain (4289)");
    const plan = JSON.parse(fs.readFileSync(path.join(__dirname, "launch-plans", `${(process.env.LAUNCH_PLAN || "idtc").replace(/[^a-z0-9_-]/gi, "")}.json`), "utf8"));
    const reg = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    const find = (n) => (reg.contracts || []).find((c) => c.name === n)?.address || null;

    const tokenAddr = ethers.getAddress((process.env.TOKEN || "").trim().toLowerCase());
    const token = await ethers.getContractAt("FactoryERC20V2", tokenAddr);
    const dec = Number(await token.decimals());

    const targets = [];
    const vestAddr = find(`${plan.symbol}_Vesting`);
    if (vestAddr) {
        const v = await ethers.getContractAt("TrancheVesting", vestAddr);
        if ((await v.token()).toLowerCase() !== tokenAddr.toLowerCase()) throw new Error(`${vestAddr} ผูกกับเหรียญอื่น — หยุด`);
        // ยอดที่ต้องมีในสัญญา = ที่ยังไม่ปลด (totalAllocation − released)
        targets.push({ name: "สัญญาล็อก", addr: vestAddr, need: (await v.totalAllocation()) - (await v.released()), check: () => v.isFunded() });
    }
    const saleAddr = find(`${plan.symbol}_Presale`);
    if (saleAddr) {
        const s = await ethers.getContractAt("FixedPriceSale", saleAddr);
        if ((await s.saleToken()).toLowerCase() !== tokenAddr.toLowerCase()) throw new Error(`${saleAddr} ขายเหรียญอื่น — หยุด`);
        targets.push({ name: "presale", addr: saleAddr, need: (await s.saleCap()) - (await s.sold()), check: async () => (await token.balanceOf(saleAddr)) >= (await s.saleCap()) - (await s.sold()) });
    }
    if (!targets.length) throw new Error(`ไม่มี ${plan.symbol}_Vesting / ${plan.symbol}_Presale ใน registry — รัน launch-token.js ก่อน`);

    let total = 0n;
    for (const t of targets) {
        t.has = await token.balanceOf(t.addr);
        t.send = t.need > t.has ? t.need - t.has : 0n;
        total += t.send;
        console.log(`  ${t.name.padEnd(10)} ${t.addr} · ต้องมี ${fmt(t.need, dec)} · มีแล้ว ${fmt(t.has, dec)} · จะโอน ${fmt(t.send, dec)}`);
    }
    const bal = await token.balanceOf(signer.address);
    if (bal < total) throw new Error(`กระเป๋า ${signer.address} มี ${fmt(bal, dec)} ${plan.symbol} ไม่พอ (ต้องใช้ ${fmt(total, dec)})`);

    for (const t of targets) {
        if (t.send === 0n) continue;
        await (await token.transfer(t.addr, t.send)).wait();
        console.log(`  โอน ${fmt(t.send, dec)} ${plan.symbol} → ${t.name} ✓`);
    }
    for (const t of targets) {
        if (!(await t.check())) throw new Error(`${t.name} ${t.addr}: โอนแล้วแต่ตรวจบนเชนไม่ผ่าน`);
        console.log(`  ✅ ${t.name} ครบ`);
    }
}

main().catch((e) => {
    console.error("\nล้มเหลว:", e.message);
    process.exitCode = 1;
});
