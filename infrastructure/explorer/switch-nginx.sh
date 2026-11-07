#!/bin/sh
# สลับ explorer.tpix.online ระหว่างชุดเก่า (/opt/tpix: 4000/3100/8153) กับชุดใหม่ (/opt/tpix-bs: 4200/3200/8163)
# ใช้: switch-nginx.sh new | old    (visualizer 8154 ใช้ตัวเดิมทั้งสองชุด)
set -e
SITE=/etc/nginx/sites-enabled/tpix-explorer.conf
GATE=/etc/nginx/snippets/tpix-verify-gate-locations.conf
case "$1" in
  new) A=4000; B=4200; C=3100; D=3200; E=8153; F=8163 ;;
  old) A=4200; B=4000; C=3200; D=3100; E=8163; F=8153 ;;
  *) echo "usage: $0 new|old"; exit 2 ;;
esac
# refuse to point nginx at a backend that is not up (the old stack is stopped and profile-gated since 2026-11-07)
if ! curl -s -o /dev/null --max-time 5 "http://127.0.0.1:$B/api/v2/stats"; then
  echo "backend 127.0.0.1:$B is not answering - nothing switched."
  [ "$1" = old ] && echo "start the old stack first: cd /opt/tpix && docker compose --profile legacy-explorer up -d   (backend needs ~2 min)"
  exit 1
fi
TS=$(date -u +%Y%m%dT%H%M%SZ)
cp -a $SITE /opt/tpix-bs/nginx-site.bak-$TS
cp -a $GATE /opt/tpix-bs/nginx-gate.bak-$TS
sed -i -e "s#http://127.0.0.1:$A;#http://127.0.0.1:$B;#g" -e "s#http://127.0.0.1:$C;#http://127.0.0.1:$D;#g" -e "s#http://127.0.0.1:$E/;#http://127.0.0.1:$F/;#g" $SITE
sed -i -e "s#http://127.0.0.1:$A;#http://127.0.0.1:$B;#g" $GATE
if nginx -t 2>/dev/null; then nginx -s reload; echo "switched to $1"; else
  cp -a /opt/tpix-bs/nginx-site.bak-$TS $SITE; cp -a /opt/tpix-bs/nginx-gate.bak-$TS $GATE; echo "nginx -t failed — restored"; exit 1; fi
grep -n 'proxy_pass' $SITE $GATE
