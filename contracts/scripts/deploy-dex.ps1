# ═══════════════════════════════════════════════════════════════════════════
#  ติดตั้ง TPIX DEX ขึ้นเชนจริง — คำสั่งเดียวจบ
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-dex.ps1
#
# ทำให้ครบในรอบเดียว:
#   1. ถามคีย์กระเป๋าแบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์)
#   2. ดึงโทเคนทะเบียนสัญญา + กระเป๋ารับค่าธรรมเนียม จากเซิร์ฟเวอร์ให้เอง
#   3. ตรวจว่าเชนรับ bytecode ได้จริงก่อนเสียเวลา (ด่าน PUSH0)
#   4. deploy WTPIX + USDT_TPIX + Factory + Router
#   5. ลงทะเบียนที่อยู่กับเว็บให้เอง → เว็บเปิดเทรดเองภายใน 1 นาที
#   6. ตรวจผลจากเว็บจริงว่าพร้อมแล้ว
#
# ⚠️ สำคัญที่สุด — กระเป๋าที่ใช้ deploy จะกลายเป็น "เจ้าของถาวร" ของ:
#      • USDT_TPIX  → สั่ง mint/burn ได้ (setBridge) และสั่งหยุดเหรียญได้ (pause)
#      • TPIXDEXFactory → เปลี่ยนปลายทางส่วนแบ่งค่าธรรมเนียมได้ (feeToSetter)
#    ใช้กระเป๋าที่คุณถือคีย์เองและเก็บรักษาได้ระยะยาวเท่านั้น
#    ห้ามใช้กระเป๋าชั่วคราวหรือกระเป๋าที่คนอื่นเคยเห็นคีย์
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   ติดตั้ง TPIX DEX ขึ้นเชน 4289 (ปลอดภัย)          ║" Cyan
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
Say "  กระเป๋านี้จะเป็นเจ้าของ USDT_TPIX (สิทธิ์ mint) และคุมค่าธรรมเนียมของ DEX"
Say "  ต้องมี TPIX อยู่จริงบนเชน (ค่าแก๊สเป็น 0 แต่บัญชีต้องมีตัวตน)"
Say "  แนะนำ: กระเป๋าคลัง 0x4BcC1844Ad9E8587f7005f092928a5D14C30F463 (ถือ 700M TPIX)"
Say "  รูปแบบ: 0x + เลขฐานสิบหก 64 ตัว · พิมพ์แล้วไม่ขึ้นจอ" DarkGray
Say ""

$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    Say "รูปแบบคีย์ไม่ถูกต้อง — ต้องเป็น 0x ตามด้วยเลขฐานสิบหก 64 ตัว" Red
    $plainKey = $null
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 2) ค่าจากเซิร์ฟเวอร์ — ดึงให้เอง ไม่ต้องพิมพ์
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/5  ดึงค่าจากเซิร์ฟเวอร์" Yellow

$siteUrl = if ($env:TPIX_SITE_URL) { $env:TPIX_SITE_URL } else { 'https://tpix.online' }
$sshHost = if ($env:TPIX_SSH_HOST) { $env:TPIX_SSH_HOST } else { 'admin@123.253.62.251' }
$appPath = '/home/admin/domains/tpix.online'

$registryToken = $env:CONTRACT_REGISTRY_TOKEN
if (-not $registryToken) {
    Say "  ดึง CONTRACT_REGISTRY_TOKEN ผ่าน ssh ..." DarkGray
    try {
        $registryToken = (ssh $sshHost "grep '^CONTRACT_REGISTRY_TOKEN=' $appPath/.env | cut -d= -f2" 2>$null | Select-Object -First 1).Trim()
    } catch { $registryToken = $null }
}
if ($registryToken) {
    Say "  โทเคนทะเบียนสัญญา: ได้แล้ว ($($registryToken.Length) ตัวอักษร)" Green
} else {
    Say "  ดึงโทเคนไม่ได้ — สคริปต์จะ deploy ต่อ แล้วพิมพ์บรรทัด .env ให้ก๊อปเอง" DarkYellow
}

# กระเป๋ารับส่วนแบ่งค่าธรรมเนียม — ใช้ใบเดียวกับที่เว็บตั้งไว้ เพื่อไม่ให้สองฝั่งหลุดจากกัน
$feeCollector = $env:FEE_COLLECTOR
if (-not $feeCollector) {
    try {
        $feeInfo = Invoke-RestMethod -Uri "$siteUrl/api/v1/trading/fee-info?chain_id=56" -TimeoutSec 15
        $feeCollector = $feeInfo.data.fee_collector
    } catch { $feeCollector = $null }
}
if ($feeCollector) { Say "  กระเป๋ารับค่าธรรมเนียม: $feeCollector" Green }
else { Say "  ไม่ได้ตั้ง FEE_COLLECTOR — LP จะได้ค่าธรรมเนียม 0.3% เต็ม (ตั้งทีหลังได้)" DarkYellow }

