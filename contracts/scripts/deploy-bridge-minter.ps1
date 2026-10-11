# ═══════════════════════════════════════════════════════════════════════════
#  ติดตั้ง TPIXBridgeMinter (ด่านจำกัดการ mint ของสะพาน USDT) ขึ้นเชน 4289
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-bridge-minter.ps1
#
# ทำให้ครบในรอบเดียว:
#   1. ถามคีย์กระเป๋าเจ้าของแบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์)
#   2. ตรวจว่ากระเป๋านี้เป็นเจ้าของ USDT_TPIX (อ่านจากเชนอย่างเดียว)
#   3. ถามเพดานต่อครั้ง/ต่อวัน + ที่อยู่ relayer/guardian ของเซิร์ฟเวอร์
#   4. deploy TPIXBridgeMinter แล้วทำขั้นตอนของเจ้าของให้ (setBridge / setRelayer / setGuardian)
#   5. ลงทะเบียนที่อยู่กับเว็บให้เอง แล้วตรวจผลจากเว็บจริง
#
# ⚠️ กระเป๋าที่ใช้ deploy จะเป็น "เจ้าของถาวร" ของ minter (ตั้งเพดาน · เพิ่ม/ถอน relayer · ปลด pause)
#    ใช้กระเป๋าเดียวกับที่เป็นเจ้าของ USDT_TPIX ไม่งั้นสคริปต์ setBridge ให้ไม่ได้
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   ติดตั้งด่าน mint ของสะพาน USDT (TPIX Chain)     ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) {
    Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red
    exit 1
}

$usdtTpix = if ($env:USDT_TPIX_ADDRESS) { $env:USDT_TPIX_ADDRESS } else { '0x0A4Ee87551eF041f3EecFBBfdcfFC1B46a4878f1' }
$rpcUrl = if ($env:TPIX_RPC_URL) { $env:TPIX_RPC_URL } else { 'https://rpc1.tpix.online' }

# ─────────────────────────────────────────────────────────────────────────────
# 1) คีย์ — ถามแบบซ่อน
# ─────────────────────────────────────────────────────────────────────────────
Say "ขั้นที่ 1/5  คีย์กระเป๋าเจ้าของ" Yellow
Say "  ต้องเป็นกระเป๋าเดียวกับเจ้าของ USDT_TPIX ($usdtTpix)"
Say "  รูปแบบ: เลขฐานสิบหก 64 ตัว (มีหรือไม่มี 0x ก็ได้ — คัดลอกจาก MetaMask ได้เลย) · พิมพ์แล้วไม่ขึ้นจอ" DarkGray
Say ""

$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

# วางคำกู้กระเป๋า (12/24 คำ) ผิดช่องเกิดขึ้นจริงแล้ว — ไม่ใช้ ไม่เก็บ ไม่ส่งไปไหน แล้วบอกว่าช่องนี้ต้องการอะไร
if (($plainKey.Trim() -split '\s+').Count -ge 12 -and $plainKey -match '^[\sa-zA-Z]+$') {
    Say "นี่คือคำกู้กระเป๋า (12/24 คำ) ไม่ใช่ private key — ไม่ได้ใช้ ไม่ได้เก็บ และไม่ได้ส่งไปไหน" Red
    Say "  ช่องนี้ต้องการ private key ของบัญชีเจ้าของ:" Red
    Say "  MetaMask → เลือกบัญชี → ⋮ → Account details → Show private key" Red
    $plainKey = $null
    exit 1
}

# MetaMask ส่งออกคีย์แบบไม่มี 0x และการวางมักติดช่องว่าง/ขึ้นบรรทัด/เครื่องหมายคำพูดมาด้วย
$plainKey = ($plainKey -replace '[\s"''`]', '')
if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }

if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    # บอกแค่ความยาว ไม่สะท้อนเนื้อคีย์กลับขึ้นจอ
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
Say "  กระเป๋าที่จะใช้: $deployerAddress" Cyan

# ─────────────────────────────────────────────────────────────────────────────
# 2) ตรวจความเป็นเจ้าของจากเชน (อ่านอย่างเดียว)
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/5  ตรวจกับเชนจริง (อ่านอย่างเดียว)" Yellow

$headers = @{ 'User-Agent' = 'TPIX-deploy/1.0'; 'Content-Type' = 'application/json' }
$ownerCall = '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"to":"' + $usdtTpix + '","data":"0x8da5cb5b"},"latest"]}'
$usdtOwner = $null
try {
    $res = Invoke-RestMethod -Uri $rpcUrl -Method Post -Headers $headers -Body $ownerCall -TimeoutSec 20
    if ($res.result -and $res.result.Length -ge 66) { $usdtOwner = '0x' + $res.result.Substring(26) }
} catch { $usdtOwner = $null }

$isOwner = $usdtOwner -and ($usdtOwner.ToLower() -eq $deployerAddress.ToLower())
if ($isOwner) {
    Say "  เป็นเจ้าของ USDT_TPIX ✓ — สคริปต์ทำขั้น setBridge ให้ได้" Green
} elseif ($usdtOwner) {
    Say "  เจ้าของ USDT_TPIX คือ $usdtOwner ไม่ใช่กระเป๋านี้" DarkYellow
    Say "  deploy ต่อได้ แต่ setBridge ต้องให้เจ้าของตัวจริงทำเองทีหลัง" DarkYellow
} else {
    Say "  อ่านเจ้าของ USDT_TPIX จากเชนไม่ได้ — จะลองต่อ สคริปต์ deploy ตรวจซ้ำอีกรอบ" DarkYellow
}

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
if ($registryToken) { Say "  โทเคนทะเบียนสัญญา: ได้แล้ว ($($registryToken.Length) ตัวอักษร)" Green }
else { Say "  ดึงโทเคนไม่ได้ — deploy ต่อได้ สคริปต์จะพิมพ์บรรทัด .env ไว้ให้" DarkYellow }

