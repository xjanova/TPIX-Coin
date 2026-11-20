#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  rpc-ban-lab.sh — fail2ban แบนคนที่มาทาง Cloudflare ได้จริงไหม (nginx + fail2ban + iptables ตัวจริง)
# ══════════════════════════════════════════════════════════════════════════════
#
#  ไม่แตะเครื่องเชน: nginx อีกตัวในโฟลเดอร์ชั่วคราว (127.0.0.1:18561-18563), fail2ban อีกตัวที่ใช้
#  config/socket/ฐานข้อมูลของตัวเองในโฟลเดอร์เดียวกัน, upstream ปลอม
#  "Cloudflare" ใน lab = 127.0.0.1 — ทุกคำขอต่อเข้ามาจากที่อยู่นั้น และบอกที่อยู่ผู้ใช้ผ่าน CF-Connecting-IP
#  (เครื่องจริง: แพ็กเก็ตมาจาก IP ของ Cloudflare เพราะ ufw เปิด 80/443 ให้เฉพาะช่วงนั้น)
#
#  สิ่งที่พิสูจน์ (RUNBOOK-flood-gate.md ขั้น 3):
#    1. เครื่องวันนี้ (conf/js/vhost/jail/filter ที่ commit OLD_REF) สตาร์ทได้ jail อ่าน log ถูกไฟล์
#    2. ของเดิม: fail2ban แบนด้วย iptables-multiport แล้วคำขอของที่อยู่นั้นยังได้ 200 — IPv4 และ IPv6
#       (กฎ iptables มีจริง ตัวนับแพ็กเก็ตเป็น 0 · กฎเดียวกันบล็อกได้เมื่อ "ต้นทางของแพ็กเก็ต" ตรง)
#    3. ของเดิม: 12 ที่อยู่ใน /64 เดียวถูกปฏิเสธที่อยู่ละครั้ง → ไม่มีที่อยู่ไหนถูกแบน
#    4. ลงของใหม่ตามลำดับ conf → js → vhost → fail2ban (restart) — การแบนที่ค้างอยู่ถูกย้ายมาที่ nginx
#       แล้วมีผลทันที: 403 · IPv6 โดนทั้ง /64
#    5. ของใหม่: 12 ที่อยู่ใน /64 เดียว → แบนทั้ง /64 · /64 ข้าง ๆ ไม่โดน · IPv4 ต่อที่อยู่ · ::ffff: ไม่ใช่ทางหลบ
#       คำขอของคนที่ถูกแบนไม่ถูกนับซ้ำ · เลิกแบนแล้วใช้ได้ · บรรทัดใส่มือไม่หาย · แบน 20 ที่อยู่ติดกัน reload ไม่กี่ครั้ง
#       · หยุด fail2ban แล้วบรรทัดของมันหายหมด
#    6. ลงผิดลำดับ: vhost ใหม่ก่อน conf → nginx -t ฟ้อง · vhost ใหม่ก่อน js → เงียบ fail2ban ไม่แมตช์สักบรรทัด
#    7. nginx-http-tpix.conf (ฉบับตั้งเครื่องใหม่) + vhost จริง parse ผ่าน และบล็อก rpc_ban_log ตรงกันสองไฟล์
#
#  ที่พิสูจน์ไม่ได้ที่นี่: Cloudflare ตัวจริง, ufw ของเครื่อง, 10-tpix-http.conf ของเครื่อง (lab ใช้ไฟล์จำลอง),
#  systemctl reload nginx (lab ส่ง HUP เอง), fail2ban ภายใต้ systemd, jail อื่นบนเครื่อง
#
#  ต้องมี: nginx + libnginx-mod-http-js, fail2ban, curl, git, python3
#          ขั้น 2-3 ต้องมี root (sudo ไม่ถามรหัส) + iptables — ไม่มีก็ข้าม (REQUIRE_IPTABLES=1 = ไม่มีแล้วไม่ผ่าน)
#
#  ใช้:
#    bash infrastructure/lab/rpc-ban-lab.sh
#    REQUIRE_IPTABLES=1 bash infrastructure/lab/rpc-ban-lab.sh    # CI ใช้แบบนี้
#    KEEP_LAB=1 ...                                               # ไม่ลบโฟลเดอร์ชั่วคราวตอนจบ
#
#  exit 0 = ผ่านหมด · exit 1 = มีข้อที่ไม่ผ่าน
#
#  Developed by Xman Studio.
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$(dirname "$HERE")"
REPO="$(dirname "$INFRA")"

# "เครื่องวันนี้" = main ก่อน PR #25 — commit เดียวกับที่ rpc-gate-lab.sh ใช้
OLD_REF="${OLD_REF:-38eb23b587a50ae810f17f67ad237882b80cd5c6}"
NGINX="${NGINX:-$(command -v nginx || echo /usr/sbin/nginx)}"
NJS_MODULE="${NJS_MODULE:-/usr/lib/nginx/modules/ngx_http_js_module.so}"

GATE_PORT=18561
STUB_PORT=18562
ALT_PORT=18563
GATE="http://127.0.0.1:$GATE_PORT"

PASS=0
FAIL=0
SKIP=0

die()  { echo -e "\n❌ $*\n" >&2; exit 1; }
say()  { echo -e "\n── $* ──"; }
ok()   { printf '  ✔ %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  ✘ %s\n' "$1"; [ -n "${2:-}" ] && printf '      → %s\n' "$2"; FAIL=$((FAIL + 1)); }
skip() { printf '  ○ ข้าม: %s\n' "$1"; SKIP=$((SKIP + 1)); }
show() { sed 's/^/    │ /'; }

[ -x "$NGINX" ] || die "ไม่พบ nginx ($NGINX)"
[ -f "$NJS_MODULE" ] || die "ไม่พบโมดูล njs ($NJS_MODULE)"
for c in curl git python3 fail2ban-client fail2ban-regex; do
    command -v "$c" >/dev/null || die "ไม่พบ $c"
done

# ── สิทธิ์: fail2ban ของ lab รันเป็น root เมื่อทำได้ (action เดิมต้องเรียก iptables) ──────────
if [ "$(id -u)" = "0" ]; then SUDO=""; ROOT=1
elif sudo -n true 2>/dev/null; then SUDO="sudo -n"; ROOT=1
else SUDO=""; ROOT=0; fi
IPT=0
if [ "$ROOT" = "1" ] && command -v iptables >/dev/null && $SUDO iptables -w -S INPUT >/dev/null 2>&1; then IPT=1; fi
IPT6=0
if [ "$IPT" = "1" ] && command -v ip6tables >/dev/null && $SUDO ip6tables -w -S INPUT >/dev/null 2>&1; then IPT6=1; fi
if [ "$IPT" = "0" ] && [ "${REQUIRE_IPTABLES:-0}" = "1" ]; then
    die "REQUIRE_IPTABLES=1 แต่ใช้ iptables ไม่ได้ (root=$ROOT) — ขั้น 2-3 จะถูกข้าม ซึ่ง CI ไม่ยอม"
