# Deploy launcher — prompts DEPLOYER_KEY via SecureString (never visible)
#
# Usage (Windows PowerShell):
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-launch.ps1
#
# What it does:
#   1. Prompts you for the private key (hidden — like a password field)
#   2. Validates format (0x + 64 hex)
#   3. Calls deploy-preflight.js to verify the key controls the right wallet
#   4. If preflight passes, asks for final confirmation, then runs deploy-mainnet.js
#   5. Clears the key from memory after run
#
# Key never appears in:
#   - Terminal screen
#   - PowerShell command history
#   - Any file
#
# Prerequisites:
#   - npx hardhat compile  (must run successfully first)
#   - You have your Token Sale wallet (0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A) private key handy

$ErrorActionPreference = 'Stop'

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   TPIX Mainnet Deploy Launcher (secure)          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Sanity: must be in contracts dir
if (-not (Test-Path .\hardhat.config.js)) {
    Write-Host "Error: run this from D:\Code\TPIX\TPIX-Coin\contracts" -ForegroundColor Red
    exit 1
}

# ─── Step 1: prompt for key (hidden)
Write-Host "Step 1/3: enter Token Sale wallet private key" -ForegroundColor Yellow
Write-Host "  Expected wallet: 0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A"
Write-Host "  Format: 0x + 64 hex chars (66 chars total)"
Write-Host "  (Input is hidden, not stored anywhere)"
Write-Host ""

$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) {
    Write-Host "Cancelled (no input)" -ForegroundColor Red
    exit 1
}

# Convert SecureString to plain only for the duration of the child process
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try {
    $plainKey = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

# Trim and validate
$plainKey = $plainKey.Trim()
if (-not ($plainKey -match '^0x[a-fA-F0-9]{64}$')) {
    Write-Host "Error: key format invalid (must be 0x + 64 hex chars)" -ForegroundColor Red
    Remove-Variable plainKey -ErrorAction SilentlyContinue
    exit 1
}

# Set as env var for child process only (doesn't persist to user env)
$env:DEPLOYER_KEY = $plainKey

# ─── Step 2: preflight (verifies key matches the wallet)
Write-Host ""
Write-Host "Step 2/3: pre-flight checks..." -ForegroundColor Yellow
Write-Host ""

try {
    & npx hardhat run scripts/deploy-preflight.js --network tpix
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Pre-flight failed — aborting deploy." -ForegroundColor Red
        $env:DEPLOYER_KEY = $null
        Remove-Variable plainKey -ErrorAction SilentlyContinue
        exit 1
    }
} catch {
    Write-Host "Pre-flight error: $_" -ForegroundColor Red
    $env:DEPLOYER_KEY = $null
    exit 1
}

# ─── Step 3: confirmation + deploy
Write-Host ""
Write-Host "Step 3/3: ready to deploy" -ForegroundColor Yellow
Write-Host ""
Write-Host "This will deploy to TPIX mainnet (chainId 4289):" -ForegroundColor Cyan
Write-Host "  • WTPIX (sale wrapper)"
Write-Host "  • Wrap 700M native TPIX → WTPIX"
Write-Host "  • USDT_TPIX (bridged Tether)"
Write-Host "  • TPIXBondingCurve (700M @ \$0.10→\$1.00)"
Write-Host "  • Transfer 700M WTPIX → BondingCurve"
Write-Host "  • Update ThaiXTrade Config/launchContracts.js"
Write-Host ""
$confirm = Read-Host "Type 'DEPLOY' to confirm, anything else to cancel"

if ($confirm -ne 'DEPLOY') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    $env:DEPLOYER_KEY = $null
    Remove-Variable plainKey -ErrorAction SilentlyContinue
    exit 0
}

# Optional relayer
$relayer = Read-Host "Optional: relayer multisig address for USDT_TPIX bridge (or Enter to skip)"
if ($relayer -match '^0x[a-fA-F0-9]{40}$') {
    $env:RELAYER_ADDRESS = $relayer
    Write-Host "  Will set bridge relayer to: $relayer" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Running deploy-mainnet.js..." -ForegroundColor Green
Write-Host ""

try {
    & npx hardhat run scripts/deploy-mainnet.js --network tpix
    $deployStatus = $LASTEXITCODE
} catch {
    Write-Host "Deploy error: $_" -ForegroundColor Red
    $deployStatus = 1
}

# ─── Cleanup: scrub key from memory
$env:DEPLOYER_KEY = $null
$env:RELAYER_ADDRESS = $null
Remove-Variable plainKey -ErrorAction SilentlyContinue
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

if ($deployStatus -eq 0) {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  ✅ Deploy launcher complete." -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next:"
    Write-Host "  1. Verify on Blockscout:  npm run verify:sources"
    Write-Host "  2. Build frontend:        cd ..\..\ThaiXTrade && npx vite build"
    Write-Host "  3. Push frontend:         git push origin main"
} else {
    Write-Host ""
    Write-Host "Deploy exited with code $deployStatus" -ForegroundColor Red
    exit $deployStatus
}
