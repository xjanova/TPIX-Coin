#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  พิสูจน์ว่าด่าน RPC ทำงานจริง — รันหลัง reload nginx ทุกครั้ง
#
#  ทำไมต้องมี: ตัวกรองรุ่นก่อนหน้าถูก "ติดตั้งสำเร็จ" และ nginx -t ผ่าน
#  แต่บล็อกทุกคำขอ เพราะ $request_body ว่างในเฟสที่ if ทำงาน
#  nginx -t ตรวจแค่ไวยากรณ์ ไม่ได้ตรวจว่าด่านตัดสินถูกไหม
#
#  ใช้งาน:
#    bash verify-rpc-gate.sh                          # ยิง https://rpc.tpix.online
#    bash verify-rpc-gate.sh http://127.0.0.1         # ยิง origin ตรงจากบนเครื่อง
#    ORIGIN_IP=123.253.62.252 bash verify-rpc-gate.sh # ตรวจว่าปิดทางยิงตรงแล้ว
#
#  exit 0 = ผ่านหมด · exit 1 = มีข้อที่ไม่ผ่าน (รายละเอียดอยู่ในผลลัพธ์)
#
#  Developed by Xman Studio.
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

TARGET="${1:-https://rpc.tpix.online}"
# ⚠️ ต้องเป็น UA แบบเบราว์เซอร์ — Cloudflare หน้า rpc.tpix.online มี bot rule
#    ที่ตอบ 403 ให้ UA ปริยายของ curl ถ้าไม่ตั้งจะนึกว่าด่านเราพัง ทั้งที่ nginx ตอบ 200
UA="Mozilla/5.0"
PASS=0
FAIL=0

hit() {
    # hit <payload> → พิมพ์รหัส HTTP
    curl -sk -m 12 -o /dev/null -w '%{http_code}' \
        -X POST "$TARGET" \
        -H 'Content-Type: application/json' \
        -H "User-Agent: $UA" \
        --data "$1" 2>/dev/null || echo "000"
}

check() {
    # check <ชื่อ> <รหัสที่คาดหวัง> <payload>
    local name="$1" want="$2" body="$3" got
    got=$(hit "$body")
    if [ "$got" = "$want" ]; then
        printf '  ✔ %-52s %s\n' "$name" "$got"
        PASS=$((PASS + 1))
    else
        printf '  ✘ %-52s ได้ %s (ควรได้ %s)\n' "$name" "$got" "$want"
        FAIL=$((FAIL + 1))
    fi
}

rpc()   { printf '{"jsonrpc":"2.0","method":"%s","params":[],"id":1}' "$1"; }

echo "══ ตรวจด่าน RPC ที่ $TARGET ══"
echo

echo "── เมธอดที่ต้องผ่าน ──"
check "eth_blockNumber (อ่านพื้นฐาน)"          200 "$(rpc eth_blockNumber)"
check "eth_chainId"                             200 "$(rpc eth_chainId)"
check "ibft_status (masternode-ui ใช้)"         200 "$(rpc ibft_status)"

echo
echo "── เมธอดที่ต้องถูกปฏิเสธ ──"
check "txpool_status (เคยเปิดโล่ง)"             403 "$(rpc txpool_status)"
check "admin_peers"                             403 "$(rpc admin_peers)"
check "debug_traceTransaction"                  403 "$(rpc debug_traceTransaction)"
check "eth_sendTransaction (ให้โหนดเซ็นแทน)"    403 "$(rpc eth_sendTransaction)"
check "eth_someFutureMethod (default deny)"     403 "$(rpc eth_someFutureMethod)"

echo
echo "── ช่องที่ตัวกรองรุ่น regex เคยโดนเจาะ ──"
check "ยัด method ที่อนุญาตลงใน params" 403 \
    '{"jsonrpc":"2.0","method":"admin_addPeer","params":["\"method\":\"eth_call\""],"id":1}'
check "unicode escape เลี่ยง deny-list" 403 \
    '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}'
check "batch ซ่อนเมธอดต้องห้ามไว้ท้ายชุด" 403 \
    '[{"jsonrpc":"2.0","method":"eth_chainId","id":1},{"jsonrpc":"2.0","method":"debug_traceTransaction","id":2}]'

