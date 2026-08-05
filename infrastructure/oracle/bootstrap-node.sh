#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  bootstrap-node.sh — เตรียม VPS หนึ่งเครื่องให้พร้อมรัน TPIX node
# ══════════════════════════════════════════════════════════════════════════════
#
#  รันบน VPS เปล่าๆ (Oracle Cloud Ampere A1 / Ubuntu 22.04 หรือ Oracle Linux 9)
#
#    curl -fsSL <raw url>/bootstrap-node.sh -o bootstrap-node.sh
#    sudo bash bootstrap-node.sh --index 1 --peers "1.2.3.4,5.6.7.8,9.10.11.12" [--rpc-only]
#
#    --index N    ลำดับโหนด 1..4
#    --peers      IP สาธารณะของโหนด "ตัวอื่น" คั่นด้วย , (ไม่ต้องใส่ตัวเอง)
#    --rpc-only   ไม่ต้อง --seal → เป็น full node สำหรับให้บริการ RPC
#                 (โหมดนี้ไม่มีคีย์ validator = ไม่มีอะไรให้ขโมย วางที่ไหนในโลกก็ได้)
#
#  ⚠️ Oracle Cloud มีไฟร์วอลล์ "สองชั้น" คนลืมชั้นใดชั้นหนึ่งตลอด:
#       ชั้นที่ 1  VCN Security List / NSG  ← ต้องตั้งใน OCI Console ด้วยมือ
#       ชั้นที่ 2  iptables ในเครื่อง       ← สคริปต์นี้จัดการให้
#     image Ubuntu ของ Oracle มากับ iptables ที่เปิดแค่ port 22 เท่านั้น
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

NODE_INDEX=""
PEERS=""
RPC_ONLY=0
EDGE_IMAGE="0xpolygon/polygon-edge:0.9.0"
NODE_HOME="/opt/tpix-node"
P2P_PORT=10001

while [[ $# -gt 0 ]]; do
  case "$1" in
    --index)    NODE_INDEX="$2"; shift 2 ;;
    --peers)    PEERS="$2"; shift 2 ;;
    --rpc-only) RPC_ONLY=1; shift ;;
    --image)    EDGE_IMAGE="$2"; shift 2 ;;
    *) echo "ไม่รู้จัก option: $1" >&2; exit 2 ;;
  esac
done

die() { echo -e "\n❌ $*\n" >&2; exit 1; }
say() { echo -e "\n▸ $*"; }

[[ $EUID -eq 0 ]]      || die "ต้องรันด้วย sudo"
[[ -n "$NODE_INDEX" ]] || die "ต้องระบุ --index"
[[ -n "$PEERS" ]]      || die "ต้องระบุ --peers (IP ของโหนดอื่น)"

