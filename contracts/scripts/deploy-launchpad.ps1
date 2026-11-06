# ═══════════════════════════════════════════════════════════════════════════
#  ติดตั้ง TPIX Launchpad (LaunchpadFactory + LaunchVestingDeployer) ขึ้นเชน 4289
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-launchpad.ps1
#
# ทำให้ครบในรอบเดียว:
#   1. ถามคีย์กระเป๋าแบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์)
#   2. ซ้อม deploy บนเครื่องก่อน — ไม่ผ่าน = ไม่แตะเชนจริง
#   3. deploy 2 สัญญาขึ้นเชนจริง แล้วเขียน deployed-contracts.json
#
# สัญญาทั้งสองไม่มีเจ้าของ ไม่มีค่าธรรมเนียม — กระเป๋าที่ deploy ไม่ได้สิทธิ์พิเศษอะไรเลย
# ค่าแก๊สเชน TPIX = 0 ใช้กระเป๋าไหนก็ได้ที่มีตัวตนบนเชน
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'
$env:NPM_CONFIG_UPDATE_NOTIFIER = 'false'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   ติดตั้ง TPIX Launchpad (TPIX Chain 4289)        ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) { Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red; exit 1 }

# ─── 1) คีย์ ───────────────────────────────────────────────────────────────
Say "ขั้นที่ 1/3  คีย์กระเป๋าที่ใช้ deploy" Yellow
Say "  เลขฐานสิบหก 64 ตัว (มีหรือไม่มี 0x ก็ได้) · พิมพ์แล้วไม่ขึ้นจอ · คลิกในหน้าต่างก่อนแล้ววางด้วยคลิกขวา" DarkGray
$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

if (($plainKey.Trim() -split '\s+').Count -ge 12 -and $plainKey -match '^[\sa-zA-Z]+$') {
    Say "นี่คือคำกู้กระเป๋า (12/24 คำ) ไม่ใช่ private key — ไม่ได้ใช้ ไม่ได้เก็บ และไม่ได้ส่งไปไหน" Red
    $plainKey = $null; exit 1
}
$plainKey = ($plainKey -replace '[\s"''`]', '')
if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }
if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    Say "รูปแบบคีย์ไม่ถูกต้อง — ได้รับ $($plainKey.Length) ตัวอักษร (ต้องเป็นเลขฐานสิบหก 64 ตัว)" Red
    $plainKey = $null; exit 1
}

# ─── 2) ซ้อม ──────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/3  ซ้อมบนเครื่อง (ยังไม่แตะเชนจริง)" Yellow
$ErrorActionPreference = 'Continue'
$rehearsal = (npx hardhat run scripts/deploy-launchpad.js 2>&1 | Out-String)
$rehearsalExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($rehearsalExit -ne 0) { Say $rehearsal Red; Say "ซ้อมไม่ผ่าน — หยุด ไม่มีอะไรขึ้นเชน" Red; $plainKey = $null; exit 1 }
Say "  ซ้อมผ่าน" Green

# ─── 3) ของจริง ───────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/3  deploy ขึ้นเชน TPIX จริง" Yellow
$confirm = Read-Host "  พิมพ์ DEPLOY เพื่อยืนยัน"
if ($confirm -ne 'DEPLOY') { Say "ยกเลิก — ไม่มีอะไรขึ้นเชน" Yellow; $plainKey = $null; exit 0 }

$env:DEPLOYER_KEY = $plainKey
try {
    $ErrorActionPreference = 'Continue'
    npx hardhat run scripts/deploy-launchpad.js --network tpix
    $deployExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = 'Stop'
    $env:DEPLOYER_KEY = $null
    $plainKey = $null
}
if ($deployExit -ne 0) { Say "deploy ไม่สำเร็จ (exit $deployExit) — รันซ้ำได้ ตัวที่ขึ้นเชนแล้วจะถูกใช้ต่อ" Red; exit $deployExit }
Say ""
Say "เสร็จแล้ว — แจ้ง Claude ว่า deploy launchpad เสร็จ เพื่อ verify และลงทะเบียนกับเว็บต่อ" Green
