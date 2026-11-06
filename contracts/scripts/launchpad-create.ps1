# ═══════════════════════════════════════════════════════════════════════════
#  เปิดขายเหรียญลูกผ่าน LaunchpadFactory (เชน TPIX 4289) — ค่าปริยาย: IDTC
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\launchpad-create.ps1                 (แผนอื่น: .\scripts\launchpad-create.ps1 -Plan xyz)
#
# ทำให้ครบในรอบเดียว — หยุดทันทีถ้าขั้นไหนไม่ผ่าน:
#   1. ถามวันเปิดขาย กระเป๋ารับ vesting และกระเป๋าโครงการ
#   2. ถามคีย์กระเป๋าที่ถือเหรียญแบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์)
#   3. ซ้อมทั้งสายบนเครื่อง (สัญญาจริงจาก build นี้ + เหรียญจำลอง + ลองซื้อ 1 USDT)
#   4. อ่านเชนจริงแล้วแสดงตัวเลขทั้งหมด — ยังไม่ส่งอะไร
#   5. พิมพ์ชื่อเหรียญเพื่อยืนยัน → approve ยอดพอดี → จำลอง → createLaunch → ตั้งขั้นต่ำ → ตรวจผล
#
# ต้องมีก่อน: LaunchpadFactory ใน deployed-contracts.json (deploy-launchpad.ps1)
#             USDT_TPIX ในกระเป๋าเท่ากับ seedUsdt ของแผน (ฝาก USDT จาก BSC ที่ tpix.online/bridge)
# ค่าแก๊สเชน TPIX = 0
#
# Developed by Xman Studio

param([string]$Plan = 'idtc')

$ErrorActionPreference = 'Stop'
$env:NPM_CONFIG_UPDATE_NOTIFIER = 'false'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Clear-LaunchEnv {
    foreach ($n in 'DEPLOYER_KEY', 'CONFIRM_LAUNCH', 'SALE_START', 'BENEFICIARY', 'PROJECT_TREASURY', 'LAUNCH_PLAN', 'SEED_USDT') {
        Remove-Item "Env:$n" -ErrorAction SilentlyContinue
    }
}

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   เปิดขายเหรียญผ่าน TPIX Launchpad (เชน 4289)      ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) { Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red; exit 1 }
if ($Plan -notmatch '^[a-z0-9_-]+$' -or -not (Test-Path ".\scripts\launch-plans\$Plan.json")) { Say "ไม่พบแผน scripts\launch-plans\$Plan.json" Red; exit 1 }
$planJson = Get-Content ".\scripts\launch-plans\$Plan.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$symbol = $planJson.symbol
if (-not $planJson.launchpad) { Say "แผน $Plan ไม่มีหัวข้อ launchpad" Red; exit 1 }

Clear-LaunchEnv
$env:LAUNCH_PLAN = $Plan

# ─── 1) ค่าเปิดขาย ─────────────────────────────────────────────────────────
Say "ขั้นที่ 1/5  ค่าเปิดขาย $symbol" Yellow
Say "  วันเวลาเปิดขาย ต้องมีเขตเวลา เช่น 2026-11-20T10:00:00+07:00 (vesting เริ่มนับวันเดียวกัน)" DarkGray
$env:SALE_START = (Read-Host "  SALE_START").Trim()
Say "  กระเป๋าที่รับเหรียญ vesting เมื่อปลดล็อก (แนะนำ multisig)" DarkGray
$env:BENEFICIARY = (Read-Host "  BENEFICIARY").Trim()
Say "  กระเป๋าโครงการ (แผนนี้ส่งเงินขายเข้าพูล $([int]$planJson.launchpad.poolShareBps / 100)% — ต้องมีที่อยู่ไว้ แม้ไม่ได้รับอะไร)" DarkGray
$env:PROJECT_TREASURY = (Read-Host "  PROJECT_TREASURY").Trim()
foreach ($n in 'BENEFICIARY', 'PROJECT_TREASURY') {
    if ((Get-Item "Env:$n").Value -notmatch '^0x[0-9a-fA-F]{40}$') { Say "$n ไม่ใช่ที่อยู่กระเป๋า" Red; Clear-LaunchEnv; exit 1 }
}

