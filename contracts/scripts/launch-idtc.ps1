# ═══════════════════════════════════════════════════════════════════════════
#  เปิดตัว IDTC บนเชน TPIX — ล็อก 70% + presale + พูล 2 คู่ + ล็อก LP ในคำสั่งเดียว
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\launch-idtc.ps1
#
# ก่อนรัน: สร้างเหรียญ IDTC ผ่าน TPIX Token Factory แล้ว (standard: ไม่มี mint/pause/blacklist/auto-burn)
#          และกระเป๋าที่ถือเหรียญทั้ง 1.1T ต้องมี USDT บนเชน TPIX ≥ 10 และ TPIX ≥ 100 สำหรับเปิดพูล
#
# ทำตามลำดับ (หยุดทันทีถ้าขั้นไหนไม่ผ่าน · รันซ้ำได้ ขั้นที่เสร็จแล้วจะถูกข้าม):
#   1. ถามคีย์กระเป๋าที่ถือ IDTC แบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์)
#   2. ถามที่อยู่เหรียญ ผู้รับเหรียญล็อก ผู้รับ LP วันเริ่มล็อก ช่วงขาย กระเป๋ารับเงิน
#   3. ซ้อมทั้งสายบนเครื่อง (launch-token.js + launch-pools.js บน hardhat) — ไม่ผ่าน = ไม่แตะเชนจริง
#   4. ของจริง: deploy สัญญาล็อก + presale → ฝากเหรียญ (fund-launch.js) → เปิดพูล + ล็อก LP
#   5. พิมพ์สถานะจากเชนและที่อยู่ที่ต้องใส่ในหลังบ้าน idtc.online
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function AskAddress($label, $envName) {
    $v = [Environment]::GetEnvironmentVariable($envName)
    if (-not $v) { $v = (Read-Host "  $label").Trim() }
    $v = ($v -replace '[\s"''`]', '')
    if ($v -notmatch '^0x[0-9a-fA-F]{40}$') { Say "  $label ไม่ใช่ที่อยู่ (0x + เลขฐานสิบหก 40 ตัว)" Red; exit 1 }
    return $v
}
function AskText($label, $envName, $example) {
    $v = [Environment]::GetEnvironmentVariable($envName)
    if (-not $v) { $v = (Read-Host "  $label (เช่น $example)").Trim() }
    if (-not $v) { Say "  ต้องใส่ $label" Red; exit 1 }
    return $v
}
function ClearEnv { foreach ($k in 'DEPLOYER_KEY','TOKEN','BENEFICIARY','LP_BENEFICIARY','VESTING_START','SALE_CAP','SALE_START','SALE_END','SALE_TREASURY','SALE_OWNER') { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   เปิดตัว IDTC บนเชน TPIX (4289)                  ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) { Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red; exit 1 }

# ─── 1) คีย์ ───────────────────────────────────────────────────────────────
Say "ขั้นที่ 1/5  คีย์กระเป๋าที่ถือ IDTC ทั้งหมด (กระเป๋าที่สร้างเหรียญผ่าน Token Factory)" Yellow
Say "  พิมพ์แล้วไม่ขึ้นจอ · เลขฐานสิบหก 64 ตัว มีหรือไม่มี 0x ก็ได้" DarkGray
$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
if (($plainKey.Trim() -split '\s+').Count -ge 12 -and $plainKey -match '^[\sa-zA-Z]+$') {
    Say "นี่คือคำกู้กระเป๋า (12/24 คำ) ไม่ใช่ private key — ไม่ได้ใช้ ไม่ได้เก็บ" Red; $plainKey = $null; exit 1
}
$plainKey = ($plainKey -replace '[\s"''`]', '')
if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }
if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') { Say "รูปแบบคีย์ไม่ถูกต้อง" Red; $plainKey = $null; exit 1 }
$env:DEPLOYER_KEY = $plainKey
try { $holder = (node -e "const { Wallet } = require('ethers'); console.log(new Wallet(process.env.DEPLOYER_KEY).address)" 2>$null | Select-Object -First 1) } finally { $env:DEPLOYER_KEY = $null }
if (-not $holder) { Say "แปลงคีย์เป็นที่อยู่ไม่ได้" Red; $plainKey = $null; exit 1 }
Say "  กระเป๋า: $holder" Cyan

