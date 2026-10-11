# ═══════════════════════════════════════════════════════════════════════════
#  ติดตั้ง TPIX Token Factory ขึ้นเชนจริง — คำสั่งเดียวจบ
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-token-factory.ps1
#
# ทำให้ครบในรอบเดียว:
#   1. ถามคีย์กระเป๋า deploy แบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์)
#   2. ถามที่อยู่ "กระเป๋าผู้ดำเนินการ" ของเว็บ (ใบที่เซิร์ฟเวอร์ใช้เซ็นคำสั่งสร้างเหรียญ)
#   3. ตรวจว่าเชนรับ bytecode ได้จริงก่อน (ด่าน PUSH0)
#   4. deploy creator 7 ตัว + TPIXTokenFactoryV2 + TPIXNFTFactory แล้วผูก creator กับ factory
#   5. โอนสิทธิ์สร้างเหรียญให้กระเป๋าผู้ดำเนินการ แล้วตรวจ owner บนเชนซ้ำ
#
# กระเป๋า deploy ไม่ได้ถือสิทธิ์อะไรต่อหลังจบ — สิทธิ์สร้างเหรียญไปอยู่ที่กระเป๋าผู้ดำเนินการ
# creator ทุกตัวผูกได้ครั้งเดียว ใครก็ไปผูกแทรกไม่ได้ (CreatorAccess)
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   ติดตั้ง TPIX Token Factory ขึ้นเชน 4289          ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) {
    Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 1) คีย์ — ถามแบบซ่อน
# ─────────────────────────────────────────────────────────────────────────────
Say "ขั้นที่ 1/5  คีย์กระเป๋าที่จะใช้ deploy" Yellow
Say "  ใช้กระเป๋า deploy ใบเดิมที่ใช้ตอนติดตั้ง DEX ได้ (ค่าแก๊สบนเชนเป็น 0)"
Say "  รูปแบบ: เลขฐานสิบหก 64 ตัว มีหรือไม่มี 0x ก็ได้ · พิมพ์แล้วไม่ขึ้นจอ" DarkGray
Say ""

$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

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
Say "  กระเป๋าที่จะใช้ deploy: $deployerAddress" Cyan

# ─────────────────────────────────────────────────────────────────────────────
# 2) กระเป๋าผู้ดำเนินการของเว็บ
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/5  ที่อยู่กระเป๋าผู้ดำเนินการของเว็บ (FACTORY_OPERATOR)" Yellow
Say "  ใบที่เซิร์ฟเวอร์ tpix.online ใช้เซ็นคำสั่งสร้างเหรียญ — Claude สร้างไว้บนเซิร์ฟเวอร์และแจ้งที่อยู่ให้แล้ว"
Say "  วางเฉพาะที่อยู่ 0x... (ไม่ใช่คีย์)" DarkGray

$operator = $env:FACTORY_OPERATOR
if (-not $operator) { $operator = (Read-Host "  FACTORY_OPERATOR").Trim() }
$operator = ($operator -replace '[\s"''`]', '')
if ($operator -notmatch '^0x[0-9a-fA-F]{40}$') {
    Say "ที่อยู่ไม่ถูกต้อง — ต้องเป็น 0x ตามด้วยเลขฐานสิบหก 40 ตัว" Red
    $plainKey = $null
    exit 1
}
if ($operator.ToLower() -eq $deployerAddress.ToLower()) {
    Say "  ผู้ดำเนินการเป็นกระเป๋าเดียวกับที่ deploy — จะไม่มีการโอนสิทธิ์" DarkYellow
} else {
    Say "  สิทธิ์สร้างเหรียญจะถูกโอนให้: $operator" Cyan
    Say "  ตรวจทีละตัวอักษรกับที่ Claude แจ้ง — โอนผิดคือเสียสิทธิ์สร้างเหรียญถาวร (เหรียญที่มีอยู่ไม่กระทบ)" DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# 3) ตรวจว่าเชนรับ bytecode ได้
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/5  ตรวจว่าเชนรับ bytecode ได้ (อ่านอย่างเดียว ไม่เสียอะไร)" Yellow
npx hardhat compile 2>&1 | Select-Object -Last 1 | ForEach-Object { Say "    $_" DarkGray }
node scripts/check-deployable.js 2>&1 | Select-String -Pattern 'Creator|TPIXTokenFactoryV2|TPIXNFTFactory|ผ่าน |ไม่ผ่าน' | ForEach-Object { Say "    $_" DarkGray }

# ─────────────────────────────────────────────────────────────────────────────
# 4) ยืนยันแล้ว deploy
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 4/5  deploy ขึ้นเชน 4289 ของจริง" Yellow
Say "  creator 7 ตัว + TPIXTokenFactoryV2 + TPIXNFTFactory · ผูก creator · โอนสิทธิ์ให้ผู้ดำเนินการ" DarkGray
$confirm = Read-Host "  พิมพ์ DEPLOY เพื่อยืนยัน"
if ($confirm -ne 'DEPLOY') { Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow; $plainKey = $null; exit 0 }

$env:DEPLOYER_KEY = $plainKey
$env:FACTORY_OPERATOR = $operator
if (-not $env:TPIX_SITE_URL) { $env:TPIX_SITE_URL = 'https://tpix.online' }

try {
    npx hardhat run scripts/deploy-token-factory.js --network tpix
    $deployExit = $LASTEXITCODE
} finally {
    $env:DEPLOYER_KEY = $null
    $env:FACTORY_OPERATOR = $null
    $plainKey = $null
    [GC]::Collect()
}

if ($deployExit -ne 0) { Say "`ndeploy ไม่สำเร็จ — อ่านข้อความด้านบน คีย์ถูกล้างออกจากหน่วยความจำแล้ว" Red; exit 1 }

# ─────────────────────────────────────────────────────────────────────────────
# 5) ขั้นต่อไป
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 5/5  เสร็จฝั่งเชนแล้ว" Yellow
Say "  ที่อยู่ทั้งหมดถูกบันทึกใน deployed-contracts.json แล้ว" Green
Say "  บอก Claude ว่า 'deploy factory แล้ว' — Claude จะลงทะเบียนกับเว็บฝั่งเซิร์ฟเวอร์และ verify ซอร์สบน explorer ให้" Green
Say ""
Say "เสร็จแล้ว" Cyan
