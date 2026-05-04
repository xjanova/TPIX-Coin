/**
 * Generate a fresh BIP-44 HD master wallet for TPIX chain regenesis.
 *
 * Per whitepaper §6 Tokenomics: ONE mnemonic derives ALL allocation wallets.
 * User backs up the mnemonic ONCE → controls all 11 wallets.
 *
 * Derivation paths (BIP-44 m/44'/60'/0'/0/N):
 *   path 0  → Main treasury / reward receiver (0 balance, alias)
 *   path 1  → Master Node Rewards     (1,400,000,000 TPIX, 20.00%)
 *   path 2  → Ecosystem Development   (1,710,000,000 TPIX, 24.43%)
 *   path 3  → Team & Advisors         (  700,000,000 TPIX, 10.00%)
 *   path 4  → Token Sale              (  700,000,000 TPIX, 10.00%) ← used by bonding curve deploy
 *   path 5  → Liquidity & MM          (1,050,000,000 TPIX, 15.00%)
 *   path 6  → Community & Rewards     (1,400,000,000 TPIX, 20.00%)
 *   path 7  → Validator-1 stake       (   10,000,000 TPIX, 0.143%)
 *   path 8  → Validator-2 stake       (   10,000,000 TPIX, 0.143%)
 *   path 9  → Validator-3 stake       (   10,000,000 TPIX, 0.143%)
 *   path 10 → Validator-4 stake       (   10,000,000 TPIX, 0.143%)
 *   ──────────────────────────────────────────────────────────────
 *   TOTAL                              7,000,000,000 TPIX (100%)
 *
 * SECURITY:
 *   - Mnemonic + private keys written ONLY to local files (never echoed to stdout)
 *   - User opens via Notepad → copies to password manager + 3 paper backups → deletes plaintext
 *   - Encrypted keystore JSON (one per derivation) is the long-term backup
 *
 * Usage (called by regenesis.ps1):
 *   $env:KEYSTORE_PASSWORD = "your strong password"
 *   node scripts/generate-master-wallet.js
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// ── Whitepaper allocation table
const ALLOCATIONS = [
    { path: "m/44'/60'/0'/0/0",  role: "main",                  balance_tpix: 0n },
    { path: "m/44'/60'/0'/0/1",  role: "masternode-rewards",    balance_tpix: 1_400_000_000n },
    { path: "m/44'/60'/0'/0/2",  role: "ecosystem-development", balance_tpix: 1_710_000_000n },
    { path: "m/44'/60'/0'/0/3",  role: "team-advisors",         balance_tpix:   700_000_000n },
    { path: "m/44'/60'/0'/0/4",  role: "token-sale",            balance_tpix:   700_000_000n },
    { path: "m/44'/60'/0'/0/5",  role: "liquidity-market-making", balance_tpix: 1_050_000_000n },
    { path: "m/44'/60'/0'/0/6",  role: "community-rewards",     balance_tpix: 1_400_000_000n },
    { path: "m/44'/60'/0'/0/7",  role: "validator-1-stake",     balance_tpix:    10_000_000n },
    { path: "m/44'/60'/0'/0/8",  role: "validator-2-stake",     balance_tpix:    10_000_000n },
    { path: "m/44'/60'/0'/0/9",  role: "validator-3-stake",     balance_tpix:    10_000_000n },
    { path: "m/44'/60'/0'/0/10", role: "validator-4-stake",     balance_tpix:    10_000_000n },
];

async function main() {
    const password = process.env.KEYSTORE_PASSWORD;
    if (!password || password.length < 12) {
        console.error("❌ KEYSTORE_PASSWORD env var required (12+ chars). Use the launcher script.");
        process.exit(1);
    }

    const OUT_DIR = path.join(__dirname, "..", "..", "wallet-output");
    fs.mkdirSync(OUT_DIR, { recursive: true });

    if (fs.existsSync(path.join(OUT_DIR, "master-wallet.mnemonic.txt")) ||
        fs.existsSync(path.join(OUT_DIR, "wallets.json"))) {
        console.error("❌ wallet-output/ already has a wallet generated.");
        console.error("   Move/rename existing files first.");
        process.exit(1);
    }

    // Verify allocation totals to 7B
    const total = ALLOCATIONS.reduce((s, a) => s + a.balance_tpix, 0n);
    if (total !== 7_000_000_000n) {
        console.error(`❌ Allocation totals ${total}, not 7,000,000,000. Refusing.`);
        process.exit(1);
    }

    // ── Generate single mnemonic
    const masterWallet = ethers.Wallet.createRandom();
    const mnemonic = masterWallet.mnemonic.phrase;

    // ── Derive each allocation wallet from mnemonic
    const wallets = [];
    for (const alloc of ALLOCATIONS) {
        const w = ethers.HDNodeWallet.fromPhrase(mnemonic, undefined, alloc.path);
        wallets.push({
            ...alloc,
            address: w.address,
            privateKey: w.privateKey,
        });
    }

    // ── Encrypt each individual wallet keystore (in case user wants to load
    //    one independently into MetaMask or Hardhat)
    process.stdout.write("Encrypting keystores (10-30 sec)... ");
    const keystores = {};
    for (const w of wallets) {
        const acct = new ethers.Wallet(w.privateKey);
        keystores[w.role] = await acct.encrypt(password);
    }
    console.log("done.");

    // ── Write outputs
    // 1. Mnemonic (PLAINTEXT, user copies to paper + deletes)
    fs.writeFileSync(
        path.join(OUT_DIR, "master-wallet.mnemonic.txt"),
        mnemonic + "\n",
        { mode: 0o600 }
    );

    // 2. Wallets summary (addresses + roles + balance — public-safe info)
    const summary = wallets.map(w => ({
        path: w.path,
        role: w.role,
        address: w.address,
        balance_tpix: w.balance_tpix.toString(),
        balance_wei_hex: "0x" + (w.balance_tpix * (10n ** 18n)).toString(16),
    }));
    fs.writeFileSync(
        path.join(OUT_DIR, "wallets.json"),
        JSON.stringify(summary, null, 2) + "\n",
        { mode: 0o644 }
    );

    // 3. Private keys (PLAINTEXT, user copies to password manager + deletes)
    let pkContent = "# TPIX Master Wallet — private keys\n";
    pkContent += "# DELETE this file after copying ALL keys to your password manager.\n";
    pkContent += "# Mnemonic in master-wallet.mnemonic.txt regenerates all of these.\n\n";
    for (const w of wallets) {
        pkContent += `[${w.role}]  ${w.address}\n  ${w.privateKey}\n\n`;
    }
    fs.writeFileSync(
        path.join(OUT_DIR, "master-wallet.privatekeys.txt"),
        pkContent,
        { mode: 0o600 }
    );

    // 4. Encrypted keystores bundle
    fs.writeFileSync(
        path.join(OUT_DIR, "master-wallet.keystores.json"),
        JSON.stringify(keystores, null, 2) + "\n",
        { mode: 0o600 }
    );

    // 5. README checklist
    const readme = `# TPIX Master Wallet — generated ${new Date().toISOString()}

## Wallets (BIP-44 HD, all derived from single mnemonic)

${wallets.map(w =>
`- **${w.role}** — \`${w.address}\` — ${w.balance_tpix.toLocaleString()} TPIX (path ${w.path})`
).join("\n")}

**Total:** 7,000,000,000 TPIX

## ⚠️ CRITICAL — backup checklist

The mnemonic is the ONE secret you must keep. Lose it = lose all 11 wallets forever.

[ ] **Open master-wallet.mnemonic.txt** → write the 12 words on **3 different paper sheets**
    Store each sheet in a different physical location (home safe, bank deposit box, family member).
[ ] Open master-wallet.privatekeys.txt → copy each \`role -> private key\` to your password manager
    (One entry per wallet — Bitwarden / 1Password / Apple Keychain).
[ ] Verify by re-deriving from mnemonic:
    \`\`\`
    node -e "const {ethers}=require('ethers'); const m=require('fs').readFileSync('./wallet-output/master-wallet.mnemonic.txt','utf8').trim(); console.log(ethers.HDNodeWallet.fromPhrase(m, undefined, \\"m/44'/60'/0'/0/4\\").address)"
    \`\`\`
    Should print the **token-sale** address from wallets.json.
[ ] **DELETE** master-wallet.mnemonic.txt
[ ] **DELETE** master-wallet.privatekeys.txt
[ ] Copy master-wallet.keystores.json to encrypted USB / cloud (encrypted, safer than plaintext)

## Files in this directory

- \`master-wallet.mnemonic.txt\`     ⚠️ DELETE after backup (the master secret)
- \`master-wallet.privatekeys.txt\`  ⚠️ DELETE after backup
- \`master-wallet.keystores.json\`   encrypted bundle, KEEP
- \`wallets.json\`                  public addresses + balances, safe to commit/share
- \`README.md\`                     this checklist

The whole \`wallet-output/\` directory is gitignored.

## Phase 3 deploy

Token Sale wallet (path \`m/44'/60'/0'/0/4\`) is used by \`deploy-launch.ps1\`.
After backup is done, when prompted for DEPLOYER_KEY, paste the private key
from \`[token-sale]\` in privatekeys.txt (or re-derive via the script above).
`;
    fs.writeFileSync(path.join(OUT_DIR, "README.md"), readme);

    // ── Stdout — addresses only, no secrets
    console.log();
    console.log("════════════════════════════════════════════════════");
    console.log(" ✅ Master HD wallet generated (11 derivations)");
    console.log("════════════════════════════════════════════════════");
    console.log();
    console.log("Allocations (per whitepaper §6):");
    for (const w of wallets) {
        const balStr = w.balance_tpix === 0n ? "       (alias)"
            : w.balance_tpix.toLocaleString().padStart(15) + " TPIX";
        console.log(`  ${w.role.padEnd(28)} ${balStr}  ${w.address}`);
    }
    console.log();
    console.log("Files written to: " + OUT_DIR);
    console.log("  ⚠️ master-wallet.mnemonic.txt    — backup + DELETE");
    console.log("  ⚠️ master-wallet.privatekeys.txt — backup + DELETE");
    console.log("  ✓ master-wallet.keystores.json  — encrypted, keep");
    console.log("  ✓ wallets.json                  — public, safe to commit");
    console.log("  ✓ README.md                     — checklist");
    console.log();
    console.log("Next: launcher will open Notepad for you to copy.");
}

main().catch((err) => {
    console.error("❌ " + err.message);
    process.exit(1);
});