fi

LAB="$(mktemp -d "${TMPDIR:-/tmp}/tpix-ban-lab.XXXXXX")"
ERR="$LAB/error.log"
F2B="$LAB/f2b"
MAP="$LAB/tpix-banned.map"
ACCESS="$LAB/log/tpix-rpc.access.log"
BANNED="$LAB/log/tpix-rpc.banned.log"
mkdir -p "$LAB/conf.d" "$LAB/njs" "$LAB/tmp" "$LAB/src" "$LAB/log" "$LAB/bin" "$LAB/alt"
: > "$ERR"

f2b() { $SUDO fail2ban-client -c "$F2B" -s "$F2B/f2b.sock" -p "$F2B/f2b.pid" "$@"; }

cleanup() {
    if [ -e "$F2B/f2b.sock" ]; then f2b stop >/dev/null 2>&1 || true; fi
    if [ "$IPT" = "1" ]; then
        # ถ้า fail2ban ตายก่อนได้เก็บของ — อย่าทิ้งกฎไว้บนเครื่องที่รัน lab
        for t in iptables ip6tables; do
            command -v "$t" >/dev/null || continue
            $SUDO "$t" -w -D INPUT -p tcp -m multiport --dports "$GATE_PORT" -j f2b-tpix-rpc 2>/dev/null || true
            $SUDO "$t" -w -F f2b-tpix-rpc 2>/dev/null || true
            $SUDO "$t" -w -X f2b-tpix-rpc 2>/dev/null || true
        done
    fi
    if [ -f "$LAB/nginx.pid" ]; then
        kill -QUIT "$(cat "$LAB/nginx.pid")" 2>/dev/null || true
        sleep 0.5
    fi
    if [ "${KEEP_LAB:-0}" = "1" ]; then echo "lab อยู่ที่ $LAB"; else $SUDO rm -rf "$LAB"; fi
}
trap cleanup EXIT

# ── ไฟล์ต้นทาง: ของเดิม (OLD_REF) กับของใหม่ (working tree) ─────────────────────────
old_file() { git -C "$REPO" show "$OLD_REF:$1" 2>/dev/null; }
for pair in "njs/tpix-rpc.js:old.js" "single-host/nginx-njs.conf:old.conf" "single-host/nginx-rpc.conf:old.vhost" \
            "fail2ban/jail.d/tpix-rpc.conf:old.jail" "fail2ban/filter.d/tpix-rpc.conf:old.filter"; do
    old_file "infrastructure/${pair%%:*}" > "$LAB/src/${pair##*:}" \
        || die "อ่าน ${pair%%:*} จาก $OLD_REF ไม่ได้ (clone แบบ shallow?) — git fetch --unshallow"
done
cp "$INFRA/njs/tpix-rpc.js"                   "$LAB/src/new.js"
cp "$INFRA/single-host/nginx-njs.conf"        "$LAB/src/new.conf"
cp "$INFRA/single-host/nginx-rpc.conf"        "$LAB/src/new.vhost"
cp "$INFRA/fail2ban/jail.d/tpix-rpc.conf"     "$LAB/src/new.jail"
cp "$INFRA/fail2ban/filter.d/tpix-rpc.conf"   "$LAB/src/new.filter"
cp "$INFRA/fail2ban/action.d/nginx-tpix-banned.conf" "$LAB/src/new.action"
install -m 0755 "$INFRA/scripts/tpix-nginx-ban.py" "$LAB/bin/tpix-nginx-ban"

grep -q 'iptables-multiport' "$LAB/src/old.jail"  || die "jail ที่ $OLD_REF ไม่ได้ใช้ iptables-multiport — ไม่ใช่ของเดิมที่จะพิสูจน์"
grep -q '^action = nginx-tpix-banned$' "$LAB/src/new.jail" || die "jail ใน working tree ไม่ได้ใช้ action nginx-tpix-banned"
grep -q 'tpixban' "$LAB/src/old.conf" && die "nginx-njs.conf ที่ $OLD_REF มี tpixban อยู่แล้ว"
grep -q 'tpixban' "$LAB/src/new.vhost" || die "nginx-rpc.conf ใน working tree ไม่ได้ใช้ log_format tpixban"

# ไฟล์จริงชี้ path ของเครื่องจริง — lab แก้เฉพาะ path/พอร์ต ที่เหลือใช้ตามไฟล์จริงทุกบรรทัด
install_conf() { sed "s#/etc/nginx/njs/#$LAB/njs/#g" "$LAB/src/$1.conf" > "$LAB/conf.d/05-tpix-njs.conf"; }
install_js()   { cp "$LAB/src/$1.js" "$LAB/njs/tpix-rpc.js"; }
lab_vhost() {
    # server ของพอร์ต 80 (redirect + ACME) ตัดทิ้ง · server 443 → ฟัง 127.0.0.1 ไม่มี TLS · log ลงโฟลเดอร์ lab
    awk '/^server \{/ { n++; if (n == 1) skip = 1 } { if (!skip) print } skip && /^\}/ { skip = 0 }' "$1" \
        | sed -e "s#listen 443 ssl http2;#listen 127.0.0.1:$2;#" -e '/listen \[::\]:443/d' \
              -e '/^[[:space:]]*ssl_/d' -e "s#/var/log/nginx/#$LAB/log/#g"
}
install_vhost() { lab_vhost "$LAB/src/$1.vhost" "$GATE_PORT" > "$LAB/vhost.conf"; }

# tpix-banned.map จริง + หนึ่งบรรทัดที่ "คนใส่มือ" ไว้ — ต้องอยู่ครบตลอด lab
cp "$INFRA/single-host/tpix-banned.map" "$MAP"
printf '198.51.100.7 1;\n' >> "$MAP"

# แทนไฟล์ที่มีอยู่บนเครื่องแต่ไม่อยู่ใน repo (00-cloudflare-realip.conf, 10-tpix-http.conf)
cat > "$LAB/host.conf" <<EOF
set_real_ip_from 127.0.0.1;
real_ip_header   CF-Connecting-IP;
limit_req_zone  \$binary_remote_addr zone=rpc_per_ip:10m rate=30r/s;
limit_conn_zone \$binary_remote_addr zone=rpc_conn_per_ip:10m;
geo \$banned_ip {
    default 0;
    include $MAP;
}
map \$http_x_cf_origin_token \$origin_ok { default 1; }
upstream tpix_rpc {
    server 127.0.0.1:$STUB_PORT;
    keepalive 16;
}
EOF

