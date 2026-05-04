#!/bin/bash
# Server-side chain regenesis — restart 4 IBFT validators with new genesis allocations.
#
# Run as root on the validator host:
#   cd ~/TPIX-Coin && git pull
#   sudo bash infrastructure/scripts/restart-chain.sh
#
# Steps:
#   1. Backup current chain data (block history, /var/lib/.../data)
#   2. Stop all 4 validator containers
#   3. Wipe each validator's blockchain data dir (keep consensus/libp2p keys)
#   4. Replace per-validator genesis.json with the new one
#   5. Start validators
#   6. Verify chain at block 0+

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then err "Run as root"; exit 1; fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")"/../.. && pwd)"
log "Repo: $REPO_DIR"

INFRA="$REPO_DIR/infrastructure"
COMPOSE_FILE="$INFRA/docker-compose-4v.yml"
[[ -f "$COMPOSE_FILE" ]] || COMPOSE_FILE="$INFRA/docker-compose.yml"
[[ -f "$COMPOSE_FILE" ]] || { err "No docker-compose file found"; exit 1; }

NEW_GENESIS="$INFRA/genesis.json"
[[ -f "$NEW_GENESIS" ]] || { err "$NEW_GENESIS missing — did you 'git pull' after running regenesis.ps1?"; exit 1; }

# Sanity check: new genesis should have the new alloc addresses (not 0x3F8E...401A)
if grep -q '0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A' "$NEW_GENESIS" 2>/dev/null; then
    err "New genesis still references the old Token Sale wallet 0x3F8E...401A."
    err "Did you run regenesis.ps1 locally and commit + push the result?"
    exit 1
fi

# ─── 1. Confirmation
echo
warn "THIS WILL RESET THE CHAIN. All blocks will be wiped and chain restarts at block 0."
warn "Consensus + libp2p keys are preserved (validators keep their identities)."
echo
read -rp "Type 'REGENESIS' to confirm: " confirm
if [[ "$confirm" != "REGENESIS" ]]; then
    log "Aborted."
    exit 0
fi

cd "$INFRA"

# ─── 2. Stop + remove validators (down, not stop — so up -d can recreate clean)
log "[1/6] Stopping + removing validator containers..."
docker compose -f "$(basename "$COMPOSE_FILE")" down 2>&1 | tail -5

# ─── 3. Backup chain state
TS=$(date +%Y%m%d-%H%M%S)
BAK_DIR="$REPO_DIR/../tpix-chain-backup-regenesis-$TS"
log "[2/6] Backing up chain data to $BAK_DIR..."
mkdir -p "$BAK_DIR"

if [[ -d "$INFRA/data" ]]; then
    for v in validator-1 validator-2 validator-3 validator-4; do
        if [[ -d "$INFRA/data/$v" ]]; then
            cp -r "$INFRA/data/$v" "$BAK_DIR/$v"
        fi
    done
    log "  Backed up validator data dirs"
fi

# ─── 4. Wipe blockchain data (keep keys + secrets)
log "[3/6] Wiping blockchain data (keeping consensus/libp2p keys + secrets)..."
for v in validator-1 validator-2 validator-3 validator-4; do
    DATA_DIR="$INFRA/data/$v"
    [[ -d "$DATA_DIR" ]] || continue

    # Polygon Edge layout:
    #   <DATA_DIR>/blockchain/         — block + state DB (WIPE)
    #   <DATA_DIR>/trie/               — state trie (WIPE)
    #   <DATA_DIR>/consensus/          — IBFT BLS key (KEEP)
    #   <DATA_DIR>/libp2p/             — peer ID key (KEEP)
    #   <DATA_DIR>/secrets.json        — secrets manager state (KEEP)
    #   <DATA_DIR>/genesis.json        — replaced below
    rm -rf "$DATA_DIR/blockchain" "$DATA_DIR/trie" 2>/dev/null
    log "  Wiped $v/blockchain + $v/trie"
done

# ─── 5. Replace genesis.json in every validator dir
log "[4/6] Distributing new genesis.json to validators..."
for v in validator-1 validator-2 validator-3 validator-4; do
    DATA_DIR="$INFRA/data/$v"
    [[ -d "$DATA_DIR" ]] || continue
    cp "$NEW_GENESIS" "$DATA_DIR/genesis.json"
    log "  → $v/genesis.json"
done

# ─── 6. Start validators
log "[5/6] Starting validators..."
docker compose -f "$(basename "$COMPOSE_FILE")" up -d 2>&1 | tail -15

# ─── 7. Verify
log "[6/6] Waiting for chain to come up (15 sec)..."
sleep 15

# Try local RPC first (validator-1 typically exposes 8545)
RPC_LOCAL="http://localhost:8545"
RPC_REMOTE="https://rpc.tpix.online"

probe() {
    local rpc="$1"
    curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$rpc" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || echo ""
}

BLOCK_LOCAL=$(probe "$RPC_LOCAL")
BLOCK_REMOTE=$(probe "$RPC_REMOTE")

echo
echo "════════════════════════════════════════════════════"
echo " ✅ Chain regenesis complete"
echo "════════════════════════════════════════════════════"
[[ -n "$BLOCK_LOCAL"  ]] && echo "  Local RPC  block: $BLOCK_LOCAL  ($((16#${BLOCK_LOCAL:2})) decimal)"
[[ -n "$BLOCK_REMOTE" ]] && echo "  Public RPC block: $BLOCK_REMOTE ($((16#${BLOCK_REMOTE:2})) decimal)"
echo
echo "Chain backup: $BAK_DIR"
echo
echo "Verify allocations (run from your local machine):"
echo "  curl -s -X POST -H 'Content-Type: application/json' \\"
echo "       --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"<addr>\",\"latest\"],\"id\":1}' \\"
echo "       https://rpc.tpix.online"
echo
echo "Or run the preflight (also verifies your DEPLOYER_KEY matches Token Sale wallet):"
echo "  cd contracts ; npx hardhat run scripts/deploy-preflight.js --network tpix"
echo
