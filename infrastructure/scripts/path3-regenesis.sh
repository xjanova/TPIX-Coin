#!/bin/bash
# ##############################################################################
# ⛔ DEAD — ห้ามรัน (ปิดตาย 2026-08-05)
# ##############################################################################
# สคริปต์นี้คือตัวที่ทำให้เชนค้างบล็อก 0 ทั้ง 8 ครั้ง (2026-05-04 → 05-07)
#
# สาเหตุ: ใช้ `--ibft-validators-prefix-path` ซึ่ง polygon-edge จะ "ไม่ error"
#         เมื่อหาคีย์ตาม path ไม่เจอ แต่สร้าง genesis ที่ validator set ว่างเปล่า
#         (extraData = 82 ตัวอักษร แทนที่จะเป็น ~666) → ไม่มีใครมีสิทธิ์ propose
#         → เชนค้างบล็อก 0 ตลอดกาลโดยไม่มี error ที่ไหนเลย
#
# ใช้แทน: infrastructure/scripts/build-genesis.sh
#          (ระบุ validator ตรงๆ + เรียก genesis-verify.py ก่อนคืนไฟล์)
# อ่าน:   docs/REGENESIS-RUNBOOK.md
# ##############################################################################
echo "⛔ สคริปต์นี้ถูกปิดตายแล้ว — ใช้ scripts/build-genesis.sh แทน" >&2
echo "   เหตุผล + ขั้นตอนใหม่: docs/REGENESIS-RUNBOOK.md" >&2
exit 1

# =============================================================================
# Path 3 — Clean regenesis using polygon-edge native CLI  (เนื้อหาเดิม เก็บไว้อ้างอิง)
# =============================================================================
# Run on TPIX server (admin@123.253.62.250) after fresh `git pull origin main`
#
#   cd ~/TPIX-Coin/infrastructure
#   chmod +x scripts/path3-regenesis.sh
#   sudo ./scripts/path3-regenesis.sh
#
# What this does (irreversible — wipes blockchain state):
#   A. Reverts --no-discover flag from docker-compose-4v.yml
#   B. Stops compose + wipes validator data dirs
#   C. Generates fresh IBFT validator keys (4 validators)
#   D. Generates new genesis with BIP-44 allocations + new validator set
#   E. Starts compose + verifies block height > 0
#   F. Prints summary (paste back to local PC for git commit)
#
# Why "wipe data" not "reset chain head":
#   IBFT consensus state is in validator data dir. Mismatched validator-set
#   hashes between nodes cause silent stall (no propose, no error). Cleanest
#   fix: treat as fresh chain — keep only genesis as source of truth.
# =============================================================================
set -e

cd "$(dirname "$0")/.."
COMPOSE=docker-compose-4v.yml
CHAIN_DIR=tpix-chain
SUMMARY_FILE=/tmp/path3-summary.txt

if [ ! -f "$COMPOSE" ]; then
  echo "ERROR: $COMPOSE not found — run from ~/TPIX-Coin/infrastructure/"
  exit 1
fi

echo "╔══════════════════════════════════════════════════╗"
echo "║   TPIX Path 3 Regenesis (clean wipe)             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "This will WIPE all validator data and regenerate genesis."
echo "Press ENTER to continue, Ctrl+C to abort."
read -r _

# ─── A. Revert --no-discover flag
echo ""
echo "→ [A] Reverting --no-discover flag"
if [ -f "${COMPOSE}.bak" ]; then
  cp "${COMPOSE}.bak" "$COMPOSE"
  echo "  ✓ Restored from .bak"
else
  sed -i 's| --no-discover||g' "$COMPOSE"
  echo "  ✓ Stripped flag inline"
fi

# ─── B. Stop + wipe
echo ""
echo "→ [B] Stopping compose + wiping validator data"
docker compose -f "$COMPOSE" down
for v in 1 2 3 4; do
  rm -rf "${CHAIN_DIR}/data/validator-$v"
  rm -rf "data/validator-$v"
  mkdir -p "${CHAIN_DIR}/data/validator-$v"
done
echo "  ✓ Wiped"

# ─── C. Generate fresh validator keys
echo ""
echo "→ [C] Generating fresh validator keys (polygon-edge secrets init)"
declare -A VADDR
declare -A VBLS
declare -A VNODE
for v in 1 2 3 4; do
  echo "  → validator-$v"
  OUT=$(docker run --rm -v "$(pwd)/${CHAIN_DIR}/data/validator-$v:/data" \
    0xpolygon/polygon-edge:0.9.0 secrets init --data-dir /data 2>&1)
  VADDR[$v]=$(echo "$OUT" | awk -F= '/Public key \(address\)/ {gsub(/^ +/,"",$2); print $2}')
  VBLS[$v]=$(echo "$OUT" | awk -F= '/BLS Public key/ {gsub(/^ +/,"",$2); print $2}')
  VNODE[$v]=$(echo "$OUT" | awk -F= '/Node ID/ {gsub(/^ +/,"",$2); print $2}')
  echo "    addr=${VADDR[$v]}"
  echo "    node=${VNODE[$v]}"
done

cat > /tmp/validator-keys.txt <<EOF
v1_addr=${VADDR[1]}
v1_bls=${VBLS[1]}
v1_node=${VNODE[1]}
v2_addr=${VADDR[2]}
v2_bls=${VBLS[2]}
v2_node=${VNODE[2]}
v3_addr=${VADDR[3]}
v3_bls=${VBLS[3]}
v3_node=${VNODE[3]}
v4_addr=${VADDR[4]}
v4_bls=${VBLS[4]}
v4_node=${VNODE[4]}
EOF
echo "  ✓ Saved to /tmp/validator-keys.txt"

