# Interactive owner signing; the private key is never a command argument or file.
# Run in a dedicated PowerShell window. -Rehearsal uses only the local Hardhat chain.
param([switch]$Rehearsal)

$ErrorActionPreference = 'Stop'
$expectedOwner = '0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7'
$secureKey = $null
$plainKey = $null
Push-Location (Join-Path $PSScriptRoot '..')
try {
    Write-Host 'Step 1: compile and verify the reviewed release hash.' -ForegroundColor Cyan
    & npx.cmd --no-install hardhat compile
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed. No transaction sent.' }
    $verifyBuild = @'
const { keccak256 } = require('ethers');
const a = require('./artifacts/src/masternode/NodeRegistryV2.sol/NodeRegistryV2.json');
const expected = require('./masternode-release-hash.json').runtimeCodeHash;
if (keccak256(a.deployedBytecode) !== expected) { console.error('Build hash mismatch'); process.exit(1); }
console.log('Verified runtime:', expected);
'@
    & node -e $verifyBuild
    if ($LASTEXITCODE -ne 0) { throw 'Build verification failed. No transaction sent.' }

    if ($Rehearsal) {
        # Do not pass any inherited real key to the local rehearsal.
        $env:DEPLOYER_KEY = $null
        & npx.cmd --no-install hardhat run scripts/stage-masternode-release.js
        if ($LASTEXITCODE -ne 0) { throw 'Local rehearsal failed.' }
        return
    }

    Write-Host ''
    Write-Host 'Step 2: enter the OWNER private key in this hidden prompt.' -ForegroundColor Cyan
    Write-Host "Required owner: $expectedOwner"
    Write-Host 'Input stays in this local process. Do not enter a seed phrase.'
    $secureKey = Read-Host 'OWNER PRIVATE KEY (hidden)' -AsSecureString
    if ($secureKey.Length -eq 0) { throw 'Cancelled. No transaction sent.' }
    $keyBuffer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyBuffer).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyBuffer) }
    if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }
    if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') { throw 'Invalid private-key format. No transaction sent.' }
    $env:DEPLOYER_KEY = $plainKey
    $plainKey = $null
    $deriveAddress = @'
try { console.log(new (require('ethers').Wallet)(process.env.DEPLOYER_KEY).address); }
catch { console.error('Invalid private key'); process.exit(1); }
'@
    $deployerAddress = & node -e $deriveAddress
    if ($LASTEXITCODE -ne 0 -or $deployerAddress -ne $expectedOwner) {
        throw 'This key is not the required owner. No transaction sent.'
    }
    Write-Host "Owner verified: $deployerAddress" -ForegroundColor Green
    Write-Host ''
    Write-Host 'Step 3: real transactions on TPIX chain 4289.' -ForegroundColor Yellow
    Write-Host 'Pause the two empty previous registries; deploy a paused registry; reuse existing KYC.'
    Write-Host 'The script rechecks ownership, history and balances before proceeding.'
    Write-Host 'Website discovery, reward funding, oracle and registration activation are separate steps.'
    Write-Host 'If following guided deployment, STOP HERE and report only the owner address.' -ForegroundColor Cyan
    $confirmation = Read-Host 'Type DEPLOY only when ready to send these transactions (anything else cancels)'
    if ($confirmation -cne 'DEPLOY') { Write-Host 'Cancelled. No transaction sent.'; return }

    & npx.cmd --no-install hardhat run scripts/stage-masternode-release.js --network tpix
    if ($LASTEXITCODE -ne 0) {
        throw 'Staging stopped. Some transactions may already be mined. Check owner transaction history before retrying.'
    }
    Write-Host 'Staged. Keep registration closed and retain the public manifest printed above.' -ForegroundColor Green
} finally {
    $env:DEPLOYER_KEY = $null
    $plainKey = $null
    if ($null -ne $secureKey) { $secureKey.Dispose() }
    Pop-Location
}
