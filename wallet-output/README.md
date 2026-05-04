# TPIX Master Wallet — generated 2026-05-04T09:33:59.012Z

## Wallets (BIP-44 HD, all derived from single mnemonic)

- **main** — `0x18A4076b9B107121280a4373cD8474f9858D5D3f` — 0 TPIX (path m/44'/60'/0'/0/0)
- **masternode-rewards** — `0xf54c0deE404ec728a03b467cba7bBA171CC77dad` — 1,400,000,000 TPIX (path m/44'/60'/0'/0/1)
- **ecosystem-development** — `0x6E176Bf5Aa39Fb4217E0ebd00E14B67aDfFaf440` — 1,710,000,000 TPIX (path m/44'/60'/0'/0/2)
- **team-advisors** — `0x87e62D9e0C2aF15d634D3301Dd2D4DA57972052d` — 700,000,000 TPIX (path m/44'/60'/0'/0/3)
- **token-sale** — `0x4BcC1844Ad9E8587f7005f092928a5D14C30F463` — 700,000,000 TPIX (path m/44'/60'/0'/0/4)
- **liquidity-market-making** — `0x2644A740A06e0401D21F8B4A840400fFe8dB42A9` — 1,050,000,000 TPIX (path m/44'/60'/0'/0/5)
- **community-rewards** — `0x6dECa2E185CF37e7c838fE5Ae6897aED025c9921` — 1,400,000,000 TPIX (path m/44'/60'/0'/0/6)
- **validator-1-stake** — `0x24CD5d5A6B5EcC6520c76f5427DB06F81BcC61C5` — 10,000,000 TPIX (path m/44'/60'/0'/0/7)
- **validator-2-stake** — `0x394418d33641D967C3553e45Af0646d565F51Ba7` — 10,000,000 TPIX (path m/44'/60'/0'/0/8)
- **validator-3-stake** — `0x9D6Fc1cf3C17b495057356B95e995834248993F0` — 10,000,000 TPIX (path m/44'/60'/0'/0/9)
- **validator-4-stake** — `0xec91028198E8cC55B284c018aBB4B2A87c6f3F12` — 10,000,000 TPIX (path m/44'/60'/0'/0/10)

**Total:** 7,000,000,000 TPIX

## ⚠️ CRITICAL — backup checklist

The mnemonic is the ONE secret you must keep. Lose it = lose all 11 wallets forever.

[ ] **Open master-wallet.mnemonic.txt** → write the 12 words on **3 different paper sheets**
    Store each sheet in a different physical location (home safe, bank deposit box, family member).
[ ] Open master-wallet.privatekeys.txt → copy each `role -> private key` to your password manager
    (One entry per wallet — Bitwarden / 1Password / Apple Keychain).
[ ] Verify by re-deriving from mnemonic:
    ```
    node -e "const {ethers}=require('ethers'); const m=require('fs').readFileSync('./wallet-output/master-wallet.mnemonic.txt','utf8').trim(); console.log(ethers.HDNodeWallet.fromPhrase(m, undefined, \"m/44'/60'/0'/0/4\").address)"
    ```
    Should print the **token-sale** address from wallets.json.
[ ] **DELETE** master-wallet.mnemonic.txt
[ ] **DELETE** master-wallet.privatekeys.txt
[ ] Copy master-wallet.keystores.json to encrypted USB / cloud (encrypted, safer than plaintext)

## Files in this directory

- `master-wallet.mnemonic.txt`     ⚠️ DELETE after backup (the master secret)
- `master-wallet.privatekeys.txt`  ⚠️ DELETE after backup
- `master-wallet.keystores.json`   encrypted bundle, KEEP
- `wallets.json`                  public addresses + balances, safe to commit/share
- `README.md`                     this checklist

The whole `wallet-output/` directory is gitignored.

## Phase 3 deploy

Token Sale wallet (path `m/44'/60'/0'/0/4`) is used by `deploy-launch.ps1`.
After backup is done, when prompted for DEPLOYER_KEY, paste the private key
from `[token-sale]` in privatekeys.txt (or re-derive via the script above).
