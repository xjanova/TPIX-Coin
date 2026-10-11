# ═══════════════════════════════════════════════════════════════════════════
#  ติดตั้งสะพาน TPIX ↔ wTPIX (BSC) — คลังบนเชน TPIX + wTPIX/ด่าน mint บน BSC
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-wtpix-bridge.ps1
#
# ลำดับที่แนะนำ (รันสคริปต์นี้ 3 รอบ):
#   1) คลังบนเชน TPIX (TPIXBridgeVault)           — ครั้งเดียว · deploy แบบหยุดไว้ (pause)
#      เปิดด้วย scripts/unpause-bridge-vault.js เมื่อฝั่งเว็บเชื่อมสะพาน wTPIX แล้วเท่านั้น
#   2) wTPIX + ด่าน mint บน BSC testnet (ซ้อม)    — ต้องมี tBNB · ตั้งเว็บเป็น testnet แล้วลองไปกลับด้วยยอดเล็ก
#   3) wTPIX + ด่าน mint บน BSC จริง              — ต้องมี BNB ค่าแก๊สเล็กน้อย
#
# คีย์ถามแบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์) และล้างทิ้งทันทีหลังใช้
# กระเป๋าที่ใช้ deploy = เจ้าของถาวรของสัญญา (ตั้งเพดาน · เพิ่ม/ถอน relayer · ปลด pause)
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   ติดตั้งสะพาน TPIX ↔ wTPIX (BSC)                  ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) {
    Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 1) จะติดตั้งอะไร
# ─────────────────────────────────────────────────────────────────────────────
Say "ขั้นที่ 1/4  เลือกสิ่งที่จะติดตั้ง" Yellow
Say "  [1] คลังล็อก TPIX บนเชน TPIX (ทำครั้งเดียว)"
Say "  [2] wTPIX + ด่าน mint บน BSC testnet (ซ้อม — ใช้ tBNB)"
Say "  [3] wTPIX + ด่าน mint บน BSC จริง (ใช้ BNB)"
$choice = (Read-Host "  เลือก 1/2/3").Trim()
switch ($choice) {
    '1' { $script = 'scripts/deploy-bridge-vault.js'; $network = 'tpix'; $label = 'คลังบนเชน TPIX' }
    '2' { $script = 'scripts/deploy-wtpix-bsc.js'; $network = 'bscTestnet'; $label = 'wTPIX บน BSC testnet' }
    '3' { $script = 'scripts/deploy-wtpix-bsc.js'; $network = 'bsc'; $label = 'wTPIX บน BSC จริง' }
    default { Say "ยกเลิก" Red; exit 1 }
}

# ─────────────────────────────────────────────────────────────────────────────
# 2) คีย์ — ถามแบบซ่อน
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/4  คีย์กระเป๋าเจ้าของ" Yellow
Say "  รูปแบบ: เลขฐานสิบหก 64 ตัว (มีหรือไม่มี 0x ก็ได้ — คัดลอกจาก MetaMask ได้เลย) · พิมพ์แล้วไม่ขึ้นจอ" DarkGray
Say ""

$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

# วางคำกู้กระเป๋า (12/24 คำ) ผิดช่องเกิดขึ้นจริงแล้ว — ไม่ใช้ ไม่เก็บ ไม่ส่งไปไหน
if (($plainKey.Trim() -split '\s+').Count -ge 12 -and $plainKey -match '^[\sa-zA-Z]+$') {
    Say "นี่คือคำกู้กระเป๋า (12/24 คำ) ไม่ใช่ private key — ไม่ได้ใช้ ไม่ได้เก็บ และไม่ได้ส่งไปไหน" Red
    Say "  MetaMask → เลือกบัญชี → ⋮ → Account details → Show private key" Red
    $plainKey = $null
    exit 1
}

$plainKey = ($plainKey -replace '[\s"''`]', '')
if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }
if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    Say "รูปแบบคีย์ไม่ถูกต้อง — ได้รับ $($plainKey.Length) ตัวอักษร (ต้องเป็นเลขฐานสิบหก 64 ตัว)" Red
    $plainKey = $null
    exit 1
}

