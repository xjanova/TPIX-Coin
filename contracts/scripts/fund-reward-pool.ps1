# ═══════════════════════════════════════════════════════════════════════════
#  เติมพูลรางวัล Master Node (NodeRegistryV2.fundRewardPool) — เจ้าของรันเองเท่านั้น
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\fund-reward-pool.ps1 -Amount 20000000              # ซ้อมก่อน: เพิ่ม -DryRun
#   .\scripts\fund-reward-pool.ps1 -Amount 20000000 -Registry 0x...
#
# เงินมาจากกระเป๋า allocation "masternode-rewards"
#   m/44'/60'/0'/0/1 · 0xf54c0deE404ec728a03b467cba7bBA171CC77dad · genesis 1,400,000,000 TPIX
#
# ⚠️ ห้ามใช้ send-tpix.ps1 เติมพูล — โอนแบบ 21,000 gas ตายตัว แต่ receive() ของสัญญา
#    ใช้ราว 30,000 → tx ล้ม (แก๊สหมด) สคริปต์นี้เรียก fundRewardPool() + ประเมินแก๊สจากเชน
# ⚠️ เงินที่เติมเข้าพูล "ถอนคืนไม่ได้" (สัญญาไม่มีฟังก์ชันถอนของใครเลย) — เติมเป็นงวด
#    สคริปต์โชว์อัตราจ่ายรางวัลตอนนี้ และบอกว่าเงินในพูลพอจ่ายอีกกี่วัน
#
# รหัสผ่าน keystore / คำ 12 คำ ถามแบบซ่อน — ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์
# และถูกล้างออกจาก environment ทันทีที่สคริปต์จบ ไม่ว่าจะสำเร็จหรือล้ม
#
# Developed by Xman Studio

param(
    [Parameter(Mandatory = $true)][string]$Amount,
    [string]$Registry = '',
    [string]$Role = 'masternode-rewards',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

function Read-Hidden($prompt) {
    $secure = Read-Host -Prompt $prompt -AsSecureString
    if ($secure.Length -eq 0) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if (-not (Test-Path .\hardhat.config.js)) {
    Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red
    exit 1
}
if ($Amount -notmatch '^\d+(\.\d{1,18})?$') { Say "จำนวนไม่ถูกต้อง: $Amount (ใส่เป็นตัวเลข TPIX เช่น 20000000)" Red; exit 1 }
if (-not (Test-Path '..\wallet-output\wallets.json')) { Say "ไม่พบ ..\wallet-output\wallets.json" Red; exit 1 }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   เติมพูลรางวัล Master Node บนเชน 4289             ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

$env:FUND_AMOUNT = $Amount
$env:FUND_ROLE = $Role
if ($Registry) { $env:REGISTRY_ADDRESS = $Registry } else { $env:REGISTRY_ADDRESS = $null }

# ── รอบแรกเสมอ: ซ้อม (ตรวจสัญญา + ยอด + ประเมินแก๊ส) โดยไม่ต้องใช้กุญแจ ──
$env:DRY_RUN = '1'
try {
    node scripts/fund-reward-pool.js
    $dryExit = $LASTEXITCODE
} finally {
    $env:DRY_RUN = $null
}
if ($dryExit -ne 0) {
    Say "`nตรวจไม่ผ่าน — ยังไม่ได้ส่งอะไร อ่านข้อความด้านบน" Red
    $env:FUND_AMOUNT = $null; $env:FUND_ROLE = $null; $env:REGISTRY_ADDRESS = $null
    exit 1
}
if ($DryRun) {
    Say "`n-DryRun: จบแค่การซ้อม ไม่ได้ส่งอะไรขึ้นเชน" DarkYellow
    $env:FUND_AMOUNT = $null; $env:FUND_ROLE = $null; $env:REGISTRY_ADDRESS = $null
    exit 0
}

Say ""
Say "  ตรวจที่อยู่สัญญาและจำนวนด้านบนให้ตรงก่อนไปต่อ — เงินที่เติมแล้วถอนคืนไม่ได้" Yellow
Say ""

$password = Read-Hidden "รหัสผ่าน keystore ของ $Role (Enter ว่าง = ใช้คำ 12 คำแทน)"
$mnemonic = ''
if (-not $password) {
    $mnemonic = Read-Hidden "คำ 12 คำ (คั่นด้วยเว้นวรรค)"
    if (-not $mnemonic) {
        Say "ยกเลิก — ไม่ได้ใส่อะไร" DarkYellow
        $env:FUND_AMOUNT = $null; $env:FUND_ROLE = $null; $env:REGISTRY_ADDRESS = $null
        exit 0
    }
}

$confirm = Read-Host "พิมพ์ FUND เพื่อยืนยันการเติม $Amount TPIX เข้าพูล"
if ($confirm -ne 'FUND') {
    $password = $null; $mnemonic = $null
    $env:FUND_AMOUNT = $null; $env:FUND_ROLE = $null; $env:REGISTRY_ADDRESS = $null
    Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow
    exit 0
}

if ($password) { $env:KEYSTORE_PASSWORD = $password } else { $env:MASTER_MNEMONIC = $mnemonic }

try {
    node scripts/fund-reward-pool.js
    $sendExit = $LASTEXITCODE
} finally {
    $env:KEYSTORE_PASSWORD = $null
    $env:MASTER_MNEMONIC = $null
    $env:FUND_AMOUNT = $null
    $env:FUND_ROLE = $null
    $env:REGISTRY_ADDRESS = $null
    $password = $null
    $mnemonic = $null
    [GC]::Collect()
}

if ($sendExit -ne 0) { Say "`nเติมไม่สำเร็จ — อ่านข้อความด้านบน รหัสถูกล้างออกจากหน่วยความจำแล้ว" Red; exit 1 }
Say "`nเสร็จแล้ว — หน้า /masternode จะโชว์ยอด 'จ่ายได้จริงตอนนี้' ภายใน ~30 วินาที" Cyan
