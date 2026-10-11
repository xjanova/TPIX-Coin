#!/usr/bin/env node
/**
 * ส่งออก "standard JSON input" ของเหรียญแต่ละชนิดที่ Token Factory สร้าง
 * ให้เว็บ (ThaiXTrade) ใช้ verify เหรียญใหม่บน Blockscout ได้ทันทีหลังสร้าง
 *
 * ทำไมต้องมี: เว็บเคย verify ด้วยไฟล์ flatten + evm cancun ซึ่งไม่ตรงกับที่ TPIX-Coin compile จริง
 * (solc 0.8.24 · london · viaIR · optimizer 200 · OZ 5.1.0) → ล้มทุกครั้ง
 * ไฟล์นี้เอา build-info ที่ hardhat compile จริงมาใช้ จึงได้ค่าตรงเป๊ะ
 *
 * ตัด source ให้เหลือเฉพาะไฟล์ที่สัญญานั้นใช้จริง (ไล่ import จาก AST) — metadata ของ solc
 * ผูกเฉพาะไฟล์ที่สัญญาพึ่งพา จึงได้ bytecode เดิมทุกไบต์ แต่ไฟล์เล็กลงมาก
 *
 * Usage:
 *   node scripts/export-verify-inputs.js [ปลายทาง] [--check]
 *   ปลายทางปริยาย: ../../ThaiXTrade/resources/contracts/verify
 *   --check  compile ไฟล์ที่ตัดแล้วด้วย solc ตัวเดียวกัน แล้วเทียบ runtime bytecode กับ artifact
 *
 * Developed by Xman Studio
 */

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

const ROOT = path.join(__dirname, "..");
const TARGETS = [
    ["FactoryERC20V2", "src/token-factory/FactoryERC20V2.sol"],
    ["UtilityToken", "src/token-factory/UtilityToken.sol"],
    ["RewardToken", "src/token-factory/RewardToken.sol"],
    ["GovernanceToken", "src/token-factory/GovernanceToken.sol"],
    ["StablecoinToken", "src/token-factory/StablecoinToken.sol"],
    ["FactoryERC721", "src/token-factory/FactoryERC721.sol"],
    ["NFTCollection", "src/token-factory/NFTCollection.sol"],
];

const args = process.argv.slice(2);
const check = args.includes("--check");
const outDir = path.resolve(args.find((a) => !a.startsWith("--")) || path.join(ROOT, "..", "..", "ThaiXTrade", "resources", "contracts", "verify"));

function loadBuild(contractName, sourcePath) {
    const artDir = path.join(ROOT, "artifacts", sourcePath);
    const artifact = JSON.parse(fs.readFileSync(path.join(artDir, `${contractName}.json`), "utf8"));
    const dbg = JSON.parse(fs.readFileSync(path.join(artDir, `${contractName}.dbg.json`), "utf8"));
    const buildInfo = JSON.parse(fs.readFileSync(path.join(artDir, dbg.buildInfo), "utf8"));
    return { artifact, buildInfo };
}

/** ไล่ import แบบ transitive จาก AST ใน build-info output */
function dependencyClosure(buildInfo, entry) {
    const seen = new Set();
    const stack = [entry];
    while (stack.length) {
        const file = stack.pop();
        if (seen.has(file)) continue;
        seen.add(file);
        const ast = buildInfo.output.sources[file]?.ast;
        if (!ast) throw new Error(`ไม่พบ AST ของ ${file} ใน build-info`);
        for (const node of ast.nodes || []) {
            if (node.nodeType === "ImportDirective") stack.push(node.absolutePath);
        }
    }
    return seen;
}

function solcPath(longVersion) {
    const base = process.env.LOCALAPPDATA
        ? path.join(process.env.LOCALAPPDATA, "hardhat-nodejs", "Cache", "compilers-v2")
        : path.join(os.homedir(), ".cache", "hardhat-nodejs", "compilers-v2");
    for (const platform of fs.existsSync(base) ? fs.readdirSync(base) : []) {
        for (const f of fs.readdirSync(path.join(base, platform))) {
            if (f.includes(`v${longVersion}`) && !f.endsWith(".json")) return path.join(base, platform, f);
        }
    }
    return null;
}

function main() {
    fs.mkdirSync(outDir, { recursive: true });
    let failed = 0;

    for (const [contractName, sourcePath] of TARGETS) {
        const { artifact, buildInfo } = loadBuild(contractName, sourcePath);
        const keep = dependencyClosure(buildInfo, artifact.sourceName);
        const input = {
            language: buildInfo.input.language,
            sources: Object.fromEntries(Object.entries(buildInfo.input.sources).filter(([k]) => keep.has(k))),
            settings: buildInfo.input.settings,
        };
        const doc = {
            compiler_version: `v${buildInfo.solcLongVersion}`,
            contract_name: `${artifact.sourceName}:${artifact.contractName}`,
            evm_version: buildInfo.input.settings.evmVersion,
            via_ir: !!buildInfo.input.settings.viaIR,
            input,
        };
        const file = path.join(outDir, `${contractName}.json`);
        fs.writeFileSync(file, JSON.stringify(doc) + "\n");
        let status = "";

        if (check) {
            const solc = solcPath(buildInfo.solcLongVersion);
            if (!solc) {
                status = "  (ข้าม --check: ไม่พบ solc ใน cache ของ hardhat)";
            } else {
                const out = JSON.parse(execFileSync(solc, ["--standard-json"], {
                    input: JSON.stringify(input), maxBuffer: 1 << 30,
                }).toString());
                const errors = (out.errors || []).filter((e) => e.severity === "error");
                const compiled = out.contracts?.[artifact.sourceName]?.[contractName];
                const same = !errors.length && compiled
                    && `0x${compiled.evm.deployedBytecode.object}` === artifact.deployedBytecode;
                if (!same) failed++;
                status = same ? "  ✅ bytecode ตรงกับ artifact" : `  ❌ ไม่ตรง ${errors.map((e) => e.formattedMessage).join(" | ")}`;
            }
        }
        const kb = (fs.statSync(file).size / 1024).toFixed(0);
        console.log(`${contractName.padEnd(16)} ${String(keep.size).padStart(3)} ไฟล์ · ${kb.padStart(4)} KB · ${doc.compiler_version} ${doc.evm_version}${doc.via_ir ? " viaIR" : ""}${status}`);
    }

    console.log(`\nเขียนไว้ที่ ${outDir}`);
    if (failed) {
        console.error(`❌ bytecode ไม่ตรง ${failed} ตัว — ห้ามใช้ไฟล์ชุดนี้`);
        process.exitCode = 1;
    }
}

main();
