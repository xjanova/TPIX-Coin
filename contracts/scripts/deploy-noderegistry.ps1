# ═══════════════════════════════════════════════════════════════════════════
#  ติดตั้งระบบ Master Node (NodeRegistryV2 + ValidatorKYC) ขึ้นเชนจริง — คำสั่งเดียวจบ
# ═══════════════════════════════════════════════════════════════════════════
#
#   cd D:\Code\TPIX\TPIX-Coin\contracts
#   .\scripts\deploy-noderegistry.ps1
#
# ทำให้ครบในรอบเดียว:
#   1. ถามคีย์กระเป๋าแบบซ่อน (ไม่ขึ้นจอ ไม่เข้า history ไม่ลงไฟล์) แล้วโชว์ที่อยู่ที่จะใช้ deploy
#   2. ดึงโทเคนทะเบียนสัญญาจากเซิร์ฟเวอร์ให้เอง (ssh) — ไม่ต้อง copy ไปมา
#   3. ตรวจว่าเชนรับ bytecode ได้จริง (ด่าน PUSH0) + ขนาด tx ลอดลิมิต 128KB ของ RPC proxy
#   4. deploy ValidatorKYC + NodeRegistryV2 แล้วผูกเข้าหากัน
#   5. ลงทะเบียนที่อยู่กับเว็บ → /masternode, แอป PC 1.14.6 และ TPIX Wallet เห็นเองภายใน ~1 นาที
#   6. ตรวจผลจากเว็บจริง
#
# ⚠️ กระเป๋าที่ใช้ deploy จะเป็น "เจ้าของถาวร" ของทั้งสองสัญญา:
#      • NodeRegistryV2 → หยุดรับสมัครชั่วคราว, ตั้ง uptime, slash (ไม่เกิน % ตอนโหนดนั้นสมัคร),
#                         ตั้งเพดาน APR/เงื่อนไขชั้นสำหรับคนสมัครใหม่
#      • ValidatorKYC   → อนุมัติ/ปฏิเสธ KYC ของชั้น Validator
#    สิทธิ์เหล่านี้ "ถอนเงินต้นหรือเงินในพูลออกไม่ได้" (ไม่มีฟังก์ชันนั้นในสัญญา)
#    แต่ก็ยังควรใช้กระเป๋า deploy เฉพาะที่คุณถือคีย์เองระยะยาว — ห้ามใช้กระเป๋าคลัง
#
# ขั้นถัดไปหลังจบ: เติมพูลรางวัลด้วย .\scripts\fund-reward-pool.ps1 (ห้ามใช้ send-tpix.ps1)
#
# Developed by Xman Studio

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

Say "╔══════════════════════════════════════════════════╗" Cyan
Say "║   ติดตั้งระบบ Master Node ขึ้นเชน 4289 (ปลอดภัย)  ║" Cyan
Say "╚══════════════════════════════════════════════════╝" Cyan
Say ""

if (-not (Test-Path .\hardhat.config.js)) {
    Say "รันจาก D:\Code\TPIX\TPIX-Coin\contracts เท่านั้น" Red
    exit 1
}

$siteUrl = if ($env:TPIX_SITE_URL) { $env:TPIX_SITE_URL.TrimEnd('/') } else { 'https://tpix.online' }
$sshHost = if ($env:TPIX_SSH_HOST) { $env:TPIX_SSH_HOST } else { 'admin@123.253.62.251' }
$appPath = '/home/admin/domains/tpix.online'