echo
echo "── ขนาดคำขอ ──"
BATCH_OK=$(python3 -c 'import json;print(json.dumps([{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":i} for i in range(5)]))' 2>/dev/null \
    || node -e 'console.log(JSON.stringify(Array.from({length:5},(_,i)=>({jsonrpc:"2.0",method:"eth_chainId",params:[],id:i}))))')
BATCH_BIG=$(python3 -c 'import json;print(json.dumps([{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":i} for i in range(25)]))' 2>/dev/null \
    || node -e 'console.log(JSON.stringify(Array.from({length:25},(_,i)=>({jsonrpc:"2.0",method:"eth_chainId",params:[],id:i}))))')
check "batch 5 ใบ"                              200 "$BATCH_OK"
check "batch 25 ใบ (เกินเพดาน 20)"              413 "$BATCH_BIG"
check "JSON พัง"                                400 '{'

echo
echo "── โควตาเขียน: จำนวนใบ (ธุรกรรมที่โหนดปฏิเสธ ไม่เข้า mempool) ──"
# ธุรกรรมโอน 1 wei ที่เซ็นจริง (gas 21,000) จากกุญแจสุ่มที่ทิ้งไปแล้ว — บัญชียอด 0
# โหนดจึงปฏิเสธ (insufficient funds) แต่ด่านนับโควตาไปแล้ว = ทดสอบได้โดยไม่ทิ้งอะไรไว้บนเชน
# ต้องเป็นใบเล็กที่ถอดแก๊สได้ ไม่ใช่ขยะ — ขยะถูกคิดแก๊สเต็มเพดาน จะไปชนงบแก๊สก่อนโควตาจำนวนใบ
# รอให้หน้าต่างโควตาของรอบก่อนหมดอายุ ไม่งั้นจะโดนตัดตั้งแต่ใบแรกแล้วอ่านผลผิด
sleep 11
SMALL='{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["0xf861808082520894000000000000000000000000000000000000dead01808221a6a07a281bdae8308daa52e66517bb4e8bdb8d7a403d633e6a0cc15750bc287f1f9da062bfd4b92be3d1dafa914a63054407dd111273562e11e5de038645cfa97fdf28"],"id":1}'
LIMITED=0
# 21 ใบ ไม่ใช่ 14: หน้าต่างเป็นแบบคงที่ 10 วิ ถ้าขอบหน้าต่างตกกลางชุด 14 ใบอาจแบ่งเป็น 7+7 แล้วไม่โดนตัดเลย
# 21 ใบแบ่งสองฝั่งยังไงก็มีฝั่งหนึ่ง ≥ 11
for i in $(seq 1 21); do
    code=$(hit "$SMALL")
    if [ "$code" = "429" ]; then LIMITED=1; break; fi
done
if [ "$LIMITED" = "1" ] && [ "$i" -ge 2 ]; then
    printf '  ✔ %-52s ตัดที่ใบที่ %s\n' "ยิงเขียนรัวแล้วโดนตัด (429)" "$i"
    PASS=$((PASS + 1))
elif [ "$LIMITED" = "1" ]; then
    printf '  ✘ %-52s โดนตัดตั้งแต่ใบแรก\n' "ยิงเขียนรัวแล้วโดนตัด (429)"
    printf '      → ธุรกรรมทุกใบอาจโดนปฏิเสธอยู่: เช็กว่าโซน rpc_write_budget และ rpc_gas_budget\n'
    printf '        ถูกประกาศใน 05-tpix-njs.conf ครบ (โซนหาย = ด่าน fail-closed)\n'
    FAIL=$((FAIL + 1))
else
    printf '  ✘ %-52s ยิง 21 ใบไม่โดนตัดเลย\n' "ยิงเขียนรัวแล้วโดนตัด (429)"
    printf '      → เช็ก js_shared_dict_zone rpc_write_budget ใน 05-tpix-njs.conf\n'
    FAIL=$((FAIL + 1))
fi

echo
echo "── โควตาเขียน: งบแก๊ส ──"
# ขยะที่ถอดแก๊สไม่ออกถูกคิดเต็มเพดาน (10M) — งบ 12M/60 วิ จึงรับได้ใบเดียว ใบถัดไปต้องโดนตัด
# และต้องเป็นข้อความของงบแก๊ส ไม่ใช่ของโควตาจำนวนใบ (จึงรอให้หน้าต่างจำนวนใบหมดก่อน)
sleep 11
JUNK='{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["0xdeadbeef"],"id":1}'
GAS_LIMITED=0
# 3 ใบ: ถ้าขอบหน้าต่าง 60 วิตกระหว่างใบที่ 1 กับ 2 ใบที่ 3 ก็ยังต้องโดนตัด
for j in 1 2 3; do
    reply=$(curl -sk -m 12 -X POST "$TARGET" -H 'Content-Type: application/json' \
        -H "User-Agent: $UA" --data "$JUNK" 2>/dev/null || true)
    case "$reply" in
        *"gas rate limit exceeded"*) GAS_LIMITED=1; break ;;
    esac