# ─── 2) ค่าเปิดตัว ──────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/5  ค่าเปิดตัว (ตรวจทีละตัวอักษร — สัญญาแก้ค่าพวกนี้ไม่ได้หลัง deploy)" Yellow
$token = AskAddress "ที่อยู่เหรียญ IDTC" 'TOKEN'
$beneficiary = AskAddress "ผู้รับเหรียญล็อก 770B (แนะนำ multisig)" 'BENEFICIARY'
$lpBeneficiary = AskAddress "ผู้รับ LP เมื่อครบล็อก 12 เดือน (แนะนำ multisig)" 'LP_BENEFICIARY'
$treasury = AskAddress "กระเป๋ารับ USDT จาก presale" 'SALE_TREASURY'
$vestStart = AskText "วันเริ่มนับล็อก (วันเปิดตลาด)" 'VESTING_START' '2026-11-01T00:00:00+07:00'
$saleStart = AskText "เริ่มขาย presale" 'SALE_START' '2026-11-01T10:00:00+07:00'
$saleEnd = AskText "ปิดขาย presale" 'SALE_END' '2027-01-31T23:59:59+07:00'
$saleOwner = $env:SALE_OWNER
if (-not $saleOwner) { $saleOwner = (Read-Host "  ผู้คุม presale (หยุดขาย/ตั้งเพดาน) — Enter = กระเป๋านี้").Trim() }
if ($saleOwner -and $saleOwner -notmatch '^0x[0-9a-fA-F]{40}$') { Say "  ผู้คุม presale ไม่ใช่ที่อยู่" Red; exit 1 }

Say ""
Say "  เหรียญ          $token"
Say "  ล็อก 770B → $beneficiary · เริ่มนับ $vestStart"
Say "  presale 100B ที่ `$0.0000015 · $saleStart → $saleEnd · เงินเข้า $treasury"
Say "  พูล IDTC/USDT 10 USDT + IDTC/TPIX 100 TPIX ที่ราคา presale · LP ล็อก 12 เดือน → $lpBeneficiary"

# ─── 3) ซ้อม ────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/5  ซ้อมทั้งสายบนเครื่อง (ไม่แตะเชนจริง)" Yellow
ClearEnv   # ค่าที่ตั้งไว้ล่วงหน้า (เช่น TOKEN ของเชนจริง) ต้องไม่หลุดเข้ารอบซ้อม — เก็บไว้ในตัวแปรแล้ว
npx hardhat run scripts/launch-token.js 2>&1 | Select-Object -Last 4 | ForEach-Object { Say "    $_" DarkGray }
if ($LASTEXITCODE -ne 0) { Say "ซ้อม launch-token ไม่ผ่าน — หยุด" Red; $plainKey = $null; exit 1 }
npx hardhat run scripts/launch-pools.js 2>&1 | Select-Object -Last 4 | ForEach-Object { Say "    $_" DarkGray }
if ($LASTEXITCODE -ne 0) { Say "ซ้อม launch-pools ไม่ผ่าน — หยุด" Red; $plainKey = $null; exit 1 }

# ─── 4) ของจริง ─────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 4/5  ขึ้นเชน 4289 ของจริง: สัญญาล็อก + presale → ฝากเหรียญ 870B → พูล 2 คู่ + ล็อก LP" Yellow
$confirm = Read-Host "  พิมพ์ LAUNCH เพื่อยืนยัน"
if ($confirm -ne 'LAUNCH') { Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow; $plainKey = $null; exit 0 }

$env:DEPLOYER_KEY = $plainKey
$env:TOKEN = $token
$env:BENEFICIARY = $beneficiary
$env:LP_BENEFICIARY = $lpBeneficiary
$env:VESTING_START = $vestStart
$env:SALE_CAP = '100000000000'
$env:SALE_START = $saleStart
$env:SALE_END = $saleEnd
$env:SALE_TREASURY = $treasury
if ($saleOwner) { $env:SALE_OWNER = $saleOwner }
$failed = $null
try {
    npx hardhat run scripts/launch-token.js --network tpix
    if ($LASTEXITCODE -ne 0) { $failed = 'launch-token.js' }
    if (-not $failed) { npx hardhat run scripts/fund-launch.js --network tpix; if ($LASTEXITCODE -ne 0) { $failed = 'fund-launch.js' } }
    if (-not $failed) { npx hardhat run scripts/launch-pools.js --network tpix; if ($LASTEXITCODE -ne 0) { $failed = 'launch-pools.js' } }
} finally {
    ClearEnv
    $plainKey = $null
    [GC]::Collect()
}
if ($failed) { Say "`n$failed ไม่สำเร็จ — อ่านข้อความด้านบน รันสคริปต์นี้ซ้ำได้ (ขั้นที่เสร็จแล้วจะถูกข้าม) คีย์ถูกล้างแล้ว" Red; exit 1 }

# ─── 5) สถานะ ───────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 5/5  สถานะจากเชน" Yellow
$env:STATUS = '1'
try {
    npx hardhat run scripts/launch-token.js --network tpix
    npx hardhat run scripts/launch-pools.js --network tpix
} finally { Remove-Item Env:STATUS -ErrorAction SilentlyContinue }
Say ""
Say "บอก Claude ว่า 'เปิดตัว IDTC แล้ว' — Claude จะใส่ที่อยู่สัญญาที่ idtc.online, verify ซอร์สบน explorer และตรวจหน้าเว็บให้" Green