# ─────────────────────────────────────────────────────────────────────────────
# 0) เว็บรู้จัก registry ตัวไหนอยู่แล้วหรือยัง — กัน deploy ซ้ำโดยไม่ตั้งใจ
#    deploy ซ้ำ = สร้างสัญญาใหม่อีกตัว คนที่ stake ไว้กับตัวเก่าจะยังอยู่ที่ตัวเก่า
# ─────────────────────────────────────────────────────────────────────────────
try {
    $existing = Invoke-RestMethod -Uri "$siteUrl/api/v1/masternode/config" -TimeoutSec 15
    if ($existing.data.registry_live -and $existing.data.registry_address) {
        Say "เว็บใช้ NodeRegistry ที่ $($existing.data.registry_address) อยู่แล้ว (live)" Yellow
        Say "  deploy ซ้ำจะได้สัญญาใหม่อีกตัว — คนที่ stake กับตัวเดิมจะไม่ย้ายตามมา" Yellow
        $again = Read-Host "  พิมพ์ REDEPLOY ถ้าตั้งใจจะสร้างใหม่จริง ๆ (อย่างอื่น = ยกเลิก)"
        if ($again -ne 'REDEPLOY') { Say "ยกเลิก ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow; exit 0 }
        $env:REGISTRY_FORCE = '1'
    }
} catch {
    Say "  (ถามสถานะจากเว็บไม่ได้ — ไปต่อได้ แต่ตรวจเองว่ายังไม่เคย deploy)" DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# 1) คีย์ — ถามแบบซ่อน
# ─────────────────────────────────────────────────────────────────────────────
Say "ขั้นที่ 1/5  คีย์กระเป๋าที่จะใช้ deploy" Yellow
Say "  กระเป๋านี้จะเป็นเจ้าของ NodeRegistryV2 + ValidatorKYC ถาวร (ดูสิทธิ์ที่หัวไฟล์)"
Say "  ต้องมี TPIX อยู่จริงบนเชนเล็กน้อย (ค่าแก๊สเป็น 0 แต่บัญชีต้องมีตัวตน)"
Say "  ใช้กระเป๋า deploy เฉพาะ — ห้ามใช้กระเป๋าคลัง/กระเป๋า allocation"
Say "  รูปแบบ: เลขฐานสิบหก 64 ตัว (มีหรือไม่มี 0x ก็ได้) · พิมพ์แล้วไม่ขึ้นจอ" DarkGray
Say ""

$secureKey = Read-Host -Prompt "DEPLOYER_KEY" -AsSecureString
if ($secureKey.Length -eq 0) { Say "ยกเลิก (ไม่ได้ใส่คีย์)" Red; exit 1 }

$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
try { $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

# วางคำกู้กระเป๋า (12/24 คำ) ผิดช่องเคยเกิดขึ้นจริง — ปฏิเสธทันที ไม่ใช้ ไม่เก็บ ไม่ส่งต่อ
if (($plainKey.Trim() -split '\s+').Count -ge 12 -and $plainKey -match '^[\sa-zA-Z]+$') {
    Say "นี่คือคำกู้กระเป๋า (12/24 คำ) ไม่ใช่ private key — ไม่ได้ใช้ ไม่ได้เก็บ และไม่ได้ส่งไปไหน" Red
    Say "  ช่องนี้ต้องการ private key ของบัญชีที่จะ deploy:" Red
    Say "  MetaMask → เลือกบัญชี → ⋮ → Account details → Show private key" Red
    $plainKey = $null
    exit 1
}

# MetaMask ส่งออก private key แบบไม่มี 0x และการวางมักติดช่องว่าง/ขึ้นบรรทัด/เครื่องหมายคำพูดมาด้วย
$plainKey = ($plainKey -replace '[\s"''`]', '')
if ($plainKey -match '^[0-9a-fA-F]{64}$') { $plainKey = "0x$plainKey" }

if ($plainKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    # บอกแค่ความยาว ไม่สะท้อนเนื้อคีย์กลับขึ้นจอ
    Say "รูปแบบคีย์ไม่ถูกต้อง — ได้รับ $($plainKey.Length) ตัวอักษร" Red
    Say "  ต้องเป็นเลขฐานสิบหก 64 ตัว — ลองคัดลอกจาก MetaMask ใหม่อีกครั้ง" Red
    $plainKey = $null
    exit 1
}

# แปลงคีย์เป็นที่อยู่ให้เห็นก่อนยืนยัน — กันวางคีย์ของกระเป๋าผิดใบ
$env:DEPLOYER_KEY = $plainKey
try {
    $deployerAddress = (node -e "const { Wallet } = require('ethers'); console.log(new Wallet(process.env.DEPLOYER_KEY).address)" 2>$null | Select-Object -First 1)
} finally {
    $env:DEPLOYER_KEY = $null
}
if (-not $deployerAddress) {
    Say "แปลงคีย์เป็นที่อยู่ไม่ได้ — คีย์นี้ใช้ไม่ได้" Red
    $plainKey = $null
    exit 1
}
Say "  กระเป๋าที่จะใช้ deploy (และเป็นเจ้าของสัญญา): $deployerAddress" Cyan
Say "  ตรวจว่าตรงกับกระเป๋า deploy ของคุณก่อนไปต่อ" DarkGray

# ─────────────────────────────────────────────────────────────────────────────
# 2) โทเคนทะเบียนสัญญา — ดึงให้เอง
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 2/5  ดึงโทเคนทะเบียนสัญญาจากเซิร์ฟเวอร์" Yellow
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
    Say "  ดึงโทเคนไม่ได้ — สคริปต์จะ deploy ต่อ แล้วพิมพ์บรรทัด .env ไว้ให้ใส่เอง" DarkYellow
}

# ─────────────────────────────────────────────────────────────────────────────
# 3) ชั้น Validator ต้องมีสัญญา KYC — ค่าปริยายคือ deploy ด้วย
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 3/5  ValidatorKYC (ด่าน KYC ของชั้น Validator 10M TPIX)" Yellow
$kycAnswer = (Read-Host "  deploy ValidatorKYC ด้วยไหม? [Y/n]").Trim()
$deployKyc = -not ($kycAnswer -match '^[nN]')
Say ("  " + ($(if ($deployKyc) { 'deploy ด้วย — ชั้น Validator เปิดได้หลังทีมอนุมัติ KYC' } else { 'ข้าม — ชั้น Validator จะสมัครไม่ได้จนกว่าจะ setKYCContract()' }))) DarkGray

# ─────────────────────────────────────────────────────────────────────────────
# 4) ตรวจแล้ว deploy
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 4/5  ตรวจก่อนส่งจริง" Yellow
Say "  คอมไพล์ (evm london) ..." DarkGray
npx hardhat compile 2>&1 | Select-Object -Last 1 | ForEach-Object { Say "    $_" DarkGray }
Say "  ถามเชนว่ารับ bytecode ได้ไหม (อ่านอย่างเดียว ไม่เสียอะไร) ..." DarkGray
node scripts/check-deployable.js 2>&1 | Select-String -Pattern 'NodeRegistryV2|ValidatorKYC' | ForEach-Object { Say "    $_" DarkGray }

Say ""
Say "  จะ deploy ขึ้นเชน 4289 ของจริงจาก $deployerAddress" Red
$confirm = Read-Host "  พิมพ์ DEPLOY เพื่อยืนยัน"
if ($confirm -ne 'DEPLOY') { Say "ยกเลิกแล้ว ไม่มีอะไรถูกส่งขึ้นเชน" DarkYellow; $plainKey = $null; exit 0 }

$env:DEPLOYER_KEY = $plainKey
$env:TPIX_SITE_URL = $siteUrl
if ($registryToken) { $env:CONTRACT_REGISTRY_TOKEN = $registryToken }
if ($deployKyc) { $env:DEPLOY_KYC = '1' } else { $env:DEPLOY_KYC = $null }

try {
    npx hardhat run scripts/deploy-noderegistry.js --network tpix
    $deployExit = $LASTEXITCODE
} finally {
    # ล้างคีย์/โทเคนออกจาก environment ของ process นี้เสมอ ไม่ว่าจะสำเร็จหรือล้ม
    $env:DEPLOYER_KEY = $null
    $env:CONTRACT_REGISTRY_TOKEN = $null
    $env:REGISTRY_FORCE = $null
    $env:DEPLOY_KYC = $null
    $plainKey = $null
    $registryToken = $null
    [GC]::Collect()
}

if ($deployExit -ne 0) { Say "`ndeploy ไม่สำเร็จ — อ่านข้อความด้านบน คีย์ถูกล้างออกจากหน่วยความจำแล้ว" Red; exit 1 }

# ─────────────────────────────────────────────────────────────────────────────
# 5) ตรวจผลจากเว็บจริง (เว็บ cache สถานะ ~30 วินาที–5 นาที)
# ─────────────────────────────────────────────────────────────────────────────
Say ""
Say "ขั้นที่ 5/5  ตรวจว่าเว็บรับรู้แล้ว" Yellow
# ต้องเทียบกับที่อยู่ที่เพิ่ง deploy — ตอน redeploy ตัวเก่ายัง live อยู่ ถ้าดูแค่ registry_live
# จะขึ้นว่า "พร้อมแล้ว" ทั้งที่เว็บยังชี้ตัวเก่า (ลงทะเบียนผ่าน ssh ล้มเงียบ ๆ ได้)
$newRegistry = ((Get-Content .\deployed-contracts.json -Raw | ConvertFrom-Json).contracts |
    Where-Object { $_.name -eq 'NodeRegistryV2' } | Select-Object -First 1).address
Say "  NodeRegistryV2 ที่เพิ่ง deploy: $newRegistry" Cyan
$ok = $false
for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
    try {
        $cfg = Invoke-RestMethod -Uri "$siteUrl/api/v1/masternode/config" -TimeoutSec 20
        $siteRegistry = [string]$cfg.data.registry_address
        if ($cfg.data.registry_live -and $newRegistry -and $siteRegistry.ToLower() -eq $newRegistry.ToLower()) {
            $ok = $true
            Say "  เว็บพร้อมแล้ว — NodeRegistry $siteRegistry" Green
            if ($cfg.data.kyc_contract) { Say "  ValidatorKYC $($cfg.data.kyc_contract)" Green }
        } else {
            Say "  เว็บยังชี้ $siteRegistry (รอบ $($i + 1)/10) — รอ 30 วินาที ..." DarkGray
            Start-Sleep -Seconds 30
        }
    } catch {
        Say "  ถามเว็บไม่สำเร็จ (รอบ $($i + 1)/10) — รอ 30 วินาที ..." DarkGray
        Start-Sleep -Seconds 30
    }
}
if (-not $ok) {
    Say "  เว็บยังไม่ชี้สัญญาใหม่ — ลงทะเบียนอัตโนมัติไม่ผ่าน (มักเป็น ssh ดึงโทเคนไม่ได้)" DarkYellow
    Say "  ⚠️ แก้ .env ไม่ช่วย: ที่อยู่ในทะเบียนสัญญาบนเว็บชนะ .env เสมอ" DarkYellow
    Say "  ส่งที่อยู่ NodeRegistryV2 + ValidatorKYC ข้างบนให้ Claude ลงทะเบียนจากฝั่งเซิร์ฟเวอร์ (POST /api/infra/contracts, force)" DarkYellow
}

Say ""
Say "เสร็จขั้น deploy — ขั้นต่อไป: เติมพูลรางวัลจากกระเป๋า masternode-rewards" Cyan
Say "  .\scripts\fund-reward-pool.ps1 -Amount 20000000" Cyan
Say "  (commit deployed-contracts.json ที่ถูกอัปเดตด้วย)" DarkGray