# ── 1. IP สาธารณะของเครื่องนี้ ─────────────────────────────────────────────────
say "1/7 หา IP สาธารณะ"
# Oracle มี metadata service ในเครื่อง เชื่อถือได้กว่าถาม service ภายนอก
PUBLIC_IP="$(curl -s --max-time 5 -H 'Authorization: Bearer Oracle' \
  http://169.254.169.254/opc/v2/vnics/ 2>/dev/null \
  | grep -o '"publicIp"[^,]*' | head -1 | cut -d'"' -f4 || true)"
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="$(curl -s --max-time 5 https://api.ipify.org || true)"
[[ "$PUBLIC_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || \
  die "หา IP สาธารณะไม่ได้ — ใส่เองด้วย: PUBLIC_IP=x.x.x.x bash $0 ..."
echo "  IP สาธารณะ = $PUBLIC_IP"

# ── 2. ติดตั้ง docker ──────────────────────────────────────────────────────────
say "2/7 ติดตั้ง docker"
if ! command -v docker >/dev/null; then
  if command -v dnf >/dev/null; then
    dnf install -y dnf-utils
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  else
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  fi
  systemctl enable --now docker
else
  echo "  docker มีอยู่แล้ว: $(docker --version)"
fi

# ── 3. swap (instance ฟรีแรมน้อย — polygon-edge sync กินแรมช่วงพีค) ─────────────
say "3/7 swap"
if ! swapon --show | grep -q .; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "  เพิ่ม swap 4G"
else
  echo "  มี swap อยู่แล้ว"
fi

# ── 4. ไฟร์วอลล์ในเครื่อง — เปิด libp2p เฉพาะ IP เพื่อน ─────────────────────────
say "4/7 ไฟร์วอลล์ในเครื่อง (ชั้นที่ 2)"
IFS=',' read -ra PEER_ARR <<< "$PEERS"
for p in "${PEER_ARR[@]}"; do
  p="$(echo "$p" | tr -d '[:space:]')"
  [[ "$p" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "IP เพื่อนผิดรูปแบบ: '$p'"
done

if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
  for p in "${PEER_ARR[@]}"; do
    p="$(echo "$p" | tr -d '[:space:]')"
    firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$p \
port port=$P2P_PORT protocol=tcp accept" >/dev/null
    echo "  firewalld: อนุญาต $p → $P2P_PORT"
  done
  firewall-cmd --reload >/dev/null
else
  # Oracle Ubuntu: iptables ตรงๆ (chain INPUT มี REJECT ปิดท้ายอยู่แล้ว)
  for p in "${PEER_ARR[@]}"; do
    p="$(echo "$p" | tr -d '[:space:]')"
    iptables -C INPUT -p tcp -s "$p" --dport "$P2P_PORT" -j ACCEPT 2>/dev/null || \
      iptables -I INPUT 1 -p tcp -s "$p" --dport "$P2P_PORT" -j ACCEPT
    echo "  iptables: อนุญาต $p → $P2P_PORT"
  done
  if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save >/dev/null
  else
    apt-get install -y iptables-persistent >/dev/null 2>&1 || true
    command -v netfilter-persistent >/dev/null && netfilter-persistent save >/dev/null
  fi
fi

cat <<EOF

  ⚠️ ยังเหลือไฟร์วอลล์ "ชั้นที่ 1" ที่ต้องทำเองใน OCI Console:
     Networking → VCN → Security Lists (หรือ NSG ที่ผูกกับ instance)
       Ingress rule: Source = <IP ของแต่ละโหนดเพื่อน>/32
                     Protocol = TCP   Destination Port = $P2P_PORT
     อย่าใช้ 0.0.0.0/0 — ระบุเป็นราย IP เท่านั้น
     ห้ามเปิด 8545 และ 10000 ออกเน็ตเด็ดขาด

EOF

# ── 5. โครงไดเรกทอรี ───────────────────────────────────────────────────────────
say "5/7 เตรียม $NODE_HOME"
mkdir -p "$NODE_HOME/data"
chmod 700 "$NODE_HOME" "$NODE_HOME/data"

SEAL_FLAG="--seal"
[[ "$RPC_ONLY" -eq 1 ]] && SEAL_FLAG=""

cat > "$NODE_HOME/.env" <<EOF
NODE_INDEX=$NODE_INDEX
PUBLIC_IP=$PUBLIC_IP
EDGE_IMAGE=$EDGE_IMAGE
SEAL=$SEAL_FLAG
EOF
chmod 600 "$NODE_HOME/.env"

# ── 6. ดึง image ล่วงหน้า ──────────────────────────────────────────────────────
say "6/7 ดึง image (ตรวจว่ารองรับสถาปัตยกรรมเครื่องนี้)"
docker pull "$EDGE_IMAGE"
echo "  สถาปัตยกรรม: $(uname -m)  — Ampere A1 = aarch64, image นี้มี manifest arm64 ครบ"

# ── 7. สรุป ────────────────────────────────────────────────────────────────────
say "7/7 เสร็จ"
cat <<EOF

  โหนดที่ $NODE_INDEX พร้อมแล้ว — แต่ยังไม่สตาร์ท (ยังไม่มี genesis + คีย์)

  ข้อมูลที่ต้องเอาไปใส่ตอนสร้าง genesis:
    PUBLIC_IP = $PUBLIC_IP

  ขั้นถัดไป (ทำจากเครื่องคุมกลาง):
    1. copy docker-compose.node.yml → $NODE_HOME/docker-compose.yml
    2. copy genesis.json (ที่ผ่าน genesis-verify.py แล้ว) → $NODE_HOME/genesis.json
    3. copy คีย์ validator (consensus/ + libp2p/) → $NODE_HOME/data/
       scp -r keys/validator-$NODE_INDEX/consensus  <host>:$NODE_HOME/data/
       scp -r keys/validator-$NODE_INDEX/libp2p     <host>:$NODE_HOME/data/
       แล้วบนโหนด:  chmod 700 $NODE_HOME/data/consensus
                    chmod 600 $NODE_HOME/data/consensus/*
    4. cd $NODE_HOME && docker compose up -d
    5. ตรวจ:  docker compose logs -f | grep -i ibft

  รายละเอียดเต็ม: docs/REGENESIS-RUNBOOK.md
EOF
