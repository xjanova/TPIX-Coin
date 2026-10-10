# ═══════════════════════════════════════════════════════════════════════════
#  โอน TPIX จากกระเป๋า allocation (master wallet) — เจ้าของรันเองเท่านั้น
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\send-tpix.ps1 -To 0xปลายทาง -Amount 210
#   .\scripts\send-tpix.ps1 -To 0x... -Amount 210 -Role token-sale
#
# ค่าปริยาย -Role = liquidity-market-making (กระเป๋าสภาพคล่องตาม tokenomics 15%)
#
# รหัสผ่าน keystore / คำ 12 คำ ถามแบบซ่อน — ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์
# และถูกล้างออกจาก environment ทันทีที่สคริปต์จบ ไม่ว่าจะสำเร็จหรือล้ม
#
# Developed by Xman Studio

param(
    [Parameter(Mandatory = $true)][string]$To,
    [Parameter(Mandatory = $true)][string]$Amount,
    [string]$Role = 'liquidity-market-making'
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

$walletsPath = '..\wallet-output\wallets.json'
if (-not (Test-Path $walletsPath)) { Say "ไม่พบ $walletsPath" Red; exit 1 }
$entry = (Get-Content $walletsPath -Raw -Encoding UTF8 | ConvertFrom-Json) | Where-Object { $_.role -eq $Role }
if (-not $entry) { Say "ไม่พบกระเป๋า role '$Role' ใน wallets.json" Red; exit 1 }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   โอน TPIX บนเชน 4289                             ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""
Say "  จาก   $Role  $($entry.address)"
Say "  ไปที่  $To"
Say "  จำนวน $Amount TPIX"
Say ""
Say "  ตรวจตัวอักษรหน้า-ท้ายของที่อยู่ปลายทางให้ตรงก่อนไปต่อ" Yellow
Say ""

$password = Read-Hidden "รหัสผ่าน keystore (Enter ว่าง = ใช้คำ 12 คำแทน)"
$mnemonic = ''
if (-not $password) {
    $mnemonic = Read-Hidden "คำ 12 คำ (คั่นด้วยเว้นวรรค)"
    if (-not $mnemonic) { Say "ยกเลิก — ไม่ได้ใส่อะไร" DarkYellow; exit 0 }
}

$confirm = Read-Host "พิมพ์ SEND เพื่อยืนยันการโอน"
if ($confirm -ne 'SEND') {
    $password = $null; $mnemonic = $null
    Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow
    exit 0
}

$env:SEND_ROLE = $Role
$env:SEND_TO = $To
$env:SEND_AMOUNT = $Amount
if ($password) { $env:KEYSTORE_PASSWORD = $password } else { $env:MASTER_MNEMONIC = $mnemonic }

try {
    node scripts/send-from-keystore.js
    $sendExit = $LASTEXITCODE
} finally {
    $env:KEYSTORE_PASSWORD = $null
    $env:MASTER_MNEMONIC = $null
    $password = $null
    $mnemonic = $null
    [GC]::Collect()
}

if ($sendExit -ne 0) { Say "`nโอนไม่สำเร็จ — อ่านข้อความด้านบน รหัสถูกล้างออกจากหน่วยความจำแล้ว" Red; exit 1 }
Say "`nเสร็จแล้ว" Cyan