# ─────────────────────────────────────────────────────────────────────────────
# 3) เพดาน + บทบาท
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/5  เพดานและบทบาท" Yellow
Say "  เพดานคือความเสียหายสูงสุดถ้าคีย์ relayer บนเซิร์ฟเวอร์หลุด — ตั้งต่ำไว้ก่อน เพิ่มทีหลังได้" DarkGray

$maxPerTx = (Read-Host "  เพดานต่อครั้ง USDT (Enter = 1000)").Trim()
if (-not $maxPerTx) { $maxPerTx = '1000' }
$dailyCap = (Read-Host "  เพดานต่อวัน USDT (Enter = 5000)").Trim()
if (-not $dailyCap) { $dailyCap = '5000' }
if ($maxPerTx -notmatch '^\d+(\.\d{1,6})?$' -or $dailyCap -notmatch '^\d+(\.\d{1,6})?$' -or [decimal]$maxPerTx -le 0 -or [decimal]$maxPerTx -gt [decimal]$dailyCap) {
    Say "เพดานไม่ถูกต้อง — ต้องเป็นตัวเลขมากกว่าศูนย์ และต่อครั้งต้องไม่เกินต่อวัน" Red
    $plainKey = $null
    exit 1
}

Say "  ที่อยู่ relayer / guardian ดูได้ที่ $siteUrl/admin/bridge (อ่านจากไฟล์ keystore บนเซิร์ฟเวอร์)" DarkGray
$relayer = (Read-Host "  ที่อยู่ relayer (Enter = ข้าม ตั้งทีหลัง)").Trim()
$guardian = (Read-Host "  ที่อยู่ guardian (Enter = ข้าม)").Trim()
foreach ($a in @($relayer, $guardian)) {
    if ($a -and $a -notmatch '^0x[0-9a-fA-F]{40}$') { Say "ที่อยู่ไม่ถูกรูปแบบ: $a" Red; $plainKey = $null; exit 1 }
}
if ($relayer -and $guardian -and $relayer.ToLower() -eq $guardian.ToLower()) {
    Say "relayer กับ guardian ต้องเป็นคนละกระเป๋า — คีย์เดียวหลุดแล้วทั้ง mint และสั่งหยุดได้ไม่ควรอยู่ด้วยกัน" Red
    $plainKey = $null
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 4) ยืนยันแล้ว deploy
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 4/5  สรุปก่อนส่งจริง" Yellow
Say "  เจ้าของ minter : $deployerAddress"
Say "  เหรียญ          : $usdtTpix"
Say "  เพดาน          : $maxPerTx USDT/ครั้ง · $dailyCap USDT/วัน"
Say "  relayer        : $(if ($relayer) { $relayer } else { '(ตั้งทีหลัง)' })"
Say "  guardian       : $(if ($guardian) { $guardian } else { '(ตั้งทีหลัง)' })"
Say ""
Say "  หลังจากนี้ minter จะเป็นทางเดียวที่ mint USDT_TPIX ได้" Red
$confirm = Read-Host "  พิมพ์ DEPLOY เพื่อยืนยัน"
if ($confirm -ne 'DEPLOY') { Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow; $plainKey = $null; exit 0 }

$env:DEPLOYER_KEY = $plainKey
$env:TPIX_SITE_URL = $siteUrl
$env:USDT_TPIX_ADDRESS = $usdtTpix
$env:BRIDGE_MAX_PER_TX = $maxPerTx
$env:BRIDGE_DAILY_CAP = $dailyCap
$env:APPLY_OWNER_STEPS = if ($isOwner) { '1' } else { '' }
if ($relayer) { $env:RELAYER_ADDRESS = $relayer }
if ($guardian) { $env:GUARDIAN_ADDRESS = $guardian }
if ($registryToken) { $env:CONTRACT_REGISTRY_TOKEN = $registryToken }

try {
    npx hardhat run scripts/deploy-bridge-minter.js --network tpix
    $deployExit = $LASTEXITCODE
} finally {
    # ล้างคีย์ออกจาก environment ของ process นี้เสมอ ไม่ว่าจะสำเร็จหรือล้ม
    $env:DEPLOYER_KEY = $null
    $env:CONTRACT_REGISTRY_TOKEN = $null
    $env:APPLY_OWNER_STEPS = $null
    $env:RELAYER_ADDRESS = $null
    $env:GUARDIAN_ADDRESS = $null
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
    $info = Invoke-RestMethod -Uri "$siteUrl/api/v1/bridge/info" -Headers @{ 'User-Agent' = 'TPIX-deploy/1.0' } -TimeoutSec 20
    if ($info.data.minter_address) {
        Say "  เว็บเห็น minter แล้ว: $($info.data.minter_address)" Green
        Say "  ขั้นต่อไปที่หน้า $siteUrl/admin/bridge — ตรวจรายการความพร้อมให้เขียวครบก่อนเปิดสวิตช์" Green
    } else {
        Say "  เว็บยังไม่เห็น minter — เอาบรรทัด .env ที่สคริปต์พิมพ์ไว้ด้านบนไปใส่ แล้วรัน php artisan config:cache" DarkYellow
    }
} catch {
    Say "  ยิงไปที่เว็บไม่สำเร็จ — ตรวจเองด้วย: curl $siteUrl/api/v1/bridge/info" DarkYellow
}

Say ""
Say "เสร็จแล้ว" Cyan