# ─── 2) คีย์ ───────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/5  คีย์กระเป๋าที่ถือ $symbol" Yellow
Say "  เลขฐานสิบหก 64 ตัว (มีหรือไม่มี 0x ก็ได้) · พิมพ์แล้วไม่ขึ้นจอ · คลิกในหน้าต่างก่อนแล้ววางด้วยคลิกขวา" DarkGray
$secureKey = Read-Host -Prompt "  DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; Clear-LaunchEnv; exit 1 }
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

if (($plainKey.Trim() -split '\s+').Count -ge 12 -and $plainKey -match '^[\sa-zA-Z]+$') {
    Say "นี่คือคำกู้กระเป๋า (12/24 คำ) ไม่ใช่ private key — ไม่ได้ใช้ ไม่ได้เก็บ และไม่ได้ส่งไปไหน" Red
    $plainKey = $null; Clear-LaunchEnv; exit 1
}
$plainKey = ($plainKey -replace '[\s"''`]', '')
if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }
if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    Say "รูปแบบคีย์ไม่ถูกต้อง — ได้รับ $($plainKey.Length) ตัวอักษร (ต้องเป็นเลขฐานสิบหก 64 ตัว)" Red
    $plainKey = $null; Clear-LaunchEnv; exit 1
}

try {
    # ─── 3) ซ้อม ──────────────────────────────────────────────────────────
    Say ""
    Say "ขั้นที่ 3/5  ซ้อมบนเครื่อง (ยังไม่แตะเชนจริง)" Yellow
    $saved = @{ start = $env:SALE_START; ben = $env:BENEFICIARY; tre = $env:PROJECT_TREASURY }
    # ซ้อมด้วยวันเริ่มของเครื่องจำลอง — ค่าจริงตรวจในขั้นที่ 4 กับเชนจริง
    Remove-Item Env:SALE_START, Env:BENEFICIARY, Env:PROJECT_TREASURY -ErrorAction SilentlyContinue
    $ErrorActionPreference = 'Continue'
    $rehearsal = (npx hardhat run scripts/launchpad-create.js 2>&1 | Out-String)
    $rehearsalExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $env:SALE_START = $saved.start; $env:BENEFICIARY = $saved.ben; $env:PROJECT_TREASURY = $saved.tre
    if ($rehearsalExit -ne 0) { Say $rehearsal Red; Say "ซ้อมไม่ผ่าน — หยุด ไม่มีอะไรขึ้นเชน" Red; exit 1 }
    Say "  ซ้อมผ่าน" Green

    # ─── 4) ดูตัวเลขจากเชนจริง ────────────────────────────────────────────
    Say ""
    Say "ขั้นที่ 4/5  อ่านเชนจริง — ยังไม่ส่งอะไร" Yellow
    $env:DEPLOYER_KEY = $plainKey
    $ErrorActionPreference = 'Continue'
    npx hardhat run scripts/launchpad-create.js --network tpix
    $previewExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($previewExit -ne 0) { Say "ตรวจไม่ผ่าน — หยุด ไม่มีอะไรขึ้นเชน" Red; exit 1 }

    # ─── 5) ของจริง ───────────────────────────────────────────────────────
    Say ""
    Say "ขั้นที่ 5/5  เปิดขายจริง" Yellow
    Say "  ตรวจตัวเลขด้านบนทุกบรรทัด — หลังส่งแล้วแก้ราคา จำนวน วันล็อก LP และ vesting ไม่ได้อีก" DarkGray
    $confirm = Read-Host "  พิมพ์ $symbol เพื่อยืนยัน"
    if ($confirm -cne $symbol) { Say "ยกเลิก — ไม่มีอะไรขึ้นเชน" Yellow; exit 0 }
    $env:CONFIRM_LAUNCH = $symbol
    $ErrorActionPreference = 'Continue'
    npx hardhat run scripts/launchpad-create.js --network tpix
    $launchExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($launchExit -ne 0) { Say "ไม่สำเร็จ (exit $launchExit) — รันซ้ำได้: ถ้าเปิดไปแล้วสคริปต์จะแสดงสถานะ ไม่เปิดซ้ำ" Red; exit $launchExit }
    Say ""
    Say "เสร็จแล้ว — แจ้ง Claude ที่อยู่ Sale เพื่อ verify และเปิดหน้าขายบนเว็บต่อ" Green
} finally {
    $plainKey = $null
    Clear-LaunchEnv
}