# user = คนที่รัน lab: nginx -t ที่ fail2ban (root) เรียกจะ chown โฟลเดอร์ temp ให้ "user" ของ config
# ถ้าไม่ระบุ มันจะยกให้ nobody แล้ว nginx ของ lab (ไม่ใช่ root) เขียนไม่ได้ — เครื่องจริงทุกตัวเป็น root ไม่มีเรื่องนี้
cat > "$LAB/nginx.conf" <<EOF
load_module $NJS_MODULE;
user $(id -un) $(id -gn);
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

    include $LAB/conf.d/*.conf;
    include $LAB/host.conf;
    include $LAB/vhost.conf;

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

ngx() { "$NGINX" -p "$LAB" -c "$LAB/nginx.conf" -e "$ERR" "$@"; }

# คำสั่งที่ action เรียกแทน `nginx -t` กับ `systemctl reload nginx` ของเครื่องจริง
cat > "$LAB/bin/nginx-test" <<EOF
#!/bin/sh
exec "$NGINX" -p "$LAB" -c "$LAB/nginx.conf" -e "$LAB/nginx-test.err" -t
EOF
cat > "$LAB/bin/nginx-reload" <<EOF
#!/bin/sh
echo reload >> "$LAB/reloads.log"
exec kill -HUP "\$(cat "$LAB/nginx.pid")"
EOF
chmod +x "$LAB/bin/nginx-test" "$LAB/bin/nginx-reload"
: > "$LAB/reloads.log"
reloads() { wc -l < "$LAB/reloads.log" | tr -d ' '; }

config_test() {
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
    # ส่ง HUP แบบเดียวกับ systemctl reload แล้วยืนยันว่า worker ชุดเก่าถูกแทนจริง (exit code บอกไม่ได้)
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
LOGMARK=0
log_clean() {
    local fresh
    fresh="$(tail -n +"$((LOGMARK + 1))" "$ERR")"
    LOGMARK="$(wc -l < "$ERR")"
    if printf '%s\n' "$fresh" | grep -E '\[(emerg|alert|crit|error)\]|js exception' > "$LAB/log.bad"; then
        bad "$1: error log มีข้อผิดพลาด" "$(head -n 3 "$LAB/log.bad")"
    else
        ok "$1: error log สะอาด"
    fi
}

READ='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
DENIED='{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}'    # deny-list → ด่านตอบ 403

code() {
    # code <IP ผู้ใช้> <payload> → รหัส HTTP
    local got
    got="$(curl -s -m 10 -o "$LAB/reply" -w '%{http_code}' -X POST "$GATE/" -H 'Content-Type: application/json' \
        -H "CF-Connecting-IP: $1" --data "$2" 2>/dev/null)" || got="000"
    printf '%s' "$got"
}
expect() {
    # expect <ชื่อ> <รหัส HTTP> <IP ผู้ใช้> <payload>
    local got; got="$(code "$3" "$4")"
    if [ "$got" = "$2" ]; then ok "$1 ($got)"; else bad "$1" "ได้ $got (ควรได้ $2) $(head -c 200 "$LAB/reply" 2>/dev/null)"; fi
}
eventually() {
    # eventually <ชื่อ> <รหัส HTTP> <IP ผู้ใช้> <payload> [วินาที] — รอจนได้รหัสนั้น (การแบนมีผลหลัง nginx reload)
    local got="" n=$(( ${5:-10} * 5 ))
    for _ in $(seq 1 "$n"); do
        got="$(code "$3" "$4")"
        [ "$got" = "$2" ] && break
        sleep 0.2
    done
    if [ "$got" = "$2" ]; then ok "$1 ($got)"; else bad "$1" "ได้ $got (ควรได้ $2) หลังรอ ${5:-10} วิ"; fi
}
reject_from() {
    # reject_from <IP ผู้ใช้> ... — ที่อยู่ละหนึ่งคำขอที่ด่านปฏิเสธ (403) · พิมพ์จำนวนที่ได้ 403
    local ip n=0
    for ip in "$@"; do [ "$(code "$ip" "$DENIED")" = "403" ] && n=$((n + 1)); done
    printf '%s' "$n"
}
count_is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1" "ได้ $2 (ควรได้ $3)"; fi; }
wait_for() {
    # wait_for <วินาที> <คำสั่ง...> — รอจนคำสั่งคืน 0
    local n=$(( $1 * 5 )); shift
    for _ in $(seq 1 "$n"); do "$@" && return 0; sleep 0.2; done
    return 1
}

# ── fail2ban ของ lab ──────────────────────────────────────────────────────────
# config เริ่มจาก /etc/fail2ban ของแพ็กเกจจริง (รวม jail.d/defaults-debian.conf ที่ตั้ง backend = systemd
# เป็นค่าปริยาย — เหตุผลที่ jail ของเราต้องระบุ backend = auto) แล้วเปลี่ยนเฉพาะ path ของตัว server
f2b_setup() {
    rm -rf "$F2B"
    cp -r /etc/fail2ban "$F2B" || die "copy /etc/fail2ban ไม่ได้"
    rm -f "$F2B"/jail.d/tpix-*.conf "$F2B"/jail.local
    cat > "$F2B/fail2ban.local" <<EOF
[Definition]
loglevel  = INFO
logtarget = $F2B/fail2ban.log
socket    = $F2B/f2b.sock
pidfile   = $F2B/f2b.pid
dbfile    = $F2B/f2b.sqlite3
EOF
    printf '[sshd]\nenabled = false\n' > "$F2B/jail.d/zz-lab.conf"
}
f2b_install_old() {
    # ของเดิมทุกบรรทัด ยกเว้น path ของ log กับพอร์ต (เครื่องจริง 80,443 → พอร์ตของ lab)
    cp "$LAB/src/old.filter" "$F2B/filter.d/tpix-rpc.conf"
    sed -e "s#/var/log/nginx/tpix-rpc.access.log#$ACCESS#" -e "s#port=\"80,443\"#port=\"$GATE_PORT\"#" \
        "$LAB/src/old.jail" > "$F2B/jail.d/tpix-rpc.conf"
    grep -q "port=\"$GATE_PORT\"" "$F2B/jail.d/tpix-rpc.conf" || die "แก้พอร์ตใน jail เดิมไม่ได้"
}
f2b_install_new() {
    # ของใหม่ทุกบรรทัด ยกเว้น path ของ log และค่าของ action ที่ชี้ไฟล์/คำสั่งของ lab
    cp "$LAB/src/new.filter" "$F2B/filter.d/tpix-rpc.conf"
    cp "$LAB/src/new.action" "$F2B/action.d/nginx-tpix-banned.conf"
    sed -e "s#/var/log/nginx/tpix-rpc.access.log#$ACCESS#" \
        -e "s#^action = nginx-tpix-banned\$#action = nginx-tpix-banned[script=\"$LAB/bin/tpix-nginx-ban\", map=\"$MAP\", statedir=\"$LAB/ban-state\", banlog=\"$LAB/ban.log\", testcmd=\"$LAB/bin/nginx-test\", reloadcmd=\"$LAB/bin/nginx-reload\", mininterval=2]#" \
        "$LAB/src/new.jail" > "$F2B/jail.d/tpix-rpc.conf"
    grep -q "map=\"$MAP\"" "$F2B/jail.d/tpix-rpc.conf" || die "แก้ action ใน jail ใหม่ไม่ได้"
}
f2b_start() {
    if ! f2b start >"$LAB/f2b.out" 2>&1; then
        show < "$LAB/f2b.out"; $SUDO tail -n 20 "$F2B/fail2ban.log" 2>/dev/null | show
        die "fail2ban ไม่สตาร์ท"
    fi
    wait_for 10 f2b status tpix-rpc >/dev/null 2>&1 || { $SUDO tail -n 20 "$F2B/fail2ban.log" | show; die "jail tpix-rpc ไม่ขึ้น"; }
}
f2b_stop() { f2b stop >/dev/null 2>&1; wait_for 10 f2b_gone || bad "fail2ban ไม่ยอมหยุด"; }
f2b_gone() { ! $SUDO test -e "$F2B/f2b.sock"; }
jail_stat() { f2b status tpix-rpc 2>/dev/null | sed -n "s/.*$1:[[:space:]]*//p" | head -n 1; }
is_banned() { jail_stat 'Banned IP list' | tr ' \t' '\n\n' | grep -qxF -- "$1"; }
failed_is() { [ "$(jail_stat 'Total failed')" = "$1" ]; }
map_has()  { grep -qE "^$(printf '%s' "$1" | sed 's/[.]/\\./g') 1; # tpix-nginx-ban " "$MAP"; }
OWN_LINE='^[0-9a-fA-F:./]+ 1; # tpix-nginx-ban '      # บรรทัดที่สคริปต์เขียน (หัวไฟล์มี comment ที่พูดถึงเครื่องหมายนี้ — ไม่นับ)
map_own()  { grep -cE "$OWN_LINE" "$MAP"; }

