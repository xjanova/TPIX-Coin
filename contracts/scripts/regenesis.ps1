# Regenesis launcher - generates BIP-44 HD master wallet (11 derivations per whitepaper)
# and updates genesis.json files locally, then commits + pushes for server pull.
#
# Usage:
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\regenesis.ps1

$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  TPIX Chain - Regenesis (whitepaper allocation)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path .\hardhat.config.js)) {
    Write-Host "Error: run this from D:\Code\TPIX\TPIX-Coin\contracts" -ForegroundColor Red
    exit 1
}

$walletDir = Join-Path (Get-Location).Path "..\wallet-output"
if (Test-Path "$walletDir\wallets.json") {
    Write-Host "ERROR: wallet-output\ already has a wallet generated." -ForegroundColor Red
    Write-Host "       Move/rename the directory first if you want to regenerate." -ForegroundColor Yellow
    exit 1
}

# --- Step 1: keystore password
Write-Host "Step 1/6: choose a STRONG password for keystore encryption" -ForegroundColor Yellow
Write-Host "  (will encrypt master-wallet.keystores.json - 12+ chars)"
$securePwd  = Read-Host -Prompt "Password" -AsSecureString
$securePwd2 = Read-Host -Prompt "Confirm"  -AsSecureString
$bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd2)
try {
    $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
    $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
}
if ($pwd1 -ne $pwd2) { Write-Host "ERROR: Passwords don't match." -ForegroundColor Red; exit 1 }
if ($pwd1.Length -lt 12) { Write-Host "ERROR: Too short (12+)." -ForegroundColor Red; exit 1 }

# --- Step 2: generate wallet
Write-Host ""
Write-Host "Step 2/6: generating BIP-44 HD wallet (11 derivations)..." -ForegroundColor Yellow
$env:KEYSTORE_PASSWORD = $pwd1
try {
    & node scripts/generate-master-wallet.js
    if ($LASTEXITCODE -ne 0) { exit 1 }
} finally {
    $env:KEYSTORE_PASSWORD = $null
    Remove-Variable pwd1 -ErrorAction SilentlyContinue
    Remove-Variable pwd2 -ErrorAction SilentlyContinue
    [GC]::Collect()
}

$walletDir = Resolve-Path (Join-Path (Get-Location).Path "..\wallet-output")
$mnemonicFile = Join-Path $walletDir "master-wallet.mnemonic.txt"
$privateKeyFile = Join-Path $walletDir "master-wallet.privatekeys.txt"
$readmeFile = Join-Path $walletDir "README.md"
$walletsFile = Join-Path $walletDir "wallets.json"

# --- Step 3: open files for backup
Write-Host ""
Write-Host "Step 3/6: backup the wallet" -ForegroundColor Yellow
Write-Host ""
Write-Host "Opening files in Notepad - copy each to safe places:" -ForegroundColor Cyan
Write-Host "  1. MNEMONIC      -> write on 3 papers, keep in 3 different physical locations" -ForegroundColor Cyan
Write-Host "  2. PRIVATE KEYS  -> 11 entries -> Bitwarden/1Password (one entry per role)" -ForegroundColor Cyan
Write-Host "  3. README.md     -> checklist + verification commands" -ForegroundColor Cyan
Write-Host ""

Start-Process notepad.exe $readmeFile
Start-Sleep -Seconds 1
Start-Process notepad.exe $mnemonicFile
Start-Sleep -Seconds 1
Start-Process notepad.exe $privateKeyFile

Write-Host "  Wallets summary saved to: wallets.json" -ForegroundColor Green
Write-Host ""
Write-Host "WARNING: After backup, BOTH plaintext files MUST be deleted from disk." -ForegroundColor Yellow
Write-Host ""
$ack = Read-Host "Type 'BACKED UP' when mnemonic + private keys are saved to your password manager + paper"
if ($ack -ne "BACKED UP") {
    Write-Host "Aborting before genesis change. Re-run when ready." -ForegroundColor Yellow
    exit 0
}

# --- Step 4: delete plaintext (encrypted keystores remain)
Write-Host ""
Write-Host "Step 4/6: deleting plaintext key files..." -ForegroundColor Yellow
Remove-Item $mnemonicFile -Force
Remove-Item $privateKeyFile -Force
Write-Host "  OK Deleted mnemonic.txt + privatekeys.txt"
Write-Host "  OK Encrypted keystores preserved: master-wallet.keystores.json"

# --- Step 5: update genesis.json
Write-Host ""
Write-Host "Step 5/6: updating genesis.json files..." -ForegroundColor Yellow
& node scripts/update-genesis.js
if ($LASTEXITCODE -ne 0) { exit 1 }

# --- Step 6: commit + push
Write-Host ""
Write-Host "Step 6/6: commit + push to GitHub" -ForegroundColor Yellow
$repoRoot = Resolve-Path (Join-Path (Get-Location).Path "..")
Push-Location $repoRoot
try {
    # Only stage paths that actually exist (infrastructure/data lives on server, not in git)
    $toAdd = @()
    foreach ($p in @(
        'infrastructure/genesis.json',
        'infrastructure/data',
        '.gitignore',
        'wallet-output/wallets.json',
        'wallet-output/README.md'
    )) {
        if (Test-Path $p) { $toAdd += $p }
    }
    if ($toAdd.Count -gt 0) {
        & git add @toAdd 2>&1 | Out-Null
    }
    & git commit -m "chore(chain): regenesis - whitepaper-aligned BIP-44 HD allocation"
    & git push origin main
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " OK - Local regenesis prep complete." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next on server (PuTTY):" -ForegroundColor Cyan
Write-Host "  cd ~/TPIX-Coin && git pull"
Write-Host "  sudo bash infrastructure/scripts/restart-chain.sh"
Write-Host ""
Write-Host "Block height will reset to 0 with new allocations visible at"
Write-Host "https://explorer.tpix.online ~30 sec after validators come back up." -ForegroundColor Cyan
Write-Host ""
Write-Host "Then deploy contracts (uses Token Sale wallet path m/44 60 0/0/4):" -ForegroundColor Cyan
Write-Host "  cd contracts ; .\scripts\deploy-launch.ps1"
Write-Host ""