# ─── D. Generate new genesis (BIP-44 allocations)
echo ""
echo "→ [D] Generating genesis with BIP-44 allocations"

# BIP-44 derived addresses (m/44'/60'/0'/0/N) — wallets.json source of truth
ALLOC=""
for entry in \
  "0xf54c0deE404ec728a03b467cba7bBA171CC77dad:1400000000" \
  "0x6E176Bf5Aa39Fb4217E0ebd00E14B67aDfFaf440:1710000000" \
  "0x87e62D9e0C2aF15d634D3301Dd2D4DA57972052d:700000000" \
  "0x4BcC1844Ad9E8587f7005f092928a5D14C30F463:700000000" \
  "0x2644A740A06e0401D21F8B4A840400fFe8dB42A9:1050000000" \
  "0x6dECa2E185CF37e7c838fE5Ae6897aED025c9921:1400000000"; do
  ADDR=$(echo "$entry" | cut -d: -f1)
  AMT=$(echo "$entry" | cut -d: -f2)
  ALLOC="$ALLOC --premine $ADDR:${AMT}000000000000000000"
done
# Validator stake (10M each) — goes to NEW IBFT keys, not BIP-44 indices 7-10
for v in 1 2 3 4; do
  eval ADDR="\$v${v}_addr"
  ALLOC="$ALLOC --premine $ADDR:10000000000000000000000000"
done

rm -f "${CHAIN_DIR}/genesis.json"
docker run --rm -v "$(pwd)/${CHAIN_DIR}:/data" \
  0xpolygon/polygon-edge:0.9.0 genesis \
    --dir /data/genesis.json \
    --consensus ibft \
    --ibft-validators-prefix-path /data/data/validator- \
    --bootnode "/dns4/tpix-validator-1/tcp/10001/p2p/${VNODE[1]}" \
    --bootnode "/dns4/tpix-validator-2/tcp/10001/p2p/${VNODE[2]}" \
    --bootnode "/dns4/tpix-validator-3/tcp/10001/p2p/${VNODE[3]}" \
    --bootnode "/dns4/tpix-validator-4/tcp/10001/p2p/${VNODE[4]}" \
    --chain-id 4289 \
    --block-gas-limit 20000000 \
    $ALLOC

# Distribute genesis to all validators
for v in 1 2 3 4; do
  cp "${CHAIN_DIR}/genesis.json" "${CHAIN_DIR}/data/validator-$v/genesis.json"
done
echo "  ✓ Genesis written + distributed to validators"

# ─── E. Start + verify
echo ""
echo "→ [E] Starting compose + verifying block height"
docker compose -f "$COMPOSE" up -d
echo "  Waiting 30s for IBFT to start producing..."
sleep 30

docker ps --format '{{.Names}} | {{.Status}}' | grep tpix || true
echo ""
BLOCK_HEX=$(curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545 | grep -o '0x[0-9a-fA-F]*' | head -1)
BLOCK_DEC=$((BLOCK_HEX))
echo "  Block height: $BLOCK_HEX (decimal: $BLOCK_DEC)"

if [ "$BLOCK_DEC" -gt 0 ]; then
  echo "  ✅ CHAIN ALIVE — producing blocks"
else
  echo "  ❌ Still stuck at block 0 — check: docker logs tpix-validator-1 --tail 30 | grep -iE 'ibft|round|seal'"
  exit 1
fi

# ─── F. Summary (copy back to local repo)
echo ""
echo "→ [F] Generating summary at $SUMMARY_FILE"
cat > "$SUMMARY_FILE" <<EOF
TPIX Path 3 Regenesis Summary
=============================
Date: $(date -Iseconds)
Block height after regenesis: $BLOCK_HEX

Validator Set (NEW IBFT keys)
=============================
v1: ${VADDR[1]}
v2: ${VADDR[2]}
v3: ${VADDR[3]}
v4: ${VADDR[4]}

Allocation (BIP-44 derived)
===========================
masternode-rewards    1.4B   0xf54c0deE404ec728a03b467cba7bBA171CC77dad
ecosystem-development 1.71B  0x6E176Bf5Aa39Fb4217E0ebd00E14B67aDfFaf440
team-advisors         700M   0x87e62D9e0C2aF15d634D3301Dd2D4DA57972052d
token-sale            700M   0x4BcC1844Ad9E8587f7005f092928a5D14C30F463
liquidity-mm          1.05B  0x2644A740A06e0401D21F8B4A840400fFe8dB42A9
community-rewards     1.4B   0x6dECa2E185CF37e7c838fE5Ae6897aED025c9921
4x validator stake    10M ea (to NEW IBFT keys above)

Total: 7,000,000,000 TPIX

Next Steps (run on local PC after this)
=======================================
ssh admin@123.253.62.250 "cat ~/TPIX-Coin/infrastructure/tpix-chain/genesis.json" \\
  > D:/Code/TPIX/TPIX-Coin/infrastructure/genesis.json
cd D:/Code/TPIX/TPIX-Coin
git add infrastructure/genesis.json
git commit -m "chore(chain): Path 3 regenesis - polygon-edge native, fresh IBFT set"
git push origin main

cd contracts
.\\scripts\\deploy-launch.ps1
# When prompted: Token Sale wallet 0x4BcC1844Ad9E8587f7005f092928a5D14C30F463
EOF

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅ PATH 3 COMPLETE                             ║"
echo "╚══════════════════════════════════════════════════╝"
cat "$SUMMARY_FILE"
echo ""
echo "Summary saved to $SUMMARY_FILE"