echo "══ lab การแบนของ fail2ban หลัง Cloudflare ══"
"$NGINX" -v 2>&1 | sed 's/^/  /'
command -v dpkg-query >/dev/null && dpkg-query -W -f='  ${Package} ${Version}\n' nginx libnginx-mod-http-js fail2ban iptables 2>/dev/null
echo "  ของเดิม = $OLD_REF"
echo "  root=$ROOT iptables=$IPT ip6tables=$IPT6"

# ══ 1. เครื่องวันนี้ ══════════════════════════════════════════════════════════════
say "1. เครื่องวันนี้ (conf / js / vhost / jail / filter ที่ $OLD_REF)"
install_conf old; install_js old; install_vhost old
config_test "ของเดิม"
start
expect "อ่านผ่าน (IPv4)" 200 10.9.0.1 "$READ"
expect "อ่านผ่าน (IPv6)" 200 2001:db8:f2b:9::1 "$READ"
expect "เมธอดต้องห้ามได้ 403" 403 10.9.0.1 "$DENIED"
expect "ที่อยู่ที่คนใส่มือไว้ใน tpix-banned.map โดนบล็อก (geo \$banned_ip ทำงานกับ IP ผู้ใช้จริง)" 403 198.51.100.7 "$READ"
if grep -q '^2001:db8:f2b:9::1 ' "$ACCESS"; then ok "log เดิม: ช่องแรกของ IPv6 คือที่อยู่เต็ม"; else
    bad "log เดิม: ไม่พบบรรทัดที่ขึ้นต้นด้วย 2001:db8:f2b:9::1" "$(tail -n 2 "$ACCESS")"
fi
log_clean "ของเดิม"