done
if [ "$GAS_LIMITED" = "1" ] && [ "$j" -ge 2 ]; then
    printf '  ✔ %-52s ตัดที่ใบที่ %s\n' "ธุรกรรมกินแก๊สเต็มเพดานโดนตัดด้วยงบแก๊ส" "$j"
    PASS=$((PASS + 1))
elif [ "$GAS_LIMITED" = "1" ]; then
    printf '  ✘ %-52s โดนตัดตั้งแต่ใบแรก\n' "ธุรกรรมกินแก๊สเต็มเพดานโดนตัดด้วยงบแก๊ส"
    printf '      → โซน rpc_gas_budget อาจหาย (fail-closed) หรือ IP นี้เพิ่งใช้งบไปในนาทีนี้ — รอ 60 วิแล้วลองใหม่\n'
    FAIL=$((FAIL + 1))
else
    printf '  ✘ %-52s ส่ง 3 ใบไม่โดนตัดเลย\n' "ธุรกรรมกินแก๊สเต็มเพดานโดนตัดด้วยงบแก๊ส"
    printf '      → tpix-rpc.js บนเครื่องยังเป็นรุ่นที่ไม่มี spendGas หรือไม่ได้ reload nginx\n'
    FAIL=$((FAIL + 1))
fi
echo "  (IP ที่รันสคริปต์นี้จะส่งธุรกรรมใหญ่ไม่ได้ราว 1 นาทีหลังจากนี้ — งบแก๊สถูกใช้ไปกับการทดสอบ)"

# การอ่านต้องไม่โดนหางเลขจากโควตาเขียนที่เพิ่งเต็ม
sleep 1
check "อ่านยังผ่านหลังโควตาเขียนเต็ม"           200 "$(rpc eth_blockNumber)"

echo
echo "── health ──"
# ⚠️ ต้องส่ง UA ด้วย — Cloudflare bot rule ตอบ 403 ให้ UA ปริยายของ curl
#    ลืมบรรทัดนี้แล้วจะนึกว่าด่านเราพัง ทั้งที่ nginx ตอบ 200 อยู่ (เสียเวลาไล่หามาแล้ว)
HEALTH=$(curl -sk -m 8 -o /dev/null -w '%{http_code}' "$TARGET/health" -H "User-Agent: $UA" 2>/dev/null || echo "000")
if [ "$HEALTH" = "200" ]; then
    printf '  ✔ %-52s 200\n' "GET /health"
    PASS=$((PASS + 1))
else
    printf '  ✘ %-52s ได้ %s\n' "GET /health" "$HEALTH"
    FAIL=$((FAIL + 1))
fi

# ── ทางยิงตรงเข้า origin ต้องถูกปิด ────────────────────────────────────────────
if [ -n "${ORIGIN_IP:-}" ]; then
    echo
    echo "── ทางอ้อม Cloudflare ──"
    DIRECT=$(curl -sk -m 8 -o /dev/null -w '%{http_code}' \
        -X POST "https://$ORIGIN_IP/" -H 'Host: rpc.tpix.online' \
        -H "User-Agent: $UA" --data "$(rpc eth_chainId)" 2>/dev/null || echo "000")
    if [ "$DIRECT" = "200" ]; then
        printf '  ✘ %-52s ได้ 200 — ยังเดินอ้อม CF ได้\n' "ยิงตรง $ORIGIN_IP"
        printf '      → รัน scripts/allow-cloudflare-only.sh --apply\n'
        FAIL=$((FAIL + 1))
    else
        printf '  ✔ %-52s ปิดแล้ว (%s)\n' "ยิงตรง $ORIGIN_IP" "$DIRECT"
        PASS=$((PASS + 1))
    fi
fi

echo
echo "══ ผ่าน $PASS · ไม่ผ่าน $FAIL ══"
[ "$FAIL" -eq 0 ] || exit 1