# ─────────────────────────────────────────────────────────────────────────────
# 3) ราคาเปิด (ไม่บังคับ)
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/5  ราคาเปิดของพูล TPIX/USDT (ข้ามได้)" Yellow
Say "  ใส่ = สร้างพูลพร้อมราคาเปิดทันที · ไม่ใส่ = deploy สัญญาก่อน เติมพูลทีหลังที่ $siteUrl/liquidity"
Say "  ราคาเปิด = จำนวน USDT ÷ จำนวน TPIX  (เช่น 1000000 กับ 200000 = 0.20 USDT ต่อ TPIX)" DarkGray

$liqTpix = (Read-Host "  จำนวน TPIX ที่จะเติมพูล (Enter = ข้าม)").Trim()
$liqUsdt = ''
if ($liqTpix) { $liqUsdt = (Read-Host "  จำนวน USDT ที่จะเติมพูล").Trim() }
if ($liqTpix -and $liqUsdt) {
    $opening = [math]::Round([double]$liqUsdt / [double]$liqTpix, 6)
    Say "  ราคาเปิดจะเป็น $opening USDT ต่อ 1 TPIX" Cyan
}

# ─────────────────────────────────────────────────────────────────────────────
# 4) ยืนยันแล้ว deploy
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 4/5  ตรวจก่อนส่งจริง" Yellow
Say "  ตรวจว่าเชนรับ bytecode ได้ (อ่านอย่างเดียว ไม่เสียอะไร) ..." DarkGray
node scripts/check-deployable.js 2>&1 | Select-String -Pattern 'WTPIX|USDT_TPIX|TPIXDEXFactory|TPIXDEXRouter02|TPIXDEXPair|ผ่าน ' | ForEach-Object { Say "    $_" DarkGray }

Say ""
Say "  จะ deploy ขึ้นเชน 4289 ของจริง — กระเป๋าที่ใช้จะเป็นเจ้าของสัญญาถาวร" Red
$confirm = Read-Host "  พิมพ์ DEPLOY เพื่อยืนยัน"
if ($confirm -ne 'DEPLOY') { Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow; $plainKey = $null; exit 0 }

$env:DEPLOYER_KEY = $plainKey
$env:TPIX_SITE_URL = $siteUrl
if ($registryToken) { $env:CONTRACT_REGISTRY_TOKEN = $registryToken }
if ($feeCollector) { $env:FEE_COLLECTOR = $feeCollector }
if ($liqTpix -and $liqUsdt) { $env:LIQ_TPIX = $liqTpix; $env:LIQ_USDT = $liqUsdt }

try {
    npx hardhat run scripts/deploy-dex.js --network tpix
    $deployExit = $LASTEXITCODE
} finally {
    # ล้างคีย์ออกจาก environment ของ process นี้เสมอ ไม่ว่าจะสำเร็จหรือล้ม
    $env:DEPLOYER_KEY = $null
    $env:CONTRACT_REGISTRY_TOKEN = $null
    $plainKey = $null
    [GC]::Collect()
}

if ($deployExit -ne 0) { Say "`ndeploy ไม่สำเร็จ — อ่านข้อความด้านบน คีย์ถูกล้างออกจากหน่วยความจำแล้ว" Red; exit 1 }

# ─────────────────────────────────────────────────────────────────────────────
# 5) ตรวจผลจากเว็บจริง
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 5/5  ตรวจว่าเว็บรับรู้แล้ว" Yellow

try {
    $cfg = Invoke-RestMethod -Uri "$siteUrl/api/v1/dex/config" -TimeoutSec 20
    if ($cfg.data.ready) {
        Say "  เว็บพร้อมแล้ว — ROUTER $($cfg.data.ROUTER)" Green
        Say "  รออีก 1 นาที dex:sync จะเปิดเชน 4289 เป็น live และสร้างคู่เทรดจากพูลให้เอง" Green
        Say ""
        Say "  ตรวจซ้ำได้ที่:  ssh $sshHost `"cd $appPath && php artisan tpix:status`"" DarkGray
    } else {
        Say "  เว็บยังไม่พร้อม — ขาด: $($cfg.data.missing -join ', ')" DarkYellow
        Say "  ถ้าลงทะเบียนอัตโนมัติไม่ผ่าน ให้เอาบรรทัด .env ที่สคริปต์พิมพ์ไว้ด้านบนไปใส่แล้วรัน php artisan config:cache" DarkYellow
    }
} catch {
    Say "  ยิงไปที่เว็บไม่สำเร็จ — ตรวจเองด้วย: curl $siteUrl/api/v1/dex/config" DarkYellow
}

Say ""
Say "เสร็จแล้ว" Cyan