if [ "$IPT" = "1" ]; then
    f2b_setup; f2b_install_old; f2b_start
    f2b status tpix-rpc | show
    if f2b status tpix-rpc | grep -q "File list:.*$ACCESS"; then ok "jail เดิมอ่าน log ไฟล์เดียวกับที่ vhost เขียน"; else
        bad "jail เดิมไม่ได้อ่าน $ACCESS (Journal matches?)"
    fi
    count_is "action ของ jail เดิม" "$(f2b get tpix-rpc actions | tail -n 1 | tr -d ' ')" "iptables-multiport"

    # ══ 2. ของเดิม: แบนแล้วคำขอยังผ่าน ═══════════════════════════════════════════
    say "2. ของเดิม — fail2ban แบนด้วย iptables-multiport"
    f2b set tpix-rpc banip 203.0.113.99 >/dev/null
    if wait_for 10 is_banned 203.0.113.99; then ok "fail2ban รายงานว่า 203.0.113.99 ถูกแบน"; else bad "fail2ban ไม่ได้แบน 203.0.113.99"; fi
    $SUDO iptables -w -S | grep -E 'f2b-tpix-rpc' | show
    if $SUDO iptables -w -S f2b-tpix-rpc 2>/dev/null | grep -q -- '-s 203.0.113.99/32 .*-j REJECT'; then
        ok "กฎ iptables ของการแบนมีอยู่จริง (REJECT ต้นทาง 203.0.113.99)"
    else
        bad "ไม่พบกฎ iptables ของ 203.0.113.99" "$($SUDO tail -n 5 "$F2B/fail2ban.log")"
    fi
    expect "IPv4 ที่ถูกแบน ยิงผ่าน \"Cloudflare\" → ยังอ่านได้" 200 203.0.113.99 "$READ"
    expect "IPv4 ที่ถูกแบน → ส่งคำขอที่ด่านปฏิเสธได้ต่อ (ถึง nginx ทุกครั้ง)" 403 203.0.113.99 "$DENIED"
    PKTS="$($SUDO iptables -w -nvxL f2b-tpix-rpc | awk '$8 == "203.0.113.99" { print $1 }')"
    count_is "ตัวนับแพ็กเก็ตของกฎนั้น (ไม่มีแพ็กเก็ตไหนตรงกับกฎ)" "${PKTS:-?}" 0

    # กฎแบบเดียวกันในเชนเดียวกันบล็อกได้จริงเมื่อ "ต้นทางของแพ็กเก็ต" ตรง — ปัญหาไม่ได้อยู่ที่ iptables
    $SUDO iptables -w -I f2b-tpix-rpc 1 -s 127.0.0.2 -j REJECT --reject-with icmp-port-unreachable
    DIRECT="$(curl -s -m 5 --interface 127.0.0.2 -o /dev/null -w '%{http_code}' "$GATE/health" 2>/dev/null)" || DIRECT="000"
    count_is "ตัวเทียบ: กฎเดียวกันกับต้นทางของแพ็กเก็ต (127.0.0.2 ต่อตรง) → ต่อไม่ติด" "$DIRECT" 000
    $SUDO iptables -w -D f2b-tpix-rpc -s 127.0.0.2 -j REJECT --reject-with icmp-port-unreachable
    count_is "ตัวเทียบ: ถอดกฎแล้ว 127.0.0.2 ต่อได้" \
        "$(curl -s -m 5 --interface 127.0.0.2 -o /dev/null -w '%{http_code}' "$GATE/health" 2>/dev/null)" 200

    f2b set tpix-rpc banip 2001:db8:99::5 >/dev/null
    if wait_for 10 is_banned 2001:db8:99::5; then ok "fail2ban รายงานว่า 2001:db8:99::5 ถูกแบน"; else bad "fail2ban ไม่ได้แบน 2001:db8:99::5"; fi
    if [ "$IPT6" = "1" ] && $SUDO ip6tables -w -S f2b-tpix-rpc 2>/dev/null | grep -q -- '-s 2001:db8:99::5/128 .*-j REJECT'; then
        ok "กฎ ip6tables ของการแบนมีอยู่จริง (REJECT ต้นทาง 2001:db8:99::5)"
    else
        skip "ไม่พบกฎ ip6tables ของ 2001:db8:99::5 (ip6tables=$IPT6) — ข้อถัดไปยังพิสูจน์ว่าคำขอผ่าน"
        $SUDO tail -n 5 "$F2B/fail2ban.log" | show
    fi
    expect "IPv6 ที่ถูกแบน ยิงผ่าน \"Cloudflare\" → ยังอ่านได้" 200 2001:db8:99::5 "$READ"
    count_is "fail2ban นับว่ากำลังแบนอยู่" "$(jail_stat 'Currently banned')" 2

    # ══ 3. ของเดิม: หมุนที่อยู่ใน /64 เดียว ══════════════════════════════════════
    say "3. ของเดิม — นับต่อที่อยู่เต็ม"
    BASE_FAILED="$(jail_stat 'Total failed')"
    ROT=""; for i in 1 2 3 4 5 6 7 8 9 a b c; do ROT="$ROT 2001:db8:f2b:1::$i"; done
    # shellcheck disable=SC2086
    count_is "12 ที่อยู่ใน /64 เดียว ถูกปฏิเสธที่อยู่ละครั้ง" "$(reject_from $ROT)" 12
    if wait_for 15 failed_is "$((BASE_FAILED + 12))"; then ok "fail2ban เห็นการถูกปฏิเสธครบ 12 ครั้ง"; else
        bad "fail2ban เห็นไม่ครบ" "Total failed = $(jail_stat 'Total failed') (ควรได้ $((BASE_FAILED + 12)))"
    fi
    sleep 3
    count_is "เกิน maxretry (10) แล้ว แต่ไม่มีใครถูกแบนเพิ่ม — นับแยกทีละที่อยู่" "$(jail_stat 'Currently banned')" 2

    ONE=""; for _ in $(seq 1 12); do ONE="$ONE 2001:db8:98:1::7"; done
    # shellcheck disable=SC2086
    count_is "ที่อยู่เดียวถูกปฏิเสธ 12 ครั้ง" "$(reject_from $ONE)" 12
    if wait_for 20 is_banned 2001:db8:98:1::7; then ok "fail2ban แบน 2001:db8:98:1::7 เอง (jail + filter เดิมทำงาน)"; else
        bad "fail2ban ไม่ได้แบน 2001:db8:98:1::7" "$(f2b status tpix-rpc | tail -n 4)"
    fi
    sleep 2
    expect "ที่อยู่ที่ fail2ban เพิ่งแบนเอง → ยังอ่านได้" 200 2001:db8:98:1::7 "$READ"
    f2b status tpix-rpc | show
else
    skip "ขั้น 2-3 (ของเดิมกับ iptables ตัวจริง) — ไม่มี root หรือ iptables"
    f2b_setup
fi

# ══ 4. ลงของใหม่ ══════════════════════════════════════════════════════════════════
say "4. ลงของใหม่: conf → js → vhost (reload ทีละขั้น) → fail2ban"
install_conf new
config_test "conf ใหม่ (js กับ vhost ยังเป็นของเดิม)"
reload "conf ใหม่"
expect "conf ใหม่ js เดิม: อ่านผ่าน" 200 10.9.0.2 "$READ"
install_js new
config_test "js ใหม่"
reload "js ใหม่"
install_vhost new
config_test "vhost ใหม่"
reload "vhost ใหม่"
expect "อ่านผ่าน (IPv4)" 200 10.9.0.3 "$READ"
expect "อ่านผ่าน (IPv6)" 200 2001:db8:f2b:9:aaaa:bbbb:cccc:dddd "$READ"
expect "อ่านผ่าน (IPv4 ที่ห่อเป็น IPv6)" 200 ::ffff:10.9.0.4 "$READ"
LINE6="$(grep 'cf=2001:db8:f2b:9:aaaa:bbbb:cccc:dddd ' "$ACCESS" | tail -n 1)"
printf '%s\n' "$LINE6" | show
case "$LINE6" in
    "2001:db8:f2b:9:: - - "*) ok "log ใหม่: ช่องแรกของ IPv6 คือที่อยู่เครือข่ายของ /64 · ที่อยู่เต็มอยู่ในช่อง cf=" ;;
    *) bad "log ใหม่: ช่องแรกของ IPv6 ไม่ใช่ 2001:db8:f2b:9::" ;;
esac
if grep -q '^10\.9\.0\.3 - - .* cf=10\.9\.0\.3 ' "$ACCESS"; then ok "log ใหม่: ช่องแรกของ IPv4 คือที่อยู่นั้น"; else bad "log ใหม่: ไม่พบบรรทัดของ 10.9.0.3"; fi
if grep -q '^10\.9\.0\.4 - - .* cf=::ffff:10\.9\.0\.4 ' "$ACCESS"; then ok "log ใหม่: ::ffff:10.9.0.4 ลงเป็น 10.9.0.4"; else
    bad "log ใหม่: ::ffff:10.9.0.4 ไม่ได้ลงเป็น 10.9.0.4" "$(grep 'cf=::ffff:10.9.0.4 ' "$ACCESS" | tail -n 1)"
fi
log_clean "ของใหม่"

