#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  build-genesis.sh — สร้าง genesis.json ของ TPIX ใหม่ พร้อมด่านตรวจที่ข้ามไม่ได้
# ══════════════════════════════════════════════════════════════════════════════
#
#  ทำไมต้องเขียนใหม่แทนที่จะใช้ chain-regenesis-4v.yml เดิม:
#
#  1) เดิมใช้ `--ibft-validators-prefix-path` ซึ่งถ้าหา key ไม่เจอ polygon-edge
#     "ไม่ error" แต่สร้าง genesis ที่ validator set ว่างเปล่าออกมาเฉยๆ
#     → ตัวนี้ใช้ `--ibft-validator <addr>:<blsPubKey>` ระบุตรงๆ ทีละตัว
#       และ verify ผลลัพธ์ด้วย genesis-verify.py ก่อนคืนค่า
#
#  2) เดิม bootnode เขียน `/ip4/tpix-validator-1/...` ซึ่งผิดรูปแบบ multiaddr
#     (`/ip4/` ต้องตามด้วยตัวเลข IP เท่านั้น) → ตัวนี้บังคับใส่ IP จริง
#
#  3) เดิมตารางจัดสรรฝังอยู่ในสคริปต์ และมีสองชุดขัดกัน
#     → ตัวนี้อ่านจาก chain/alloc.env ที่เดียว
#
#  ใช้:
#    ./build-genesis.sh --out /path/genesis.json --node-ips "1.2.3.4,5.6.7.8,..." \
#                       [--keys-dir /path/keys] [--lab]
#
#    --lab  = โหมดทดลองในเครื่อง ใช้ /dns4/<ชื่อ container> แทน IP สาธารณะ
#
#  ต้องมี: docker, python3
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
ALLOC_ENV="${ALLOC_ENV:-$INFRA/chain/alloc.env}"
VERIFY_PY="$HERE/genesis-verify.py"

OUT=""
NODE_IPS=""
KEYS_DIR=""
LAB_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)       OUT="$2"; shift 2 ;;
    --node-ips)  NODE_IPS="$2"; shift 2 ;;
    --keys-dir)  KEYS_DIR="$2"; shift 2 ;;
    --lab)       LAB_MODE=1; shift ;;
    *) echo "ไม่รู้จัก option: $1" >&2; exit 2 ;;
  esac
done

die() { echo -e "\n❌ $*\n" >&2; exit 1; }
say() { echo -e "\n▸ $*"; }

[[ -f "$ALLOC_ENV" ]]  || die "ไม่พบ $ALLOC_ENV"
[[ -f "$VERIFY_PY" ]]  || die "ไม่พบ $VERIFY_PY — ห้ามรันโดยไม่มีตัวตรวจ"
[[ -n "$OUT" ]]        || die "ต้องระบุ --out"
command -v docker  >/dev/null || die "ไม่พบ docker"
command -v python3 >/dev/null || die "ไม่พบ python3"

# shellcheck disable=SC1090
source "$ALLOC_ENV"

KEYS_DIR="${KEYS_DIR:-$INFRA/chain/keys}"
IMG="$POLYGON_EDGE_IMAGE"

# ── 1. เตรียม/ตรวจคีย์ validator ───────────────────────────────────────────────
say "ขั้นที่ 1 — คีย์ validator ($VALIDATOR_COUNT ตัว) ที่ $KEYS_DIR"
mkdir -p "$KEYS_DIR"

declare -a ADDRS BLS NODEIDS
for i in $(seq 1 "$VALIDATOR_COUNT"); do
  VDIR="$KEYS_DIR/validator-$i"
  if [[ ! -d "$VDIR/consensus" ]]; then
    echo "  · สร้างคีย์ใหม่สำหรับ validator-$i"
    mkdir -p "$VDIR"
    docker run --rm -v "$VDIR:/data" "$IMG" secrets init --data-dir /data --insecure >/dev/null
  else
    echo "  · ใช้คีย์เดิมของ validator-$i (มีอยู่แล้ว)"
  fi

  OUT_TXT="$(docker run --rm -v "$VDIR:/data" "$IMG" secrets output --data-dir /data 2>&1)"
  A="$(echo "$OUT_TXT" | awk -F'= ' '/Public key \(address\)/{print $2}' | tr -d '[:space:]')"
  B="$(echo "$OUT_TXT" | awk -F'= ' '/BLS Public key/{print $2}'        | tr -d '[:space:]')"
  N="$(echo "$OUT_TXT" | awk -F'= ' '/Node ID/{print $2}'               | tr -d '[:space:]')"

  # ── ด่านที่ 1: ถ้าคีย์อ่านไม่ออก ต้องตายตรงนี้ ห้ามปล่อยผ่านเป็นค่าว่าง ──
  [[ -n "$A" ]] || die "validator-$i: อ่าน address ไม่ได้\n$OUT_TXT"
  [[ -n "$B" ]] || die "validator-$i: อ่าน BLS public key ไม่ได้ (ถ้า validator_type=bls จำเป็น)\n$OUT_TXT"
  [[ -n "$N" ]] || die "validator-$i: อ่าน Node ID ไม่ได้\n$OUT_TXT"

  ADDRS+=("$A"); BLS+=("$B"); NODEIDS+=("$N")
  echo "    address = $A"
  echo "    node id = ${N:0:24}…"
