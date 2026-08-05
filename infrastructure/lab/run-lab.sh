#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  run-lab.sh — พิสูจน์ว่า genesis ใหม่ทำให้เชนเดินได้ ก่อนแตะของจริง
# ══════════════════════════════════════════════════════════════════════════════
#
#  รอบก่อน regenesis พังบน production 8 ครั้ง เพราะไม่เคยทดสอบที่อื่นก่อน
#  ตัวนี้รันได้บนเครื่องไหนก็ได้ที่มี docker (โน้ตบุ๊ก / VPS ตัวทิ้ง)
#  พังกี่รอบก็ได้ ไม่มีลูกค้าเดือดร้อน
#
#  สิ่งที่มันดักได้ (คือสองบั๊กที่ทำให้รอบก่อนพัง):
#    1. genesis ที่ validator set ว่างเปล่า → genesis-verify.py ตีตกตั้งแต่ยังไม่สตาร์ท
#    2. data dir เก่าค้าง → บล็อก 0 เดิม (validator set ว่าง) ถูกใช้ต่อ
#       ต่อให้ genesis.json ใหม่ถูกต้องแล้วก็ตาม → ตัวนี้ล้าง data ทุกครั้ง
#
#  ใช้:  ./run-lab.sh            # ล้าง + สร้าง + สตาร์ท + ตรวจ
#        ./run-lab.sh --down     # เก็บกวาด
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
COMPOSE="$HERE/docker-compose.lab.yml"
KEYS_DIR="$HERE/keys"
WAIT_SECONDS=120

die() { echo -e "\n❌ $*\n" >&2; exit 1; }
say() { echo -e "\n▸ $*"; }

if [[ "${1:-}" == "--down" ]]; then
  docker compose -f "$COMPOSE" down -v 2>/dev/null || true
  rm -rf "$HERE/data" "$HERE/genesis.json" "$HERE/genesis.json.meta"
  echo "เก็บกวาด lab เรียบร้อย (คีย์ที่ $KEYS_DIR ยังอยู่)"
  exit 0
fi

command -v docker >/dev/null || die "ไม่พบ docker"
docker compose version >/dev/null 2>&1 || die "ไม่พบ docker compose v2"

# ── 1. ล้างของเก่าให้เกลี้ยง ────────────────────────────────────────────────────
say "1/5 ล้าง lab เดิม"
docker compose -f "$COMPOSE" down -v 2>/dev/null || true
rm -rf "$HERE/data" "$HERE/genesis.json" "$HERE/genesis.json.meta"

# ── 2. สร้าง genesis (โหมด lab ใช้ /dns4/ ชื่อ container) ────────────────────────
say "2/5 สร้าง genesis สำหรับ lab"
ALLOC_ENV="$INFRA/chain/alloc.env" \
  bash "$INFRA/scripts/build-genesis.sh" \
    --out "$HERE/genesis.json" \
    --keys-dir "$KEYS_DIR" \
    --lab

# ── 3. วางคีย์ลง data dir ที่ "สะอาดจริง" ───────────────────────────────────────
# polygon-edge ใช้ --data-dir เดียวกันทั้งเก็บคีย์และเก็บบล็อกเชน
# ถ้าเหลือ blockchain/ หรือ trie/ ของรอบก่อน มันจะใช้บล็อก 0 เก่าต่อ
# แล้ว genesis.json ใหม่จะไม่มีผลใดๆ ← นี่คือเหตุผลที่ต้อง copy จาก keys/ ทุกครั้ง
say "3/5 วางคีย์ลง data dir ใหม่ (ไม่มี blockchain/ trie/ ค้าง)"
for i in 1 2 3 4; do
  src="$KEYS_DIR/validator-$i"
  dst="$HERE/data/validator-$i"
  [[ -d "$src/consensus" ]] || die "ไม่พบคีย์ที่ $src/consensus (build-genesis.sh ควรสร้างให้แล้ว)"
  mkdir -p "$dst"
  cp -r "$src/consensus" "$dst/"
  cp -r "$src/libp2p"    "$dst/" 2>/dev/null || true
  [[ -e "$dst/blockchain" || -e "$dst/trie" ]] && die "data dir ไม่สะอาด: $dst"
  echo "  · validator-$i พร้อม"