# fail2ban: วางไฟล์ใหม่แล้ว restart — ตอนหยุด action เดิมยังอยู่ในหน่วยความจำ จึงเก็บกฎ iptables ของตัวเองไป
F2B_ERR_FROM=1
if [ "$IPT" = "1" ]; then
    f2b_stop
    F2B_ERR_FROM=$(( $($SUDO cat "$F2B/fail2ban.log" | wc -l) + 1 ))
fi
f2b_install_new
if [ "$IPT" = "1" ]; then
    if $SUDO iptables -w -S | grep -q 'f2b-tpix-rpc'; then bad "หยุด fail2ban แล้วกฎ iptables ของ action เดิมยังค้าง" "$($SUDO iptables -w -S | grep f2b-tpix-rpc | head -n 3)"; else
        ok "หยุด fail2ban แล้วกฎ iptables ของ action เดิมหายหมด"
    fi
fi
f2b_start
f2b status tpix-rpc | show
count_is "action ของ jail ใหม่" "$(f2b get tpix-rpc actions | tail -n 1 | tr -d ' ')" "nginx-tpix-banned"
if f2b status tpix-rpc | grep -q "File list:.*$ACCESS"; then ok "jail ใหม่อ่าน log ไฟล์เดียวกับที่ vhost เขียน"; else bad "jail ใหม่ไม่ได้อ่าน $ACCESS"; fi

if [ "$IPT" = "1" ]; then
    say "4b. การแบนที่ค้างจากของเดิม ย้ายมาอยู่ที่ nginx แล้วมีผล"
    if wait_for 15 map_has 203.0.113.99; then ok "tpix-banned.map มี 203.0.113.99"; else bad "tpix-banned.map ไม่มี 203.0.113.99" "$(tail -n 5 "$MAP")"; fi
    if wait_for 15 map_has 2001:db8:99::/64; then ok "tpix-banned.map มี 2001:db8:99::/64 (จากที่อยู่เดี่ยว 2001:db8:99::5)"; else bad "tpix-banned.map ไม่มี 2001:db8:99::/64" "$(tail -n 5 "$MAP")"; fi
    eventually "IPv4 ที่ถูกแบน → 403" 403 203.0.113.99 "$READ"
    eventually "IPv6 ที่ถูกแบน → 403" 403 2001:db8:99::5 "$READ"
    eventually "ที่อยู่อื่นใน /64 เดียวกัน → 403" 403 2001:db8:99:0:aaaa:bbbb:cccc:dddd "$READ"
    eventually "ที่อยู่ที่ fail2ban แบนเองในขั้น 3 → 403" 403 2001:db8:98:1::7 "$READ"
    expect "/64 ที่ติดกันไม่โดน" 200 2001:db8:99:1::5 "$READ"
    expect "IPv4 ตัวถัดไปไม่โดน" 200 203.0.113.98 "$READ"
    f2b set tpix-rpc unbanip 203.0.113.99 2001:db8:99::5 2001:db8:98:1::7 >/dev/null
    eventually "เลิกแบนแล้ว IPv4 อ่านได้" 200 203.0.113.99 "$READ"
    eventually "เลิกแบนแล้ว IPv6 อ่านได้" 200 2001:db8:99::5 "$READ"
    count_is "บรรทัดของ fail2ban ใน tpix-banned.map หลังเลิกแบนครบ" "$(map_own)" 0
fi

# ══ 5. ของใหม่ ════════════════════════════════════════════════════════════════════
say "5. ของใหม่ — หมุนที่อยู่ใน /64 เดียว"
ROT=""; for i in 1 2 3 4 5 6 7 8 9 a b c; do ROT="$ROT 2001:db8:f2b:2:$i::$i"; done
# shellcheck disable=SC2086
count_is "12 ที่อยู่ใน /64 เดียว ถูกปฏิเสธที่อยู่ละครั้ง" "$(reject_from $ROT)" 12
if wait_for 20 is_banned 2001:db8:f2b:2::; then ok "fail2ban แบน 2001:db8:f2b:2:: (นับรวมทั้ง /64)"; else
    bad "fail2ban ไม่ได้แบน /64 ที่หมุนที่อยู่" "$(f2b status tpix-rpc | tail -n 4)"
fi
if wait_for 10 map_has 2001:db8:f2b:2::/64; then ok "tpix-banned.map มี 2001:db8:f2b:2::/64"; else bad "tpix-banned.map ไม่มี 2001:db8:f2b:2::/64" "$(tail -n 5 "$MAP")"; fi
grep -E "$OWN_LINE" "$MAP" | show
eventually "ที่อยู่ที่ยังไม่เคยใช้ใน /64 นั้น → 403" 403 2001:db8:f2b:2:ffff::1 "$READ"
expect "ที่อยู่ที่เคยใช้ → 403" 403 2001:db8:f2b:2:1::1 "$READ"
expect "/64 ที่ติดกันไม่โดน" 200 2001:db8:f2b:3::1 "$READ"
expect "IPv4 ไม่โดน" 200 10.9.0.3 "$READ"

say "5b. IPv4 ยังนับต่อที่อยู่ · ::ffff: ไม่ใช่ทางหลบ"
ONE=""; for _ in $(seq 1 12); do ONE="$ONE 10.9.1.1"; done
# shellcheck disable=SC2086
count_is "IPv4 ตัวเดียวถูกปฏิเสธ 12 ครั้ง" "$(reject_from $ONE)" 12
if wait_for 20 is_banned 10.9.1.1; then ok "fail2ban แบน 10.9.1.1"; else bad "fail2ban ไม่ได้แบน 10.9.1.1" "$(f2b status tpix-rpc | tail -n 4)"; fi
eventually "IPv4 ที่ถูกแบน → 403" 403 10.9.1.1 "$READ"
expect "IPv4 ตัวเดียวกันที่ห่อเป็น IPv6 → 403" 403 ::ffff:10.9.1.1 "$READ"
expect "IPv4 ตัวถัดไปไม่โดน" 200 10.9.1.2 "$READ"

MIX=""; for i in 1 2 3 4 5 6; do MIX="$MIX 10.9.3.1 ::ffff:10.9.3.1"; done
# shellcheck disable=SC2086
count_is "IPv4 สลับกับรูป ::ffff: ของตัวเอง ถูกปฏิเสธ 12 ครั้ง" "$(reject_from $MIX)" 12
if wait_for 20 is_banned 10.9.3.1; then ok "สองรูปของ IPv4 ตัวเดียวถูกนับรวมกันแล้วแบน"; else bad "สองรูปของ IPv4 ตัวเดียวไม่ถูกนับรวม" "$(f2b status tpix-rpc | tail -n 4)"; fi

