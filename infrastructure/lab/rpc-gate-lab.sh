#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  rpc-gate-lab.sh — พิสูจน์ด่าน RPC (njs) บน nginx จริง โดยไม่แตะเครื่องเชน
# ══════════════════════════════════════════════════════════════════════════════
#
#  tpix-rpc.test.mjs พิสูจน์ได้แค่ "ตรรกะ" ด้วยถังจำลอง ส่วนที่ขึ้นกับ njs ตัวจริง
#  (ngx.shared, incr(), โซนข้ามรอบ reload) ต้องรันบน nginx — สคริปต์นี้ทำส่วนนั้น
#  ด้วย nginx อีกตัวในโฟลเดอร์ชั่วคราว (พอร์ต 127.0.0.1:18545-18550) กับ upstream ปลอม
#  ไม่มีโหนดจริง ไม่มีธุรกรรมจริง
#
#  สิ่งที่พิสูจน์ (เดินตามลำดับของ RUNBOOK-flood-gate.md ขั้น 1b):
#    1. conf ใหม่ (เพิ่มโซน rpc_gas_budget) + reload  → โซนเกิดโดยไม่ต้อง restart
#       และตัวนับของ rpc_write_budget ไม่หาย
#    2. js ใหม่ + reload                              → งบแก๊สทำงาน, คืนงบ (incr ค่าลบ) ทำงาน
#    3. verify-rpc-gate.sh                            → ผ่านกับด่านใหม่, ไม่ผ่านกับด่านเก่า/ด่านที่ลงผิดลำดับ
#    4. ลง js ก่อนโซน (ผิดลำดับ)                      → ธุรกรรมทุกใบ 429, การอ่านยังผ่าน, ลง conf แล้วหาย
#    5. ทาง restart แทน reload                        → ใช้ได้เหมือนกัน แต่ตัวนับทุก IP ถูกล้าง
#    6. โซนเต็ม                                        → evict ทำงาน ไม่ใช่ทุกธุรกรรมได้ 500
#    7. ธุรกรรม ~100KB                                 → ถอดแก๊สได้ถูกบน njs จริง
#    8. กุญแจถังของ IPv6 = /64 (ด่าน njs)              → สองที่อยู่ใน /64 เดียวใช้โควตาจำนวนใบและงบแก๊สร่วมกัน
#       อีก /64 มีของตัวเอง · ::ffff:a.b.c.d ใช้ถังของ a.b.c.d · ด่านเดิมให้ถังใหม่ทุกที่อยู่ (ช่องที่ปิด)
#    9. กุญแจ /64 ของชั้นหยาบ (map $rpc_client_net)    → limit_req นับต่อ /64 จริง รวมที่อยู่ที่มีไบต์ 0x00 0x0a 0xff
#       ลงผิดลำดับ nginx -t ฟ้อง · เปลี่ยนกุญแจของโซนเดิมแล้ว reload ถูกปฏิเสธเงียบ ๆ (RUNBOOK ขั้น 1c)
#
#  ต้องมี: nginx + โมดูล njs รุ่นเดียวกับเครื่องจริง (Ubuntu 24.04: libnginx-mod-http-js 0.8.2),
#          curl, git, python3 หรือ node (verify-rpc-gate.sh ใช้)
#
#  ใช้:
#    bash infrastructure/lab/rpc-gate-lab.sh
#    EXPECT_NJS=0.8.2 bash infrastructure/lab/rpc-gate-lab.sh     # ไม่ผ่านถ้า njs ไม่ใช่รุ่นนี้
#    KEEP_LAB=1 ...                                               # ไม่ลบโฟลเดอร์ชั่วคราวตอนจบ
#    OLD_JS=/path/tpix-rpc.js OLD_CONF=/path/nginx-njs.conf ...   # ระบุ "ของเดิมบนเครื่อง" เอง
#
#  ไม่มี nginx+njs ในเครื่อง → รันใน container ทิ้ง:
#    docker run --rm -v "$PWD":/w -w /w ubuntu:24.04 bash -c \
#      'apt-get update -qq && apt-get install -y -qq nginx libnginx-mod-http-js curl git python3 procps \
#       && git config --global --add safe.directory /w && bash infrastructure/lab/rpc-gate-lab.sh'
#
#  exit 0 = ผ่านหมด · exit 1 = มีข้อที่ไม่ผ่าน
#
#  Developed by Xman Studio.
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
REPO="$(dirname "$INFRA")"

# "ของเดิมบนเครื่อง" = main ก่อนมีงบแก๊ส (PR #25) — ใช้จำลองสถานะเครื่องจริงก่อน deploy
OLD_REF="${OLD_REF:-38eb23b587a50ae810f17f67ad237882b80cd5c6}"
NGINX="${NGINX:-$(command -v nginx || echo /usr/sbin/nginx)}"
NJS_MODULE="${NJS_MODULE:-/usr/lib/nginx/modules/ngx_http_js_module.so}"
EXPECT_NJS="${EXPECT_NJS:-}"

GATE_PORT=18545
STUB_PORT=18546
PROBE_PORT=18547
NET_PORT=18548     # ขั้น 7: โซนเข้ม (1 คำขอ/นาที) ที่ใช้กุญแจ $rpc_client_net
ADDR_PORT=18550    # ขั้น 7: โซนเข้มแบบเดียวกันที่ใช้กุญแจ $binary_remote_addr (ตัวเทียบ)
GATE="http://127.0.0.1:$GATE_PORT"
PROBE="http://127.0.0.1:$PROBE_PORT/probe"

PASS=0
FAIL=0

die()  { echo -e "\n❌ $*\n" >&2; exit 1; }
say()  { echo -e "\n── $* ──"; }
ok()   { printf '  ✔ %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  ✘ %s\n' "$1"; [ -n "${2:-}" ] && printf '      → %s\n' "$2"; FAIL=$((FAIL + 1)); }

[ -x "$NGINX" ] || die "ไม่พบ nginx ($NGINX)"
[ -f "$NJS_MODULE" ] || die "ไม่พบโมดูล njs ($NJS_MODULE) — ติดตั้ง libnginx-mod-http-js หรือระบุ NJS_MODULE"
command -v curl >/dev/null || die "ไม่พบ curl"

LAB="$(mktemp -d "${TMPDIR:-/tmp}/tpix-gate-lab.XXXXXX")"
ERR="$LAB/error.log"
mkdir -p "$LAB/conf.d" "$LAB/njs" "$LAB/tmp" "$LAB/src" "$LAB/alt"
: > "$ERR"

cleanup() {
    if [ -f "$LAB/nginx.pid" ]; then
        kill -QUIT "$(cat "$LAB/nginx.pid")" 2>/dev/null || true
        sleep 0.5
    fi
    if [ "${KEEP_LAB:-0}" = "1" ]; then
        echo "lab อยู่ที่ $LAB"
    else
        rm -rf "$LAB"
    fi
}
trap cleanup EXIT

# ── ไฟล์ต้นทาง: ของเดิม (main ก่อน PR) กับของใหม่ (working tree) ────────────────
old_file() {
    git -C "$REPO" show "$OLD_REF:$1" 2>/dev/null
}
if [ -n "${OLD_JS:-}" ]; then cp "$OLD_JS" "$LAB/src/old.js"; else
    old_file infrastructure/njs/tpix-rpc.js > "$LAB/src/old.js" \
        || die "อ่าน $OLD_REF ไม่ได้ (clone แบบ shallow?) — git fetch --unshallow หรือระบุ OLD_JS/OLD_CONF"