done

# ── 2. ประกอบ bootnodes ────────────────────────────────────────────────────────
say "ขั้นที่ 2 — bootnodes"
declare -a BOOT_ARGS
if [[ "$LAB_MODE" -eq 1 ]]; then
  for i in $(seq 1 "$VALIDATOR_COUNT"); do
    idx=$((i-1))
    BOOT_ARGS+=(--bootnode "/dns4/tpix-validator-$i/tcp/10001/p2p/${NODEIDS[$idx]}")
    echo "  · /dns4/tpix-validator-$i/tcp/10001/p2p/${NODEIDS[$idx]:0:16}…"
  done
else
  [[ -n "$NODE_IPS" ]] || die "โหมดจริงต้องระบุ --node-ips (IP สาธารณะของแต่ละโหนด คั่นด้วย ,)"
  IFS=',' read -ra IPS <<< "$NODE_IPS"
  [[ ${#IPS[@]} -eq $VALIDATOR_COUNT ]] || \
    die "จำนวน IP (${#IPS[@]}) ไม่เท่ากับ VALIDATOR_COUNT ($VALIDATOR_COUNT)"
  for i in $(seq 1 "$VALIDATOR_COUNT"); do
    idx=$((i-1)); ip="$(echo "${IPS[$idx]}" | tr -d '[:space:]')"
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "IP ไม่ถูกรูปแบบ: '$ip'"
    BOOT_ARGS+=(--bootnode "/ip4/$ip/tcp/10001/p2p/${NODEIDS[$idx]}")
    echo "  · /ip4/$ip/tcp/10001/p2p/${NODEIDS[$idx]:0:16}…"
  done
fi

# ── 3. ประกอบ premine จาก alloc.env ────────────────────────────────────────────
say "ขั้นที่ 3 — ตารางจัดสรร (จาก $(basename "$ALLOC_ENV"))"
declare -a PREMINE_ARGS
TOTAL=0
printf "  %-46s %18s\n" "ADDRESS" "TPIX"
printf "  %-46s %18s\n" "----------------------------------------------" "------------------"
while IFS= read -r line; do
  entry="${line#*=}"; entry="${entry//\"/}"
  addr="${entry%%:*}"; amt="${entry##*:}"
  [[ "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]] || die "address ผิดรูปแบบใน alloc.env: '$addr'"
  [[ "$amt"  =~ ^[0-9]+$ ]]            || die "จำนวนผิดรูปแบบใน alloc.env: '$amt'"
  PREMINE_ARGS+=(--premine "${addr}:${amt}000000000000000000")
  TOTAL=$((TOTAL + amt))
  printf "  %-46s %18s\n" "$addr" "$(printf "%'d" "$amt")"
done < <(grep -E '^ALLOC_[A-Z_]+=' "$ALLOC_ENV")

for i in $(seq 1 "$VALIDATOR_COUNT"); do
  idx=$((i-1))
  PREMINE_ARGS+=(--premine "${ADDRS[$idx]}:${VALIDATOR_PREMINE}000000000000000000")
  TOTAL=$((TOTAL + VALIDATOR_PREMINE))
  printf "  %-46s %18s  (validator-%d)\n" "${ADDRS[$idx]}" "$(printf "%'d" "$VALIDATOR_PREMINE")" "$i"
done
printf "  %-46s %18s\n" "" "=================="
printf "  %-46s %18s\n" "รวม" "$(printf "%'d" "$TOTAL")"

[[ "$TOTAL" -eq "$TOTAL_SUPPLY" ]] || \
  die "ยอดรวมไม่ตรง: ได้ $TOTAL แต่ TOTAL_SUPPLY=$TOTAL_SUPPLY — แก้ alloc.env ก่อน"

# ── 4. ยืนยันด้วยมือ (โหมดจริงเท่านั้น) ─────────────────────────────────────────
if [[ "$LAB_MODE" -eq 0 ]]; then
  echo
  echo "  ตารางข้างบนจะกลายเป็นยอดเหรียญจริงบนเชนใหม่ และแก้ไม่ได้อีกหลังจากนี้"
  echo "  ยืนยันว่าคุณ 'ปลดล็อกได้จริง' ทุกกระเป๋าในรายการ (เคยลอง decrypt แล้ว)"
  read -r -p "  พิมพ์ YES เพื่อดำเนินการต่อ: " CONFIRM
  [[ "$CONFIRM" == "YES" ]] || die "ยกเลิกโดยผู้ใช้"
fi

# ── 5. สร้าง genesis ───────────────────────────────────────────────────────────
say "ขั้นที่ 4 — สร้าง genesis"
TMPDIR_G="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_G"' EXIT

VALIDATOR_ARGS=()
for i in $(seq 1 "$VALIDATOR_COUNT"); do
  idx=$((i-1))
  # ระบุ validator ตรงๆ ไม่ใช้ prefix-path — prefix-path คือต้นเหตุที่ทำให้ได้ set ว่าง
  VALIDATOR_ARGS+=(--ibft-validator "${ADDRS[$idx]}:${BLS[$idx]}")
done

docker run --rm -v "$TMPDIR_G:/out" "$IMG" genesis \
  --dir /out/genesis.json \
  --consensus ibft \
  --ibft-validator-type bls \
  "${VALIDATOR_ARGS[@]}" \
  --chain-id "$CHAIN_ID" \
  --name "$CHAIN_NAME" \
  --block-gas-limit "$BLOCK_GAS_LIMIT" \
  --epoch-size "$EPOCH_SIZE" \
  --block-time "$BLOCK_TIME" \
  "${BOOT_ARGS[@]}" \
  "${PREMINE_ARGS[@]}" >/dev/null

[[ -f "$TMPDIR_G/genesis.json" ]] || die "polygon-edge ไม่ได้สร้างไฟล์ออกมา"

# ── 6. ด่านตรวจสุดท้าย — ข้ามไม่ได้ ────────────────────────────────────────────
say "ขั้นที่ 5 — ตรวจ genesis ก่อนปล่อยผ่าน"
VERIFY_FLAGS=(--validators "$VALIDATOR_COUNT" --chain-id "$CHAIN_ID"
              --total-supply "$TOTAL_SUPPLY" --validator-type bls
              --expect-alloc "$ALLOC_ENV")
[[ "$LAB_MODE" -eq 0 ]] && VERIFY_FLAGS+=(--require-public-bootnodes)

if ! python3 "$VERIFY_PY" "$TMPDIR_G/genesis.json" "${VERIFY_FLAGS[@]}"; then
  cp "$TMPDIR_G/genesis.json" /tmp/genesis.REJECTED.json
  die "genesis ไม่ผ่านการตรวจ — ไฟล์ที่ถูกปฏิเสธเก็บไว้ที่ /tmp/genesis.REJECTED.json
     ห้ามนำไปใช้ นี่คือด่านเดียวกับที่ควรจะดักตอน regenesis รอบก่อนไว้ตั้งแต่แรก"
fi

mkdir -p "$(dirname "$OUT")"
cp "$TMPDIR_G/genesis.json" "$OUT"

SHA="$(sha256sum "$OUT" | cut -d' ' -f1)"
cat > "$OUT.meta" <<EOF
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sha256=$SHA
chain_id=$CHAIN_ID
validators=$VALIDATOR_COUNT
total_supply=$TOTAL_SUPPLY
lab_mode=$LAB_MODE
alloc_env_sha256=$(sha256sum "$ALLOC_ENV" | cut -d' ' -f1)
EOF

say "เสร็จ"
echo "  genesis : $OUT"
echo "  sha256  : $SHA"
echo "  meta    : $OUT.meta"
echo
echo "  ทุกโหนดต้องใช้ไฟล์ที่ sha256 ตรงกันนี้เป๊ะๆ — เทียบด้วย sha256sum ก่อนสตาร์ท"