say "5c. คำขอของคนที่ถูกแบนอยู่ ไม่ถูกนับซ้ำ และไม่ทำให้ nginx reload"
sleep 3      # ให้ reload ที่รอรวมอยู่ทำเสร็จก่อนจดค่าตั้งต้น
FAILED_BEFORE="$(jail_stat 'Total failed')"
RELOADS_BEFORE="$(reloads)"
BANNED_LINES_BEFORE="$(wc -l < "$BANNED" | tr -d ' ')"
for _ in $(seq 1 15); do code 2001:db8:f2b:2:beef::1 "$DENIED" >/dev/null; done
sleep 3
count_is "Total failed ไม่ขยับหลังคนที่ถูกแบนยิงอีก 15 ครั้ง" "$(jail_stat 'Total failed')" "$FAILED_BEFORE"
count_is "nginx ไม่ถูก reload เพิ่ม" "$(reloads)" "$RELOADS_BEFORE"
count_is "15 คำขอนั้นลง tpix-rpc.banned.log" "$(( $(wc -l < "$BANNED" | tr -d ' ') - BANNED_LINES_BEFORE ))" 15
if tail -n 1 "$BANNED" | grep -q '^2001:db8:f2b:2:beef::1 - - .*" 403 '; then ok "tpix-rpc.banned.log เก็บที่อยู่เต็มของคนที่ยังยิงอยู่"; else
    bad "tpix-rpc.banned.log ไม่ได้ขึ้นต้นด้วยที่อยู่เต็ม" "$(tail -n 1 "$BANNED")"
fi
if grep -q 'cf=2001:db8:f2b:2:beef::1 ' "$ACCESS"; then bad "คำขอของคนที่ถูกแบนยังลง log ที่ fail2ban อ่าน"; else ok "log ที่ fail2ban อ่านไม่มีคำขอของคนที่ถูกแบน"; fi

say "5d. คำขอที่สำเร็จไม่ถูกนับ"
for _ in $(seq 1 25); do code 10.9.2.1 "$READ" >/dev/null; done
sleep 3
if is_banned 10.9.2.1; then bad "ที่อยู่ที่อ่านสำเร็จ 25 ครั้งถูกแบน"; else ok "อ่านสำเร็จ 25 ครั้งไม่ถูกแบน"; fi
count_is "Total failed ไม่ขยับ" "$(jail_stat 'Total failed')" "$FAILED_BEFORE"

say "5e. fail2ban-regex กับ log จริงของ lab"
WANT_MATCH="$(grep -cE '" (403|405|413|429) [0-9]+ "' "$ACCESS")"
fail2ban-regex "$ACCESS" "$F2B/filter.d/tpix-rpc.conf" > "$LAB/regex.out" 2>&1
grep -E '^Lines:|Failregex:' "$LAB/regex.out" | show
GOT_MATCH="$(sed -n 's/^Lines:.* \([0-9][0-9]*\) matched.*/\1/p' "$LAB/regex.out")"
count_is "filter จับบรรทัดที่ถูกปฏิเสธครบ และไม่จับบรรทัด 200" "${GOT_MATCH:-?}" "$WANT_MATCH"

say "5f. เลิกแบน"
f2b set tpix-rpc unbanip 2001:db8:f2b:2:: >/dev/null
if wait_for 10 bash -c "! grep -q '^2001:db8:f2b:2::/64 ' '$MAP'"; then ok "บรรทัดของ /64 หายจาก tpix-banned.map"; else bad "บรรทัดของ /64 ยังอยู่"; fi
eventually "เลิกแบนแล้ว /64 นั้นอ่านได้" 200 2001:db8:f2b:2:ffff::1 "$READ"
expect "IPv4 ที่ยังถูกแบนอยู่ยัง 403" 403 10.9.1.1 "$READ"
if grep -q '^198\.51\.100\.7 1;$' "$MAP"; then ok "บรรทัดที่คนใส่มือยังอยู่"; else bad "บรรทัดที่คนใส่มือหายไป"; fi
expect "ที่อยู่ที่คนใส่มือยังโดนบล็อก" 403 198.51.100.7 "$READ"

say "5g. แบน 20 ที่อยู่ติดกัน — reload ต้องไม่ถี่ตามจำนวนที่อยู่"
sleep 3
RELOADS_BEFORE="$(reloads)"
MANY=""; for i in $(seq 1 20); do MANY="$MANY 10.20.0.$i"; done
# shellcheck disable=SC2086
f2b set tpix-rpc banip $MANY >/dev/null
if wait_for 20 bash -c "[ \"\$(grep -c '^10\\.20\\.0\\.[0-9]* 1; # tpix-nginx-ban ' '$MAP')\" = 20 ]"; then ok "ทั้ง 20 ที่อยู่ลง tpix-banned.map"; else
    bad "ลงไฟล์ไม่ครบ 20" "มี $(grep -c '^10\.20\.0\.' "$MAP") บรรทัด"
fi
eventually "ที่อยู่แรกของชุด → 403" 403 10.20.0.1 "$READ"
eventually "ที่อยู่สุดท้ายของชุด → 403" 403 10.20.0.20 "$READ"
sleep 3
ADDED=$(( $(reloads) - RELOADS_BEFORE ))
echo "    │ reload nginx $ADDED ครั้งสำหรับ 20 ที่อยู่ (ขั้นต่ำ 2 วิต่อครั้งใน lab · 5 วิบนเครื่องจริง)"
if [ "$ADDED" -ge 1 ] && [ "$ADDED" -le 4 ]; then ok "reload รวมกัน ไม่ใช่ 20 ครั้ง"; else bad "reload $ADDED ครั้ง (ควรได้ 1-4)"; fi
if ngx -t >"$LAB/t.out" 2>&1; then ok "config ยังผ่าน nginx -t หลังเขียนไฟล์ 20+ ครั้ง"; else bad "config พังหลังเขียนไฟล์" "$(tail -n 3 "$LAB/t.out")"; fi

say "5h. ของที่ไม่ใช่ที่อยู่ไปไม่ถึงไฟล์"
cp "$MAP" "$LAB/map.before"
"$LAB/bin/tpix-nginx-ban" --map "$MAP" --state-dir "$LAB/ban-state2" --log "$LAB/ban2.log" \
    --test-cmd "$LAB/bin/nginx-test" --reload-cmd "$LAB/bin/nginx-reload" add '1.2.3.4 1; } server {' 2>"$LAB/refuse.err"
count_is "สคริปต์ปฏิเสธ (exit 2)" "$?" 2
if cmp -s "$MAP" "$LAB/map.before"; then ok "ไฟล์ไม่ถูกแตะ"; else bad "ไฟล์เปลี่ยนทั้งที่ปฏิเสธ"; fi