$env:DEPLOYER_KEY = $plainKey
try {
    $deployerAddress = (node -e "const { Wallet } = require('ethers'); console.log(new Wallet(process.env.DEPLOYER_KEY).address)" 2>$null | Select-Object -First 1)
} finally {
    $env:DEPLOYER_KEY = $null
}
if (-not $deployerAddress) { Say "แปลงคีย์เป็นที่อยู่ไม่ได้ — คีย์นี้ใช้ไม่ได้" Red; $plainKey = $null; exit 1 }
Say "  กระเป๋าที่จะใช้: $deployerAddress  ← จะเป็นเจ้าของถาวร" Cyan

# ─────────────────────────────────────────────────────────────────────────────
# 3) เพดาน + บทบาท
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/4  เพดานและบทบาท" Yellow
Say "  เพดานคือความเสียหายสูงสุดต่อวันถ้าคีย์ relayer บนเซิร์ฟเวอร์หลุด — เพิ่มทีหลังได้" DarkGray
Say "  ⚠️ ใช้ค่าเดียวกันทั้งสองฝั่ง: ยอดล็อกสูงสุดของคลัง ต้องไม่เกินเพดานต่อครั้งของฝั่ง BSC" DarkGray

$maxPerTx = (Read-Host "  เพดานต่อครั้ง TPIX (Enter = 100000)").Trim()
if (-not $maxPerTx) { $maxPerTx = '100000' }
$dailyCap = (Read-Host "  เพดานต่อวัน TPIX (Enter = 500000)").Trim()
if (-not $dailyCap) { $dailyCap = '500000' }
if ($maxPerTx -notmatch '^\d+$' -or $dailyCap -notmatch '^\d+$' -or [decimal]$maxPerTx -le 0 -or [decimal]$maxPerTx -gt [decimal]$dailyCap) {
    Say "เพดานไม่ถูกต้อง — ต้องเป็นจำนวนเต็มมากกว่าศูนย์ และต่อครั้งต้องไม่เกินต่อวัน" Red
    $plainKey = $null
    exit 1
}

$relayer = (Read-Host "  ที่อยู่ relayer ของเซิร์ฟเวอร์ (Enter = ตั้งทีหลัง)").Trim()
$guardian = (Read-Host "  ที่อยู่ guardian (Enter = ข้าม)").Trim()
foreach ($a in @($relayer, $guardian)) {
    if ($a -and $a -notmatch '^0x[0-9a-fA-F]{40}$') { Say "ที่อยู่ไม่ถูกรูปแบบ: $a" Red; $plainKey = $null; exit 1 }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4) ยืนยัน แล้ว deploy
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 4/4  ยืนยัน" Yellow
Say "  ติดตั้ง      : $label ($network)"
Say "  เจ้าของ      : $deployerAddress"
Say "  เพดาน       : $maxPerTx ต่อครั้ง · $dailyCap ต่อวัน (UTC)"
Say "  relayer     : $(if ($relayer) { $relayer } else { '(ตั้งทีหลัง)' })"
Say "  guardian    : $(if ($guardian) { $guardian } else { '(ข้าม)' })"
$confirm = (Read-Host "  พิมพ์ DEPLOY เพื่อเริ่ม").Trim()
if ($confirm -cne 'DEPLOY') { Say "ยกเลิก — ไม่ได้ส่งอะไรขึ้นเชน" DarkYellow; $plainKey = $null; exit 1 }

$env:DEPLOYER_KEY = $plainKey
$env:BRIDGE_MAX_PER_TX = $maxPerTx
$env:BRIDGE_DAILY_CAP = $dailyCap
$env:BRIDGE_MAX_LOCK = $maxPerTx
$env:RELAYER_ADDRESS = $relayer
$env:GUARDIAN_ADDRESS = $guardian
if ($network -eq 'bsc') { $env:CONFIRM_MAINNET = 'yes' }
if ($network -eq 'tpix' -and -not $env:TPIX_SITE_URL) { $env:TPIX_SITE_URL = 'https://tpix.online' }

try {
    npx hardhat run $script --network $network
    $exitCode = $LASTEXITCODE
} finally {
    # ล้างความลับทิ้งทุกกรณี — ไม่ค้างใน session ของ PowerShell
    $env:DEPLOYER_KEY = $null
    $env:CONFIRM_MAINNET = $null
    $plainKey = $null
}

if ($exitCode -ne 0) { Say "" ; Say "❌ deploy ไม่สำเร็จ — ดูข้อความด้านบน" Red; exit $exitCode }
Say ""
Say "✅ เสร็จ — ทำ 'ขั้นตอนที่ยังเหลือ' ด้านบนต่อ" Green