done

# ── 4. สตาร์ท ───────────────────────────────────────────────────────────────────
say "4/5 สตาร์ท 4 validator"
docker compose -f "$COMPOSE" up -d
sleep 10

# ── 5. ตรวจว่าบล็อกเดินจริง ─────────────────────────────────────────────────────
say "5/5 รอบล็อกเดิน (สูงสุด ${WAIT_SECONDS}s)"
rpc() {
  curl -s --max-time 5 -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":[],\"id\":1}" \
    http://127.0.0.1:8545 2>/dev/null || true
}

height_hex=""
elapsed=0
while [[ $elapsed -lt $WAIT_SECONDS ]]; do
  resp="$(rpc eth_blockNumber)"
  height_hex="$(echo "$resp" | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p')"
  if [[ -n "$height_hex" && "$height_hex" != "0x0" ]]; then
    break
  fi
  printf "\r  ผ่านไป %3ds — ความสูง: %s" "$elapsed" "${height_hex:-รอ RPC…}"
  sleep 5; elapsed=$((elapsed + 5))
done
echo

if [[ -z "$height_hex" || "$height_hex" == "0x0" ]]; then
  echo
  echo "════════════ ผลลัพธ์: ล้มเหลว — ยังค้างที่บล็อก 0 ════════════"
  echo
  echo "อาการเดียวกับรอบ 2026-05-04/05-07 — เก็บหลักฐานก่อนลองใหม่:"
  echo
  echo "── extraData ที่ใช้จริง ──"
  python3 -c "
import json
g=json.load(open('$HERE/genesis.json'))
e=g['genesis']['extraData']
print('ยาว', len(e), 'ตัวอักษร', '(82 = validator set ว่าง, ~666 = 4 validators BLS)')
"
  echo
  echo "── log validator-1 ──"
  docker logs tpix-validator-1 --tail 40 2>&1 | grep -iE "ibft|round|seal|validator|consensus|error" || \
    docker logs tpix-validator-1 --tail 40 2>&1
  echo
  echo "── จำนวน peer ──"
  rpc net_peerCount
  echo
  echo "ถ้า genesis ผ่าน verify แล้วยังค้าง 0 → ลองตามลำดับ:"
  echo "  ก) เปลี่ยน image เป็น 0xpolygon/polygon-edge:0.10.0 หรือ :1.3.3 แล้วรัน lab ใหม่"
  echo "  ข) เพิ่ม --log-level DEBUG แล้วหาบรรทัดที่มีคำว่า 'ibft'"
  echo "  ค) ลดเหลือ validator เดียว (--seal) เพื่อแยกว่าเป็นปัญหา consensus หรือ networking"
  exit 1
fi

height=$((height_hex))
sleep 12
resp2="$(rpc eth_blockNumber)"
h2_hex="$(echo "$resp2" | sed -n 's/.*"result":"\(0x[0-9a-fA-F]*\)".*/\1/p')"
h2=$((h2_hex))

echo
echo "════════════════════ ผลลัพธ์: สำเร็จ ════════════════════"
echo "  ความสูงครั้งแรก : $height"
echo "  อีก 12 วินาที   : $h2  (+$((h2 - height)) บล็อก)"
[[ $h2 -gt $height ]] || die "บล็อกไม่เพิ่ม — เชนหยุดหลังเริ่มได้ ยังไม่ควรขึ้น production"
echo "  sha256 genesis  : $(sha256sum "$HERE/genesis.json" | cut -d' ' -f1)"
echo
echo "  ✅ genesis ชุดนี้ทำให้เชนเกิดใหม่จากบล็อก 0 ได้จริง"
echo "     ขั้นถัดไปตาม docs/REGENESIS-RUNBOOK.md → Phase 3 (สร้าง genesis จริงด้วย IP สาธารณะ)"
echo
echo "  เก็บกวาด: ./run-lab.sh --down"