fi
if [ -n "${OLD_CONF:-}" ]; then cp "$OLD_CONF" "$LAB/src/old.conf"; else
    old_file infrastructure/single-host/nginx-njs.conf > "$LAB/src/old.conf" \
        || die "อ่าน nginx-njs.conf จาก $OLD_REF ไม่ได้"
fi
cp "$INFRA/njs/tpix-rpc.js" "$LAB/src/new.js"
cp "$INFRA/single-host/nginx-njs.conf" "$LAB/src/new.conf"

grep -q 'rpc_gas_budget' "$LAB/src/old.conf" && die "OLD_CONF มีโซน rpc_gas_budget อยู่แล้ว — ไม่ใช่ของเดิมก่อน PR"
grep -q 'rpc_gas_budget' "$LAB/src/new.conf" || die "nginx-njs.conf ใน working tree ไม่มีโซน rpc_gas_budget"

# บรรทัด limit_req / limit_conn ของ vhost — เอาจากไฟล์จริง ไม่พิมพ์ซ้ำ จะได้พิสูจน์ของที่ deploy จริง
LIMIT_LINES='^[[:space:]]*limit_(req|conn)'
old_file infrastructure/single-host/nginx-rpc.conf | grep -E "$LIMIT_LINES" > "$LAB/src/old.limits"
[ -s "$LAB/src/old.limits" ] || printf '%s\n' 'limit_req  zone=rpc_per_ip burst=60 nodelay;' 'limit_req_status 429;' \
    'limit_conn rpc_conn_per_ip 10;' 'limit_conn_status 429;' > "$LAB/src/old.limits"
grep -E "$LIMIT_LINES" "$INFRA/single-host/nginx-rpc.conf" > "$LAB/src/new.limits"
grep -q 'zone=rpc_per_ip' "$LAB/src/old.limits"  || die "nginx-rpc.conf ของเดิมไม่ได้ใช้โซน rpc_per_ip"
grep -q 'zone=rpc_per_net' "$LAB/src/new.limits" || die "nginx-rpc.conf ใน working tree ไม่ได้ใช้โซน rpc_per_net"
grep -q 'rpc_conn_per_net' "$LAB/src/new.limits" || die "nginx-rpc.conf ใน working tree ไม่ได้ใช้โซน rpc_conn_per_net"

# ไฟล์จริงชี้ js ที่ /etc/nginx/njs/ — lab แก้เฉพาะ path นี้ ที่เหลือใช้ตามไฟล์จริงทุกบรรทัด
install_conf() { sed "s#/etc/nginx/njs/#$LAB/njs/#g" "$LAB/src/$1.conf" > "$LAB/conf.d/05-tpix-njs.conf"; }
install_js()   { cp "$LAB/src/$1.js" "$LAB/njs/tpix-rpc.js"; }

# ── ตัวส่องโซน (ใช้เฉพาะใน lab) ───────────────────────────────────────────────
cat > "$LAB/njs/probe.js" <<'EOF'
function zoneType(name) {
    try { return typeof ngx.shared[name]; } catch (e) { return 'throws ' + e; }
}
function attempt(fn) {
    try { return String(fn()); } catch (e) { return 'ERR ' + e; }
}
function run(r) {
    var op = r.args.op;
    var k = r.args.k || 'k';
    var out = [];
    if (op === 'info') {
        out.push('njs=' + njs.version);
        out.push('write=' + zoneType('rpc_write_budget'));
        out.push('gas=' + zoneType('rpc_gas_budget'));
        out.push('missing=' + zoneType('lab_no_such_zone'));
    } else if (op === 'incr') {
        var d = ngx.shared.lab_probe;
        out.push('plus=' + attempt(function () { return d.incr(k, 10000000, 0); }));
        out.push('minus=' + attempt(function () { return d.incr(k, -10000000, 0); }));
        out.push('below=' + attempt(function () { return d.incr(k, -21000, 0); }));
        out.push('fresh=' + attempt(function () { return d.incr(k + 'f', -5, 0); }));
        out.push('get=' + attempt(function () { return d.get(k); }));
    } else if (op === 'put') {
        out.push('put=' + attempt(function () { return ngx.shared[r.args.zone].incr(k, Number(r.args.v), 0); }));
    } else if (op === 'get') {
        out.push('get=' + attempt(function () { return ngx.shared[r.args.zone].get(k); }));
    } else if (op === 'fill') {
        var f = ngx.shared.lab_fill;
        var n = Number(r.args.n);
        var firstErr = 'none';
        var done = 0;
        for (var i = 0; i < n; i++) {
            try { f.incr(k + i, 1, 0); done++; } catch (e) { firstErr = i + ' ' + e; break; }
        }
        out.push('done=' + done);
        out.push('firstErr=' + firstErr);
        out.push('oldest=' + attempt(function () { return f.get(k + 0); }));
        out.push('newest=' + attempt(function () { return f.get(k + (done - 1)); }));
        out.push('size=' + attempt(function () { return f.size(); }));
    }
    r.headersOut['Content-Type'] = 'text/plain';
    r.return(200, out.join('\n') + '\n');
}
export default { run };
EOF

