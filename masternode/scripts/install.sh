#!/bin/bash
#
# TPIX Master Node — One-Click Installer (Linux/macOS)
# =====================================================
# Installs and configures TPIX Master Node on your server
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/xjanova/TPIX-Coin/main/masternode/scripts/install.sh | bash
#
# Or with options:
#   ./install.sh --tier=sentinel --wallet=0xYourAddress --name=my-node
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

TPIX_VERSION="1.0.0"
INSTALL_DIR="/opt/tpix-node"
DATA_DIR="$HOME/.tpix-node"
SERVICE_NAME="tpix-node"
GITHUB_REPO="xjanova/TPIX-Coin"

show_help() {
    echo "TPIX Master Node Installer v${TPIX_VERSION}"
    echo ""
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --tier=TYPE     Node tier: validator, sentinel, light (default: light)"
    echo "  --wallet=ADDR   Your TPIX wallet address (0x...)"
    echo "  --name=NAME     Node display name"
    echo "  --help          Show this help"
    echo ""
    echo "Tiers:"
    echo "  validator  1,000,000 TPIX stake  12-15% APY  (max 100 nodes)"
    echo "  sentinel     100,000 TPIX stake   7-10% APY  (max 500 nodes)"
    echo "  light         10,000 TPIX stake    4-6% APY  (unlimited)"
}

# Parse arguments
TIER="light"
WALLET=""
NODE_NAME=""

for arg in "$@"; do
    case $arg in
        --tier=*) TIER="${arg#*=}" ;;
        --wallet=*) WALLET="${arg#*=}" ;;
        --name=*) NODE_NAME="${arg#*=}" ;;
        --help) show_help; exit 0 ;;
    esac
done

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                                                      ║"
    echo "║   ████████╗██████╗ ██╗██╗  ██╗                       ║"
    echo "║      ██╔══╝██╔══██╗██║╚██╗██╔╝                       ║"
    echo "║      ██║   ██████╔╝██║ ╚███╔╝                        ║"
    echo "║      ██║   ██╔═══╝ ██║ ██╔██╗                        ║"
    echo "║      ██║   ██║     ██║██╔╝ ██╗                       ║"
    echo "║      ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝                       ║"
    echo "║                                                      ║"
    echo "║   Master Node Installer v${TPIX_VERSION}                       ║"
    echo "║   https://tpix.online                                ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_requirements() {
    log_info "Checking system requirements..."

    # Check OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) log_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    log_info "OS: $OS / Arch: $ARCH"

    # Check minimum resources
    TOTAL_MEM=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    log_info "Total Memory: ${TOTAL_MEM}MB"

    case "$TIER" in
        validator)
            if [ "$TOTAL_MEM" -lt 14000 ]; then
                log_warn "Validator nodes recommend 16GB RAM (found ${TOTAL_MEM}MB)"
            fi
            ;;
        sentinel)
            if [ "$TOTAL_MEM" -lt 6000 ]; then
                log_warn "Sentinel nodes recommend 8GB RAM (found ${TOTAL_MEM}MB)"
            fi
            ;;
    esac

    # Check required tools
    for cmd in curl tar; do
        if ! command -v $cmd &>/dev/null; then
            log_error "$cmd is required but not installed"
            exit 1
        fi
    done

    log_info "Requirements OK"
}

download_binary() {
    log_info "Downloading TPIX Node v${TPIX_VERSION}..."

    BINARY_URL="https://github.com/${GITHUB_REPO}/releases/download/v${TPIX_VERSION}/tpix-node-${OS}-${ARCH}.tar.gz"

    mkdir -p "$INSTALL_DIR"

    if curl -fsSL "$BINARY_URL" -o /tmp/tpix-node.tar.gz 2>/dev/null; then
        tar -xzf /tmp/tpix-node.tar.gz -C "$INSTALL_DIR"
        chmod +x "$INSTALL_DIR/tpix-node"
        rm /tmp/tpix-node.tar.gz
        log_info "Binary installed to $INSTALL_DIR/tpix-node"
    else
        log_warn "Could not download pre-built binary. Building from source..."
        build_from_source
    fi
}

build_from_source() {
    log_info "Building from source..."

    if ! command -v go &>/dev/null; then
        log_info "Installing Go..."
        curl -fsSL https://go.dev/dl/go1.22.1.linux-${ARCH}.tar.gz | sudo tar -C /usr/local -xzf -
        export PATH=$PATH:/usr/local/go/bin
    fi

    cd /tmp
    git clone --depth 1 "https://github.com/${GITHUB_REPO}.git" tpix-coin 2>/dev/null || true
    cd tpix-coin/masternode

    go build -ldflags="-s -w -X main.Version=${TPIX_VERSION}" -o "$INSTALL_DIR/tpix-node" ./cmd/tpix-node/
    log_info "Built successfully"

    cd /tmp && rm -rf tpix-coin
}

configure_node() {
    log_info "Configuring node..."

    mkdir -p "$DATA_DIR"/{logs,data,keystore}

    # Generate config
    "$INSTALL_DIR/tpix-node" init \
        --tier="$TIER" \
        --wallet="${WALLET:-}" \
        --name="${NODE_NAME:-}"

    log_info "Configuration saved to $DATA_DIR/tpix-node.yaml"
}

install_service() {
    log_info "Installing systemd service..."

    # Create symlink
    sudo ln -sf "$INSTALL_DIR/tpix-node" /usr/local/bin/tpix-node

    # Create systemd service
    sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=TPIX Master Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
ExecStart=$INSTALL_DIR/tpix-node --config=$DATA_DIR/tpix-node.yaml
Restart=always
RestartSec=10
LimitNOFILE=65535
StandardOutput=append:$DATA_DIR/logs/node.log
StandardError=append:$DATA_DIR/logs/error.log

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"

    log_info "Service installed: $SERVICE_NAME"
}

start_node() {
    log_info "Starting TPIX Master Node..."
    sudo systemctl start "$SERVICE_NAME"
    sleep 2

    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Node is running!"
    else
        log_error "Node failed to start. Check logs: journalctl -u $SERVICE_NAME -f"
        exit 1
    fi
}

print_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   TPIX Master Node — Installation Complete!          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}Tier:${NC}       $TIER"
    echo -e "  ${GREEN}Wallet:${NC}     ${WALLET:-'(not set — edit config)'}"
    echo -e "  ${GREEN}Config:${NC}     $DATA_DIR/tpix-node.yaml"
    echo -e "  ${GREEN}Dashboard:${NC}  http://localhost:3847"
    echo -e "  ${GREEN}Logs:${NC}       $DATA_DIR/logs/node.log"
    echo ""
    echo -e "  ${YELLOW}Commands:${NC}"
    echo "    tpix-node status              Show node status"
    echo "    tpix-node dashboard           Open web dashboard"
    echo "    sudo systemctl stop $SERVICE_NAME    Stop node"
    echo "    sudo systemctl restart $SERVICE_NAME Restart node"
    echo "    journalctl -u $SERVICE_NAME -f       View logs"
    echo ""

    if [ -z "$WALLET" ]; then
        echo -e "  ${YELLOW}IMPORTANT:${NC} Set your wallet address in $DATA_DIR/tpix-node.yaml"
        echo "  Then restart: sudo systemctl restart $SERVICE_NAME"
        echo ""
    fi

    echo -e "  ${CYAN}Stake TPIX at: https://tpix.online/masternode${NC}"
    echo ""
}

# ============================================================
#  Main
# ============================================================

banner
check_requirements
download_binary
configure_node
install_service
start_node
print_summary