say "5i. หยุด fail2ban — บรรทัดของมันต้องหายหมด บรรทัดใส่มือต้องอยู่"
f2b_stop
count_is "บรรทัดของ fail2ban ที่เหลือใน tpix-banned.map" "$(map_own)" 0
if grep -q '^198\.51\.100\.7 1;$' "$MAP"; then ok "บรรทัดที่คนใส่มือยังอยู่"; else bad "บรรทัดที่คนใส่มือหายไป"; fi
eventually "หยุดแล้ว ที่อยู่ที่เคยถูกแบนอ่านได้" 200 10.9.1.1 "$READ"
if ngx -t >"$LAB/t.out" 2>&1; then ok "config ผ่าน nginx -t"; else bad "config ไม่ผ่าน" "$(tail -n 3 "$LAB/t.out")"; fi
sleep 3
log_clean "ตลอดขั้น 4-5"
echo "    │ ── log ของ tpix-nginx-ban (ท้าย) ──"
$SUDO tail -n 12 "$LAB/ban.log" 2>/dev/null | show
echo "    │ ── fail2ban.log: ข้อผิดพลาด ──"
$SUDO tail -n +"$F2B_ERR_FROM" "$F2B/fail2ban.log" | grep -E '\]: (ERROR|CRITICAL)' > "$LAB/f2b.err"
if [ -s "$LAB/f2b.err" ]; then bad "fail2ban.log มี ERROR ตั้งแต่ลงของใหม่" "$(head -n 3 "$LAB/f2b.err")"; else ok "fail2ban.log ไม่มี ERROR ตั้งแต่ลงของใหม่"; fi
stop

# ══ 6. ลงผิดลำดับ ═════════════════════════════════════════════════════════════════
say "6. ผิดลำดับ — vhost ใหม่ขึ้นก่อน conf ที่ประกาศ tpixban"
install_conf old; install_js old; install_vhost new
if ngx -t >"$LAB/t.out" 2>&1; then
    bad "vhost ใหม่บน conf เดิม: nginx -t ควรไม่ผ่าน"
elif grep -q 'tpixban' "$LAB/t.out"; then
    ok "vhost ใหม่บน conf เดิม: nginx -t ไม่ผ่านและบอกชื่อ log format (พลาดแบบนี้ไม่เงียบ)"
    tail -n 2 "$LAB/t.out" | show
else
    bad "vhost ใหม่บน conf เดิม: nginx -t ไม่ผ่าน แต่ไม่ได้บอกว่าเพราะ tpixban" "$(tail -n 3 "$LAB/t.out")"
fi

say "6b. ผิดลำดับ — vhost ใหม่ + conf ใหม่ แต่ tpix-rpc.js ยังเป็นตัวเดิม (ไม่มี banKey)"
install_conf new; install_js old; install_vhost new
: > "$ACCESS"
if ngx -t >"$LAB/t.out" 2>&1; then
    ok "nginx -t ผ่าน (ไม่ช่วยจับ)"
    start
    reject_from 2001:db8:f2b:6::1 2001:db8:f2b:6::1 2001:db8:f2b:6::1 >/dev/null
    tail -n 1 "$ACCESS" | show
    echo "    │ error log พูดถึง banKey $(grep -c 'banKey' "$ERR") บรรทัด"
    if grep -q '^2001:db8:f2b:6::' "$ACCESS"; then bad "ช่องแรกของ log ยังเป็นที่อยู่ ทั้งที่ js ไม่มี banKey"; else ok "ช่องแรกของ log ไม่ใช่ที่อยู่"; fi
    fail2ban-regex "$ACCESS" "$LAB/src/new.filter" > "$LAB/regex.out" 2>&1
    grep -E '^Lines:' "$LAB/regex.out" | show
    count_is "fail2ban ไม่แมตช์สักบรรทัด = ไม่แบนใครเลย (พลาดแบบนี้เงียบ)" \
        "$(sed -n 's/^Lines:.* \([0-9][0-9]*\) matched.*/\1/p' "$LAB/regex.out")" 0
    stop
else
    ok "nginx -t ไม่ผ่าน (พลาดแบบนี้ไม่เงียบ)"
    tail -n 2 "$LAB/t.out" | show
fi

# ══ 7. ฉบับตั้งเครื่องใหม่ ════════════════════════════════════════════════════════
say "7. nginx-http-tpix.conf + nginx-rpc.conf จริง"
sed -e "s#/etc/nginx/njs/#$LAB/njs/#g" \
    -e "s#/etc/nginx/conf.d/tpix-banned.map#$MAP#g" \
    -e "s#tpix-validator-[1-4]:8545#127.0.0.1:$STUB_PORT#g" \
    "$INFRA/single-host/nginx-http-tpix.conf" > "$LAB/alt/10-tpix-http.conf"
lab_vhost "$LAB/src/new.vhost" "$ALT_PORT" > "$LAB/alt/vhost.conf"
install_js new
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
    include $LAB/alt/10-tpix-http.conf;
    include $LAB/alt/vhost.conf;
}
EOF
if "$NGINX" -p "$LAB/alt" -c "$LAB/alt/nginx.conf" -e "$LAB/alt/error.log" -t >"$LAB/t.out" 2>&1; then
    ok "nginx-http-tpix.conf + nginx-rpc.conf: nginx -t ผ่าน"
else
    bad "nginx-http-tpix.conf + nginx-rpc.conf: nginx -t ไม่ผ่าน" "$(tail -n 3 "$LAB/t.out")"
fi
ban_block() { sed -n '/^# >>> rpc_ban_log/,/^# <<< rpc_ban_log/p' "$1" | grep -v '^#'; }
BLOCK_NJS="$(ban_block "$INFRA/single-host/nginx-njs.conf")"
BLOCK_HTTP="$(ban_block "$INFRA/single-host/nginx-http-tpix.conf")"
if [ -n "$BLOCK_NJS" ] && [ "$BLOCK_NJS" = "$BLOCK_HTTP" ]; then
    ok "บล็อก rpc_ban_log ใน nginx-http-tpix.conf ตรงกับ nginx-njs.conf"
else
    bad "บล็อก rpc_ban_log ใน nginx-http-tpix.conf ไม่ตรงกับ nginx-njs.conf (หรือหาบล็อกไม่เจอ)"
fi

echo
echo "══ ผ่าน $PASS · ไม่ผ่าน $FAIL · ข้าม $SKIP ══"
if [ "$FAIL" -ne 0 ]; then
    echo
    echo "── nginx error log 30 บรรทัดสุดท้าย ──"
    tail -n 30 "$ERR" 2>/dev/null
    echo "── fail2ban.log 40 บรรทัดสุดท้าย ──"
    $SUDO tail -n 40 "$F2B/fail2ban.log" 2>/dev/null
    echo "── tpix-banned.map ──"
    cat "$MAP" 2>/dev/null
    exit 1
fi