# ── nginx.conf ของ lab — server block ลอกจาก single-host/nginx-rpc.conf (ตัด TLS ออก) ──
cat > "$LAB/nginx.conf" <<EOF
load_module $NJS_MODULE;
worker_processes 2;
pid $LAB/nginx.pid;
error_log $ERR notice;
events { worker_connections 256; }
http {
    client_body_temp_path $LAB/tmp/body;
    proxy_temp_path       $LAB/tmp/proxy;
    fastcgi_temp_path     $LAB/tmp/fastcgi;
    uwsgi_temp_path       $LAB/tmp/uwsgi;
    scgi_temp_path        $LAB/tmp/scgi;

    # เครื่องจริง: 00-cloudflare-realip.conf (ช่วง IP ของ Cloudflare) — lab ให้ 127.0.0.1 เป็น "Cloudflare"
    # เพื่อให้แต่ละชุดทดสอบใช้ IP ของตัวเองผ่าน CF-Connecting-IP ได้
    set_real_ip_from 127.0.0.1;
    real_ip_header   CF-Connecting-IP;

    include $LAB/conf.d/*.conf;

    js_import labprobe from $LAB/njs/probe.js;
    js_shared_dict_zone zone=lab_probe:1m timeout=60s type=number evict;
    js_shared_dict_zone zone=lab_fill:64k timeout=60s type=number evict;

    limit_req_zone  \$binary_remote_addr zone=rpc_per_ip:10m rate=30r/s;
    limit_conn_zone \$binary_remote_addr zone=rpc_conn_per_ip:10m;

    upstream tpix_rpc {
        least_conn;
        server 127.0.0.1:$STUB_PORT max_fails=2 fail_timeout=10s;
        keepalive 16;
    }

    server {
        listen 127.0.0.1:$GATE_PORT;

        client_max_body_size         128k;
        client_body_buffer_size      128k;
        client_body_in_single_buffer on;
        client_body_timeout          10s;
        client_header_timeout        10s;
        subrequest_output_buffer_size 1m;

        limit_req  zone=rpc_per_ip burst=60 nodelay;
        limit_req_status 429;
        limit_conn rpc_conn_per_ip 10;
        limit_conn_status 429;

        access_log $LAB/access.log tpixgate;

        location = /health {
            access_log off;
            default_type application/json;
            return 200 '{"status":"ok"}';
        }
        location / {
            js_content tpix.gate;
        }
        location = /__rpc_upstream {
            internal;
            access_log off;
            proxy_pass http://tpix_rpc;
            proxy_http_version 1.1;
            proxy_set_header Host       \$host;
            proxy_set_header Connection "";
            proxy_hide_header Access-Control-Allow-Origin;
            proxy_hide_header Access-Control-Allow-Methods;
            proxy_hide_header Access-Control-Allow-Headers;
        }
    }

    # upstream ปลอม — ตอบ 200 ทุกคำขอ (ด่านเป็นตัวตัดสิน ไม่ใช่โหนด)
    server {
        listen 127.0.0.1:$STUB_PORT;
        access_log $LAB/stub.log;
        location / {
            default_type application/json;
            return 200 '{"jsonrpc":"2.0","id":1,"result":"0x1"}';
        }
    }

    server {
        listen 127.0.0.1:$PROBE_PORT;
        access_log off;
        location = /probe { js_content labprobe.run; }
    }
}
EOF

ngx() { "$NGINX" -p "$LAB" -c "$LAB/nginx.conf" -e "$ERR" "$@"; }

config_test() {
    # config_test <ชื่อ> — nginx -t ต้องผ่าน
    if ngx -t >"$LAB/t.out" 2>&1; then ok "$1: nginx -t ผ่าน"; else bad "$1: nginx -t ไม่ผ่าน" "$(tail -n 3 "$LAB/t.out")"; fi
}

start() {
    : > "$ERR"; LOGMARK=0
    ngx || die "nginx ไม่สตาร์ท: $(tail -n 5 "$ERR")"
    for _ in $(seq 1 50); do
        [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' "$GATE/health" 2>/dev/null)" = "200" ] && return 0
        sleep 0.1
    done
    die "nginx สตาร์ทแล้วแต่ /health ไม่ตอบ: $(tail -n 5 "$ERR")"
}

stop() {
    [ -f "$LAB/nginx.pid" ] || return 0
    local pid; pid="$(cat "$LAB/nginx.pid")"
    kill -QUIT "$pid" 2>/dev/null || true
    for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
    rm -f "$LAB/nginx.pid"
}

workers() { ps -o pid= --ppid "$(cat "$LAB/nginx.pid")" 2>/dev/null | tr -s ' \n' ' '; }

reload() {
    # reload <ชื่อ> — ส่ง HUP แบบเดียวกับ systemctl reload แล้วยืนยันว่า worker ชุดเก่าถูกแทนจริง
    # (reload ที่ config ถูกปฏิเสธ worker ชุดเก่าจะวิ่งต่อเงียบ ๆ — exit code บอกไม่ได้)
    local old new p swapped=0
    old="$(workers)"
    kill -HUP "$(cat "$LAB/nginx.pid")"
    for _ in $(seq 1 100); do
        sleep 0.1
        new="$(workers)"
        swapped=1
        for p in $old; do case " $new " in *" $p "*) swapped=0 ;; esac; done
        [ -z "${new// /}" ] && swapped=0
        [ "$swapped" = "1" ] && break
    done
    if [ "$swapped" = "1" ]; then ok "$1: reload แล้ว worker ชุดใหม่ขึ้นแทน"; else
        bad "$1: reload แล้ว worker ชุดเก่ายังวิ่งอยู่ (config ถูกปฏิเสธ?)" "$(grep -E '\[(emerg|alert|crit)\]' "$ERR" | tail -n 3)"
    fi
}

reload_rejected() {
    # reload_rejected <ชื่อ> <ข้อความที่ต้องมีใน error log> — reload ที่ nginx ต้องปฏิเสธ:
    # worker ชุดเดิมต้องยังอยู่ครบ และ error log ต้องบอกสาเหตุ (exit code ของ reload บอกไม่ได้)
    local old new p kept=1 fresh
    old="$(workers)"
    kill -HUP "$(cat "$LAB/nginx.pid")"
    sleep 2
    new="$(workers)"
    [ -z "${old// /}" ] && kept=0
    for p in $old; do case " $new " in *" $p "*) ;; *) kept=0 ;; esac; done
    fresh="$(tail -n +"$((LOGMARK + 1))" "$ERR")"
    LOGMARK="$(wc -l < "$ERR")"
    if [ "$kept" = "1" ] && printf '%s\n' "$fresh" | grep -qF -- "$2"; then
        ok "$1: nginx ปฏิเสธ config ใหม่ worker ชุดเดิมวิ่งต่อ"
        printf '%s\n' "$fresh" | grep -F -- "$2" | head -n 1 | sed 's/^/    │ /'
    else
        bad "$1: reload ควรถูกปฏิเสธ (worker เดิม: $old · หลัง reload: $new)" "$(printf '%s\n' "$fresh" | tail -n 3)"
    fi
}

LOGMARK=0
log_clean() {
    # log_clean <ชื่อ> [ข้อความของบรรทัดที่ตั้งใจให้เกิด] — error log ตั้งแต่เช็กครั้งก่อนต้องไม่มี
    # emerg/alert/crit/error หรือ js exception นอกจากบรรทัดที่มีข้อความนั้น
    local fresh
    fresh="$(tail -n +"$((LOGMARK + 1))" "$ERR")"
    LOGMARK="$(wc -l < "$ERR")"
    [ -n "${2:-}" ] && fresh="$(printf '%s\n' "$fresh" | grep -vF -- "$2")"
    if printf '%s\n' "$fresh" | grep -E '\[(emerg|alert|crit|error)\]|js exception' > "$LAB/log.bad"; then
        bad "$1: error log มีข้อผิดพลาด" "$(head -n 3 "$LAB/log.bad")"
    else
        ok "$1: error log สะอาด"
    fi
}

align() {
    # align <หน้าต่าง วิ> <ต้องเหลือ วิ> — ถ้าใกล้ขอบหน้าต่างเกินไปให้รอขึ้นหน้าต่างใหม่ก่อน
    local left=$(( $1 - $(date +%s) % $1 ))
    [ "$left" -ge "$2" ] || sleep "$left"
}

rawtx() {
    # rawtx <gas> → ธุรกรรม legacy ที่ gasLimit = <gas> (ลายเซ็นปลอม — ด่านไม่ตรวจลายเซ็น upstream ก็ปลอม)
    local g body
    g="$(printf '%x' "$1")"
    [ $(( ${#g} % 2 )) -eq 1 ] && g="0$g"
    body="8080$(printf '%02x' $(( 0x80 + ${#g} / 2 )))${g}94000000000000000000000000000000000000dead8080010101"
    printf '0x%02x%s' $(( 0xc0 + ${#body} / 2 )) "$body"
}
bigtx() {
    # bigtx <gas> → ธุรกรรม legacy ที่ data ยาว 50,000 ไบต์ — JSON ราว 100KB ใกล้เพดาน body 128k ของ vhost
    # (gas ต้องเป็นเลข 3 ไบต์: 65,536 – 16,777,215)
    local g body
    g="$(printf '%06x' "$1")"
    body="808083${g}94000000000000000000000000000000000000dead80b9c350$(printf '%0100000d' 0)010101"
    printf '0xf9%04x%s' $(( ${#body} / 2 )) "$body"
}
send()  { printf '{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["%s"],"id":1}' "$1"; }
tx()    { send "$(rawtx "$1")"; }
batch() {
    # batch <gas> <gas> ... → batch ของ eth_sendRawTransaction
    local out="[" first=1 g
    for g in "$@"; do
        [ "$first" = "1" ] || out="$out,"
        out="$out$(tx "$g")"; first=0
    done
    printf '%s]' "$out"
}
READ='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
JUNK="$(send 0xdeadbeef)"

expect() {
    # expect <ชื่อ> <รหัส HTTP> <ข้อความใน body หรือ -> <IP ผู้ใช้> <payload>
    local name="$1" want="$2" sub="$3" ip="$4" data="$5" got body
    printf '%s' "$data" > "$LAB/req"       # ผ่านไฟล์ — ธุรกรรม ~100KB ยาวเกินจะส่งเป็นอาร์กิวเมนต์
    got="$(curl -s -m 10 -o "$LAB/reply" -w '%{http_code}' -X POST "$GATE/" \
        -H 'Content-Type: application/json' -H "CF-Connecting-IP: $ip" --data-binary @"$LAB/req" 2>/dev/null)" || got="000"
    body="$(head -c 300 "$LAB/reply" 2>/dev/null)"
    if [ "$got" != "$want" ]; then
        bad "$name" "ได้ $got (ควรได้ $want) $body"
    elif [ "$sub" != "-" ] && [ "${body#*"$sub"}" = "$body" ]; then
        bad "$name" "รหัส $got ถูก แต่ body ไม่มี \"$sub\": $body"
    else
        ok "$name ($got)"
    fi
}

burst() {
    # burst <IP ผู้ใช้> <จำนวน> → พิมพ์จำนวนใบที่ได้ 200 (ส่งโอน 21k ทีละใบ)
    local n=0 code
    for _ in $(seq 1 "$2"); do
        code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST "$GATE/" -H 'Content-Type: application/json' \
            -H "CF-Connecting-IP: $1" --data "$(tx 21000)" 2>/dev/null)" || code="000"
        [ "$code" = "200" ] && n=$((n + 1))
    done
    printf '%s' "$n"
}
count_is() {
    # count_is <ชื่อ> <ที่ได้> <ที่ต้องได้>
    if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1" "ได้ $2 (ควรได้ $3)"; fi
}
hit() {
    # hit <ชื่อ> <รหัส HTTP> <พอร์ต> <IP ผู้ใช้> — GET เปล่า ๆ ใช้กับโซนเข้มของขั้น 7
    local got
    got="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$3/" -H "CF-Connecting-IP: $4" 2>/dev/null)" || got="000"
    if [ "$got" = "$2" ]; then ok "$1 ($got)"; else bad "$1" "ได้ $got (ควรได้ $2)"; fi
}

probe() { curl -s -m 10 "$PROBE?$1" 2>/dev/null; }
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n 1; }
probe_is() {
    # probe_is <ชื่อ> <ผล probe> <ช่อง> <ค่าที่ต้องได้>
    local got; got="$(field "$2" "$3")"
    if [ "$got" = "$4" ]; then ok "$1 ($3=$got)"; else bad "$1" "$3=$got (ควรได้ $4)"; fi
}

run_verify() {
    # run_verify <ชื่อ> <exit ที่ต้องได้> <ข้อความที่ต้องมีในผล หรือ ->
    local name="$1" want="$2" sub="$3" rc
    bash "$INFRA/scripts/verify-rpc-gate.sh" "$GATE" > "$LAB/verify.out" 2>&1
    rc=$?
    sed 's/^/    │ /' "$LAB/verify.out"
    if [ "$rc" != "$want" ]; then
        bad "$name" "verify-rpc-gate.sh exit $rc (ควรได้ $want)"
    elif [ "$sub" != "-" ] && ! grep -qF -- "$sub" "$LAB/verify.out"; then
        bad "$name" "exit $rc ถูก แต่ผลไม่มีข้อความ \"$sub\""
    else
        ok "$name (exit $rc)"
    fi
}

gas_checks() {
    # gas_checks <ชื่อชุด> <คำนำหน้า IP> — ชุดตรวจงบแก๊สที่ใช้ซ้ำหลังทุกทาง deploy
    local s="$1" ip="$2"
    expect "$s: โอน 21k ผ่าน" 200 - "$ip.1" "$(tx 21000)"
    align 60 5
    expect "$s: ขยะใบแรก (คิด 10M) ผ่าน" 200 - "$ip.2" "$JUNK"
    expect "$s: ขยะใบที่สองโดนงบแก๊สตัด" 429 'gas rate limit exceeded' "$ip.2" "$JUNK"
}

echo "══ lab ด่าน RPC ══"
"$NGINX" -v 2>&1 | sed 's/^/  /'
command -v dpkg-query >/dev/null && dpkg-query -W -f='  ${Package} ${Version}\n' nginx libnginx-mod-http-js 2>/dev/null
echo "  ของเดิม = $OLD_REF"

# ══ 1. สถานะเครื่องจริงวันนี้: conf เดิม + js เดิม ══════════════════════════════
say "1. ของเดิม (conf เดิม + js เดิม)"
install_conf old; install_js old
config_test "ของเดิม"
start
INFO="$(probe 'op=info')"
NJS_VERSION="$(field "$INFO" njs)"
echo "  njs $NJS_VERSION"
if [ -n "$EXPECT_NJS" ]; then
    if [ "$NJS_VERSION" = "$EXPECT_NJS" ]; then ok "njs เป็นรุ่น $EXPECT_NJS ตามเครื่องจริง"; else
        bad "njs เป็นรุ่น $NJS_VERSION ไม่ใช่ $EXPECT_NJS" "ผลของ lab นี้ใช้ยืนยันเครื่องจริงไม่ได้ — หา image ที่มี njs $EXPECT_NJS"
    fi
fi
probe_is "โซน rpc_write_budget มีอยู่" "$INFO" write object
probe_is "โซน rpc_gas_budget ยังไม่มี" "$INFO" gas undefined
expect "อ่านผ่าน" 200 - 10.0.0.1 "$READ"
expect "โอน 21k ผ่าน" 200 - 10.0.0.1 "$(tx 21000)"
expect "ด่านเดิมไม่มีงบแก๊ส: ขยะใบแรกผ่าน" 200 - 10.0.0.2 "$JUNK"
expect "ด่านเดิมไม่มีงบแก๊ส: ขยะใบที่สองก็ผ่าน" 200 - 10.0.0.2 "$JUNK"
# ช่องที่กุญแจ /64 ปิด — ด่านเดิมใช้ที่อยู่เต็ม (/128) เป็นกุญแจ: เปลี่ยนที่อยู่ใน /64 เดิม = ได้ถังใหม่
align 10 4
count_is "ด่านเดิม: IPv6 ที่อยู่เดียว 10 ใบแรกผ่าน" "$(burst 2001:db8:0:1::1 10)" 10
expect "ด่านเดิม: ใบที่ 11 จากที่อยู่เดิมโดนตัด" 429 'write rate limit exceeded' 2001:db8:0:1::1 "$(tx 21000)"
expect "ด่านเดิม (ช่องโหว่): ที่อยู่อื่นใน /64 เดียวกันได้ถังใหม่" 200 - 2001:db8:0:1::2 "$(tx 21000)"
log_clean "ของเดิม"

say "1b. verify-rpc-gate.sh ต้องฟ้องว่าด่านเดิมไม่มีงบแก๊ส"
run_verify "verify กับด่านเดิม: ไม่ผ่าน" 1 'ส่ง 3 ใบไม่โดนตัดเลย'

# ══ 2. ขั้น 1b ข้อ 1: conf ใหม่ + reload (js ยังเป็นตัวเดิม) ═════════════════════
say "2. conf ใหม่ + reload (js เดิม)"
install_conf new
config_test "conf ใหม่"
# ฝากค่าชิด reload — โซนนี้ timeout=10s และ get() มองไม่เห็นกุญแจที่หมดอายุ
# ถ้าฝากไว้นานกว่านั้นจะอ่านผลผิดว่า reload ล้างโซน
probe_is "ฝากค่าไว้ในโซน rpc_write_budget ก่อน reload" "$(probe 'op=put&zone=rpc_write_budget&k=labkeep&v=7')" put 7
reload "conf ใหม่"
probe_is "ตัวนับใน rpc_write_budget ไม่หายข้ามรอบ reload" "$(probe 'op=get&zone=rpc_write_budget&k=labkeep')" get 7
probe_is "และนับต่อจากค่าเดิม" "$(probe 'op=put&zone=rpc_write_budget&k=labkeep&v=1')" put 8
INFO="$(probe 'op=info')"
probe_is "โซน rpc_gas_budget เกิดด้วย reload (ไม่ต้อง restart)" "$INFO" gas object
expect "js เดิมยังรับธุรกรรมตามปกติ" 200 - 10.0.1.1 "$(tx 21000)"
expect "js เดิม: ขยะสองใบยังผ่าน (ยังไม่มีอะไรเปลี่ยนสำหรับผู้ใช้)" 200 - 10.0.1.2 "$JUNK"
expect "js เดิม: ขยะใบที่สอง" 200 - 10.0.1.2 "$JUNK"
log_clean "conf ใหม่"

# ══ 3. ขั้น 1b ข้อ 2: js ใหม่ + reload ═══════════════════════════════════════════
say "3. js ใหม่ + reload"
install_js new
config_test "js ใหม่"
reload "js ใหม่"
gas_checks "ทาง reload" 10.1.0
ROLL_WINDOW=$(( $(date +%s) / 60 ))

align 60 5
expect "คืนงบ: 5M ผ่าน" 200 - 10.1.1.1 "$(tx 5000000)"
expect "คืนงบ: 10M เกินงบที่เหลือ โดนตัด" 429 'gas rate limit exceeded' 10.1.1.1 "$(tx 10000000)"
expect "คืนงบ: ใบเล็กที่ตามมายังผ่าน (ใบที่โดนตัดไม่กินงบ)" 200 - 10.1.1.1 "$(tx 21000)"
expect "คืนงบ: ใช้ได้ครบ 12M พอดี" 200 - 10.1.1.1 "$(tx 6979000)"
expect "คืนงบ: งบหมดแล้ว ใบเล็กก็โดนตัด" 429 'gas rate limit exceeded' 10.1.1.1 "$(tx 21000)"

align 60 5
expect "แก๊สเกินบล็อก (10,000,001) ได้ 400" 400 'above block gas limit' 10.1.2.1 "$(tx 10000001)"
expect "ใบที่ได้ 400 ไม่กินงบ: 10M ยังผ่าน" 200 - 10.1.2.1 "$(tx 10000000)"

align 60 5
expect "batch 5M+5M ผ่าน" 200 - 10.1.3.1 "$(batch 5000000 5000000)"
expect "batch 21k+5M เกินงบ โดนตัดทั้งชุด" 429 'gas rate limit exceeded' 10.1.3.1 "$(batch 21000 5000000)"
expect "batch ที่โดนตัดคืนงบ: 21k ยังผ่าน" 200 - 10.1.3.1 "$(tx 21000)"

align 60 5
expect "ธุรกรรม ~100KB (5M gas) ผ่าน" 200 - 10.1.5.1 "$(send "$(bigtx 5000000)")"
expect "ธุรกรรม ~100KB ถูกคิด 5M จริง: 7,000,001 เกินงบ" 429 'gas rate limit exceeded' 10.1.5.1 "$(tx 7000001)"
expect "ธุรกรรม ~100KB ถูกคิด 5M จริง: 7,000,000 พอดีงบ" 200 - 10.1.5.1 "$(tx 7000000)"

align 10 4
WRITE_OK=1
for _ in $(seq 1 10); do
    code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST "$GATE/" -H 'Content-Type: application/json' \
        -H 'CF-Connecting-IP: 10.1.4.1' --data "$(tx 21000)")"
    [ "$code" = "200" ] || WRITE_OK=0
done
if [ "$WRITE_OK" = "1" ]; then ok "โควตาจำนวนใบ: 10 ใบแรกผ่าน"; else bad "โควตาจำนวนใบ: 10 ใบแรกต้องผ่านทั้งหมด"; fi
expect "โควตาจำนวนใบ: ใบที่ 11 โดนตัด" 429 'write rate limit exceeded' 10.1.4.1 "$(tx 21000)"
expect "อ่านยังผ่านหลังโควตาเต็ม" 200 - 10.1.4.1 "$READ"

# ── กุญแจถังของ IPv6 = /64 — ทั้งโควตาจำนวนใบและงบแก๊ส (addressKey ใน tpix-rpc.js) ──
align 10 4
count_is "IPv6 /64: 10 ใบแรกจากที่อยู่แรกผ่าน" "$(burst 2001:db8:64:1::1 10)" 10
expect "IPv6 /64: ที่อยู่อื่นใน /64 เดียวกันใช้โควตาจำนวนใบร่วมกัน" 429 'write rate limit exceeded' 2001:db8:64:1:aaaa:bbbb:cccc:dddd "$(tx 21000)"
expect "IPv6 /64: อีก /64 มีโควตาจำนวนใบของตัวเอง" 200 - 2001:db8:64:2::1 "$(tx 21000)"

align 60 5
expect "IPv6 /64: ที่อยู่แรกใช้ 10M" 200 - 2001:db8:a:1::1 "$JUNK"
expect "IPv6 /64: ที่อยู่ที่สองใน /64 เดียวกันโดนงบแก๊สเดียวกันตัด" 429 'gas rate limit exceeded' 2001:db8:a:1:aaaa:bbbb:cccc:dddd "$JUNK"
expect "IPv6 /64: รูปเต็ม + ตัวใหญ่ ของ /64 เดียวกันก็ถังเดียวกัน" 429 'gas rate limit exceeded' 2001:0DB8:000A:0001:0000:0000:0000:0003 "$JUNK"
expect "IPv6 /64: งบ 2M ที่เหลือของ /64 ใช้จากที่อยู่อื่นได้" 200 - 2001:db8:a:1::4 "$(tx 2000000)"
expect "IPv6 /64: แล้วงบก็หมดพร้อมกันทั้ง /64" 429 'gas rate limit exceeded' 2001:db8:a:1::1 "$(tx 21000)"
expect "IPv6 /64: /64 ที่ติดกันมีงบของตัวเอง" 200 - 2001:db8:a:2::1 "$JUNK"
expect "IPv6 /64: 2001:db8:a::1 อยู่ใน /64 ของ 2001:db8:a:0 ไม่ใช่ a:1 — งบของตัวเอง" 200 - 2001:db8:a::1 "$JUNK"
expect "IPv4 ที่ห่อเป็น IPv6: IPv4 ใช้ 10M" 200 - 10.1.6.1 "$JUNK"
expect "IPv4 ที่ห่อเป็น IPv6: ::ffff: ของ IPv4 เดิมใช้งบเดียวกัน" 429 'gas rate limit exceeded' ::ffff:10.1.6.1 "$JUNK"
expect "IPv4 ที่ห่อเป็น IPv6: ::ffff: ของ IPv4 อื่นไม่โดนหางเลข" 200 - ::ffff:10.1.6.2 "$JUNK"
expect "header ที่ไม่ใช่ที่อยู่ไม่ทำให้ด่านพัง" 200 - 'not:an:ip' "$(tx 21000)"

say "3b. incr() บน njs ตัวจริง"
INCR="$(probe "op=incr&k=n$$")"
printf '%s\n' "$INCR" | sed 's/^/    │ /'
probe_is "incr บวก 10M" "$INCR" plus 10000000
probe_is "incr ค่าลบ (ทางคืนงบ) ไม่โยน error" "$INCR" minus 0
probe_is "incr ค่าลบจนต่ำกว่า 0" "$INCR" below -21000
probe_is "incr ค่าลบบนกุญแจใหม่" "$INCR" fresh -5

log_clean "js ใหม่"

say "3c. โซนเต็ม — ต้อง evict ไม่ใช่โยน error (error = ธุรกรรมทุกใบได้ 500)"
FILL="$(probe "op=fill&k=f$$x&n=20000")"
printf '%s\n' "$FILL" | sed 's/^/    │ /'
probe_is "สร้าง 20,000 กุญแจในโซน 64k ครบโดยไม่มี error" "$FILL" firstErr none
probe_is "กุญแจเก่าสุดถูก evict" "$FILL" oldest undefined
probe_is "กุญแจใหม่สุดยังอยู่" "$FILL" newest 1
# โซนเต็ม nginx ลง [crit] "no memory in js shared zone" ทุกครั้งที่จองไม่ได้ ก่อน njs จะ evict แล้วลองใหม่
# = เสียงรบกวนใน error log ไม่ใช่ความเสียหาย — ที่ต้องไม่มีคืออย่างอื่นนอกจากบรรทัดนี้
FRESH="$(tail -n +"$((LOGMARK + 1))" "$ERR")"
LOGMARK="$(wc -l < "$ERR")"
NOMEM="$(printf '%s\n' "$FRESH" | grep -c 'no memory in js shared zone "lab_fill"')"
OTHER="$(printf '%s\n' "$FRESH" | grep -E '\[(emerg|alert|crit|error)\]|js exception' | grep -vc 'no memory in js shared zone "lab_fill"')"
echo "    │ [crit] no memory in js shared zone: $NOMEM บรรทัด"
if [ "$OTHER" = "0" ]; then ok "โซนเต็ม: error log มีแต่ [crit] no memory ของ nginx (ไม่มี js exception)"; else
    bad "โซนเต็ม: error log มีข้อผิดพลาดอื่น" "$(printf '%s\n' "$FRESH" | grep -E '\[(emerg|alert|error)\]|js exception' | head -n 3)"
fi

say "3d. verify-rpc-gate.sh ต้องผ่านกับด่านใหม่"
run_verify "verify กับด่านใหม่: ผ่าน" 0 -

say "3e. ขึ้นนาทีใหม่ งบแก๊สเริ่มใหม่"
while [ $(( $(date +%s) / 60 )) -eq "$ROLL_WINDOW" ]; do sleep 1; done
align 60 5
expect "นาทีใหม่: IP ที่งบหมดส่งได้อีก" 200 - 10.1.0.2 "$JUNK"
expect "นาทีใหม่: แล้วก็โดนตัดเมื่อเกินงบอีกครั้ง" 429 'gas rate limit exceeded' 10.1.0.2 "$JUNK"
log_clean "นาทีใหม่"
stop

# ══ 4. ผิดลำดับ: js ใหม่ขึ้นก่อนโซน ═══════════════════════════════════════════════
say "4. ผิดลำดับ — js ใหม่ + reload โดยยังไม่มีโซน"
install_conf old; install_js old
start
install_js new
config_test "js ใหม่บน conf เดิม (nginx -t ไม่ช่วยจับ)"
reload "js ใหม่บน conf เดิม"
probe_is "โซน rpc_gas_budget ไม่มี" "$(probe 'op=info')" gas undefined
expect "fail-closed: ธุรกรรมใบแรกก็ได้ 429" 429 'gas rate limit exceeded' 10.2.0.1 "$(tx 21000)"
expect "fail-closed: ใบถัดไปก็ 429" 429 'gas rate limit exceeded' 10.2.0.2 "$(tx 21000)"
expect "fail-closed: การอ่านยังผ่าน" 200 - 10.2.0.1 "$READ"
log_clean "fail-closed"

say "4b. verify-rpc-gate.sh ต้องฟ้องการลงผิดลำดับ"
run_verify "verify กับด่านที่ลงผิดลำดับ: ไม่ผ่าน" 1 'โดนตัดตั้งแต่ใบแรก'

say "4c. แก้ด้วย conf ใหม่ + reload"
install_conf new
config_test "conf ใหม่ตามหลัง"
reload "conf ใหม่ตามหลัง"
gas_checks "หลังแก้ลำดับ" 10.2.1
log_clean "หลังแก้ลำดับ"
stop

say "4d. ผิดลำดับแบบสตาร์ทใหม่ (js ใหม่ + conf เดิม ตั้งแต่ nginx ขึ้น)"
install_conf old; install_js new
start
expect "fail-closed (สตาร์ทใหม่): ธุรกรรมได้ 429" 429 'gas rate limit exceeded' 10.2.2.1 "$(tx 21000)"
expect "fail-closed (สตาร์ทใหม่): การอ่านยังผ่าน" 200 - 10.2.2.1 "$READ"
log_clean "fail-closed (สตาร์ทใหม่)"
stop

# ══ 5. ทาง restart แทน reload ═══════════════════════════════════════════════════
say "5. conf ใหม่ + restart (แทน reload) แล้ว js ใหม่ + reload"
install_conf old; install_js old
start
probe_is "ฝากค่าไว้ก่อน restart" "$(probe 'op=put&zone=rpc_write_budget&k=labkeep&v=7')" put 7
install_conf new
config_test "conf ใหม่"
stop; start
INFO="$(probe 'op=info')"
probe_is "โซน rpc_gas_budget เกิดด้วย restart" "$INFO" gas object
probe_is "restart ล้างตัวนับทุก IP (reload ไม่ล้าง)" "$(probe 'op=get&zone=rpc_write_budget&k=labkeep')" get undefined
install_js new
reload "js ใหม่หลัง restart"
gas_checks "ทาง restart" 10.3.0
log_clean "ทาง restart"
stop

# ══ 6. nginx-http-tpix.conf (ฉบับตั้งเครื่องใหม่ทั้งลูก) ต้อง parse ผ่าน ═══════════
say "6. nginx-http-tpix.conf"
cp "$INFRA/single-host/tpix-banned.map" "$LAB/alt/tpix-banned.map"
sed -e "s#/etc/nginx/njs/#$LAB/njs/#g" \
    -e "s#/etc/nginx/conf.d/tpix-banned.map#$LAB/alt/tpix-banned.map#g" \
    -e "s#tpix-validator-[1-4]:8545#127.0.0.1:$STUB_PORT#g" \
    "$INFRA/single-host/nginx-http-tpix.conf" > "$LAB/alt/10-tpix-http.conf"
cat > "$LAB/alt/nginx.conf" <<EOF
load_module $NJS_MODULE;
pid $LAB/alt/nginx.pid;
error_log $LAB/alt/error.log notice;
events { worker_connections 64; }
http {
    client_body_temp_path $LAB/tmp/body;
    proxy_temp_path       $LAB/tmp/proxy;
    fastcgi_temp_path     $LAB/tmp/fastcgi;
    uwsgi_temp_path       $LAB/tmp/uwsgi;
    scgi_temp_path        $LAB/tmp/scgi;
    access_log off;
    include $LAB/alt/10-tpix-http.conf;
    server {
        listen 127.0.0.1:18549;
        # บรรทัด limit_* ของ nginx-rpc.conf จริง — โซนที่มันเรียกต้องมีใน nginx-http-tpix.conf
        include $LAB/src/new.limits;
        location / { js_content tpix.gate; }
        location = /__rpc_upstream { internal; proxy_pass http://tpix_rpc; }
    }
}
EOF
if "$NGINX" -p "$LAB/alt" -c "$LAB/alt/nginx.conf" -e "$LAB/alt/error.log" -t >"$LAB/t.out" 2>&1; then
    ok "nginx-http-tpix.conf + บรรทัด limit ของ nginx-rpc.conf: nginx -t ผ่าน"
else
    bad "nginx-http-tpix.conf + บรรทัด limit ของ nginx-rpc.conf: nginx -t ไม่ผ่าน" "$(tail -n 3 "$LAB/t.out")"
fi

# map $rpc_client_net มีสองสำเนา (ไฟล์ที่ deploy จริง กับฉบับตั้งเครื่องใหม่) — ขั้น 7 พิสูจน์สำเนาใน nginx-njs.conf
# สำเนาใน nginx-http-tpix.conf ต้องเหมือนกันทุกบรรทัด ไม่งั้นผลของขั้น 7 ใช้กับมันไม่ได้
map_block() { sed -n '/^# >>> rpc_client_net/,/^# <<< rpc_client_net/p' "$1" | grep -v '^#'; }
MAP_NJS="$(map_block "$INFRA/single-host/nginx-njs.conf")"
MAP_HTTP="$(map_block "$INFRA/single-host/nginx-http-tpix.conf")"
if [ -n "$MAP_NJS" ] && [ "$MAP_NJS" = "$MAP_HTTP" ]; then
    ok "map \$rpc_client_net ใน nginx-http-tpix.conf ตรงกับ nginx-njs.conf"
else
    bad "map \$rpc_client_net ใน nginx-http-tpix.conf ไม่ตรงกับ nginx-njs.conf (หรือหาบล็อกไม่เจอ)"
fi

# ══ 7. ชั้นหยาบ: limit_req / limit_conn นับ IPv6 ต่อ /64 (RUNBOOK ขั้น 1c) ════════════════
# nginx ตัวเดิม (หยุดไปแล้ว) ถูกแทนด้วย config ที่แยก "ของที่อยู่บนเครื่อง" ออกเป็นไฟล์ตามจริง:
#   conf.d/05-tpix-njs.conf   ไฟล์จริงจาก repo (ของเดิม → ของใหม่ที่มี map + โซน rpc_per_net)
#   net/host-zones.conf       แทน 10-tpix-http.conf ของเครื่อง: โซนเดิมที่กุญแจ = $binary_remote_addr
#   net/vhost-limits.conf     บรรทัด limit_* ของ nginx-rpc.conf จริง (ของเดิม → ของใหม่)
#   net/strict.conf           เฉพาะ lab: โซน 1 คำขอ/นาที ไม่มี burst ใช้กุญแจเดียวกับของจริง
#                             → คำขอที่สองที่ตกถังเดียวกันได้ 429 แน่นอน ไม่ต้องยิงแข่งกับ 30 r/s
say "7. ชั้นหยาบ — เครื่องวันนี้ (โซนเดิม กุญแจ = ที่อยู่เต็ม)"
mkdir -p "$LAB/net"
cat > "$LAB/net/host-zones.conf" <<'EOF'
limit_req_zone  $binary_remote_addr zone=rpc_per_ip:10m rate=30r/s;
limit_conn_zone $binary_remote_addr zone=rpc_conn_per_ip:10m;
EOF
cp "$LAB/src/old.limits" "$LAB/net/vhost-limits.conf"
: > "$LAB/net/strict.conf"
cat > "$LAB/nginx.conf" <<EOF
load_module $NJS_MODULE;
worker_processes 2;
pid $LAB/nginx.pid;
error_log $ERR notice;
events { worker_connections 256; }
http {
    client_body_temp_path $LAB/tmp/body;
    proxy_temp_path       $LAB/tmp/proxy;
    fastcgi_temp_path     $LAB/tmp/fastcgi;
    uwsgi_temp_path       $LAB/tmp/uwsgi;
    scgi_temp_path        $LAB/tmp/scgi;

    set_real_ip_from 127.0.0.1;
    real_ip_header   CF-Connecting-IP;

    include $LAB/conf.d/*.conf;
    include $LAB/net/host-zones.conf;
    include $LAB/net/strict.conf;

    server {
        listen 127.0.0.1:$GATE_PORT;

        client_max_body_size         128k;
        client_body_buffer_size      128k;
        client_body_in_single_buffer on;
        subrequest_output_buffer_size 1m;

        include $LAB/net/vhost-limits.conf;

        access_log $LAB/access.log tpixgate;

        location = /health {
            access_log off;
            default_type application/json;
            return 200 '{"status":"ok"}';
        }
        location / {
            js_content tpix.gate;
        }
        location = /__rpc_upstream {
            internal;
            access_log off;
            proxy_pass http://127.0.0.1:$STUB_PORT;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }

    server {
        listen 127.0.0.1:$STUB_PORT;
        access_log off;
        location / {
            default_type application/json;
            return 200 '{"jsonrpc":"2.0","id":1,"result":"0x1"}';
        }
    }
}
EOF
install_conf old; install_js old
config_test "เครื่องวันนี้"
start
expect "เครื่องวันนี้: IPv6 อ่านผ่าน" 200 - 2001:db8:70:1::1 "$READ"
log_clean "เครื่องวันนี้"

say "7b. ผิดลำดับ — vhost ใหม่ขึ้นก่อน conf ที่ประกาศโซน"
cp "$LAB/src/new.limits" "$LAB/net/vhost-limits.conf"
if ngx -t >"$LAB/t.out" 2>&1; then
    bad "vhost ใหม่บน conf เดิม: nginx -t ควรไม่ผ่าน (โซน rpc_per_net ยังไม่มี)"
elif grep -q 'rpc_per_net' "$LAB/t.out"; then
    ok "vhost ใหม่บน conf เดิม: nginx -t ไม่ผ่านและบอกชื่อโซน (พลาดแบบนี้ไม่เงียบ)"
    tail -n 2 "$LAB/t.out" | sed 's/^/    │ /'
else
    bad "vhost ใหม่บน conf เดิม: nginx -t ไม่ผ่าน แต่ไม่ได้บอกว่าเพราะโซน rpc_per_net" "$(tail -n 3 "$LAB/t.out")"
fi
cp "$LAB/src/old.limits" "$LAB/net/vhost-limits.conf"
LOGMARK="$(wc -l < "$ERR")"      # nginx -t ที่ไม่ผ่านเมื่อครู่ลง [emerg] ไว้ใน error log — ตั้งใจให้เกิด ไม่นับ

say "7c. ขั้น 1c ข้อ 1: conf ใหม่ (map + โซน rpc_per_net) + reload — vhost ยังใช้โซนเดิม"
install_conf new
config_test "conf ใหม่"
reload "conf ใหม่"
expect "conf ใหม่ vhost เดิม: IPv6 อ่านผ่าน" 200 - 2001:db8:70:1::1 "$READ"
install_js new
reload "js ใหม่"
log_clean "conf ใหม่ vhost เดิม"

say "7d. ขั้น 1c ข้อ 2: vhost ใหม่ (limit_req zone=rpc_per_net) + reload"
cp "$LAB/src/new.limits" "$LAB/net/vhost-limits.conf"
cat > "$LAB/net/strict.conf" <<EOF
limit_req_zone \$rpc_client_net     zone=lab_net:1m  rate=1r/m;
limit_req_zone \$binary_remote_addr zone=lab_addr:1m rate=1r/m;
server {
    listen 127.0.0.1:$NET_PORT;
    access_log off;
    limit_req zone=lab_net;
    limit_req_status 429;
    location / { proxy_pass http://127.0.0.1:$STUB_PORT; }
}
server {
    listen 127.0.0.1:$ADDR_PORT;
    access_log off;
    limit_req zone=lab_addr;
    limit_req_status 429;
    location / { proxy_pass http://127.0.0.1:$STUB_PORT; }
}
EOF
config_test "vhost ใหม่"
reload "vhost ใหม่"
expect "vhost ใหม่: IPv6 อ่านผ่าน" 200 - 2001:db8:70:1::1 "$READ"
expect "vhost ใหม่: IPv6 ส่งธุรกรรมผ่าน" 200 - 2001:db8:70:1::1 "$(tx 21000)"
expect "vhost ใหม่: IPv4 อ่านผ่าน" 200 - 10.7.9.1 "$READ"

say "7e. กุญแจเดิม (\$binary_remote_addr) — ที่อยู่ใหม่ใน /64 เดิมได้ถังใหม่"
hit "กุญแจเดิม: ที่อยู่แรกผ่าน" 200 "$ADDR_PORT" 2001:db8:78:1::1
hit "กุญแจเดิม: ที่อยู่เดิมซ้ำโดนตัด (โซนเข้มทำงาน)" 429 "$ADDR_PORT" 2001:db8:78:1::1
hit "กุญแจเดิม (ช่องโหว่): ที่อยู่อื่นใน /64 เดียวกันผ่าน" 200 "$ADDR_PORT" 2001:db8:78:1::2

say "7f. กุญแจใหม่ (\$rpc_client_net) — IPv6 นับต่อ /64"
hit "IPv6: ที่อยู่แรกผ่าน" 200 "$NET_PORT" 2001:db8:77:1::1
hit "IPv6: ที่อยู่อื่นใน /64 เดียวกันโดนตัด" 429 "$NET_PORT" 2001:db8:77:1:aaaa:bbbb:cccc:dddd
hit "IPv6: /64 ที่ติดกันผ่าน" 200 "$NET_PORT" 2001:db8:77:2::1
hit "IPv6: /64 ที่ต่างกันบิตเดียวผ่าน" 200 "$NET_PORT" 2001:db8:77:3::1
hit "ไบต์ 0x0a ใน /64: ที่อยู่แรกผ่าน" 200 "$NET_PORT" 2001:db8:a0a:a0a::1
hit "ไบต์ 0x0a ใน /64: ที่อยู่อื่นใน /64 เดียวกันโดนตัด" 429 "$NET_PORT" 2001:db8:a0a:a0a::2
hit "ไบต์ 0x0a ในครึ่งหลัง: ที่อยู่แรกผ่าน" 200 "$NET_PORT" 2001:db8:77:4:a0a:a0a:a0a:a0a
hit "ไบต์ 0x0a ในครึ่งหลัง: ที่อยู่อื่นใน /64 เดียวกันโดนตัด" 429 "$NET_PORT" 2001:db8:77:4::1
hit "ไบต์ 0xff: ที่อยู่แรกผ่าน" 200 "$NET_PORT" fd00:ffff:ffff:ffff::1
hit "ไบต์ 0xff: ที่อยู่อื่นใน /64 เดียวกันโดนตัด" 429 "$NET_PORT" fd00:ffff:ffff:ffff:ffff:ffff:ffff:ffff
hit "IPv4: ที่อยู่แรกผ่าน" 200 "$NET_PORT" 10.7.0.1
hit "IPv4: ที่อยู่ถัดไปผ่าน (IPv4 นับต่อที่อยู่เหมือนเดิม)" 200 "$NET_PORT" 10.7.0.2
hit "IPv4: ที่อยู่เดิมซ้ำโดนตัด" 429 "$NET_PORT" 10.7.0.1
hit "IPv4 ที่มีไบต์ 0x0a: ผ่าน" 200 "$NET_PORT" 10.10.10.10
hit "IPv4 ที่มีไบต์ 0x0a: ซ้ำโดนตัด" 429 "$NET_PORT" 10.10.10.10
hit "::ffff: ของ IPv4 ที่ใช้ไปแล้วโดนตัด (ถังเดียวกับ IPv4 ตัวนั้น)" 429 "$NET_PORT" ::ffff:10.7.0.1
hit "::ffff: ของ IPv4 อื่นผ่าน" 200 "$NET_PORT" ::ffff:10.7.0.3
hit "::ffff: ของ IPv4 อีกตัวก็ผ่าน (ไม่กองรวมใน ::/64)" 200 "$NET_PORT" ::ffff:10.7.0.4
# limit_req ลง [error] "limiting requests" ทุกครั้งที่ตัด — คือ 429 ที่ตั้งใจข้างบน ที่ต้องไม่มีคืออย่างอื่น
log_clean "ชั้นหยาบ กุญแจใหม่" 'limiting requests, excess'

say "7g. กับดัก — แก้กุญแจของโซนเดิม (rpc_per_ip) แทนการเพิ่มโซนชื่อใหม่ แล้ว reload"
cat > "$LAB/net/host-zones.conf" <<'EOF'
limit_req_zone  $rpc_client_net     zone=rpc_per_ip:10m rate=30r/s;
limit_conn_zone $binary_remote_addr zone=rpc_conn_per_ip:10m;
EOF
config_test "แก้กุญแจโซนเดิม (nginx -t ไม่ช่วยจับ)"
reload_rejected "แก้กุญแจโซนเดิม" 'while previously it used'
expect "หลัง reload ที่ถูกปฏิเสธ: ด่านยังตอบด้วย config เดิม" 200 - 2001:db8:70:1::1 "$READ"
stop

echo
echo "══ ผ่าน $PASS · ไม่ผ่าน $FAIL ══"
if [ "$FAIL" -ne 0 ]; then
    echo
    echo "── error log 40 บรรทัดสุดท้าย ──"
    tail -n 40 "$ERR" 2>/dev/null
    exit 1
fi
