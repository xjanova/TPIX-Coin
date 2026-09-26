# ============================================================
# TPIX — เฝ้าพื้นที่ดิสก์เครื่องแม่ VMware Workstation
#        (WIN-8083NJGR9TE · 123.253.62.250 · VM: prod .251 + เชน .252)
#
# ทำไมต้องมี: 2026-09-26 02:18 ไดรฟ์ D: เต็ม → Workstation พัก VM ทุกตัวไว้ที่หน้าต่าง
# "disk full: Retry/Cancel" 10 ชั่วโมงโดยไม่มีใครรู้ — หลังบ้านที่ควรร้องเตือนก็อยู่ใน VM
# ที่ถูกพักด้วย และดิสก์ VM ไม่มี TRIM (DISC-MAX 0B) ไฟล์ .vmdk จึงโตอย่างเดียว ไม่หดเอง
# สคริปต์นี้ขึ้นคาดแดงหลังบ้าน tpix.online ตั้งแต่ยังเหลือที่ให้จัดการ ไม่ใช่ตอนทุกเว็บ 522 แล้ว
#
# ติดตั้ง (Administrator):
#   - ไฟล์นี้ต้องเป็น UTF-8 มี BOM — PowerShell 5.1 อ่านไฟล์ไม่มี BOM เป็น ANSI ข้อความไทยจะเพี้ยน
#   - วางที่ C:\ProgramData\TPIX\host-diskwatch.ps1 (โฟลเดอร์ให้สิทธิ์แค่ SYSTEM + Administrators)
#   - alert-url.txt = ปลายทางเดียวกับ TPIX_ALERT_URL ใน /etc/tpix-watchdog.env ของเครื่องเชน
#   - alert-token.bin = token เดียวกับ TPIX_ALERT_TOKEN เข้ารหัส DPAPI (LocalMachine)
#     ห้ามคัด token ผ่านแชต/clipboard — ส่งแบบเข้ารหัสด้วยกุญแจ RSA ที่สร้างบนเครื่องนี้
#   - Task Scheduler "\TPIX\TPIX Host Disk Watch" รันด้วย SYSTEM ทุก 30 นาที
#
# Developed by Xman Studio
# ============================================================

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$Dir  = 'C:\ProgramData\TPIX'
$Node = 'vmhost-250'
$Log  = Join-Path $Dir 'host-diskwatch.log'

# เกณฑ์เป็น GB ที่ยังว่าง
# D: เก็บดิสก์ VM หลัก — ไฟล์ .vmdk โตวันละหลาย GB ตอนเชน/ฐานข้อมูลเขียน
# C: เก็บ Windows + ไฟล์แรม .vmem ของ prod (C:\VM-work) — เต็มแล้วอัปเดตและ VM พังพร้อมกัน
$Rules = @(
    @{ Drive = 'D'; Warn = 60; Crit = 30 },
    @{ Drive = 'C'; Warn = 15; Crit = 8 }
)

function Write-Log([string]$Message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message
    Add-Content -Path $Log -Value $line -Encoding UTF8
}

# ห้ามพิมพ์ token ลง log หรือหน้าจอ — ถอดรหัสใช้แล้วทิ้งในฟังก์ชันนี้เท่านั้น
function Send-Alert([string]$Key, [string]$Severity, [string]$Message) {
    $url   = (Get-Content (Join-Path $Dir 'alert-url.txt') -Raw).Trim()
    $token = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect(
        [IO.File]::ReadAllBytes((Join-Path $Dir 'alert-token.bin')), $null, 'LocalMachine'))
    $body = @{ node = $Node; key = $Key; severity = $Severity; message = $Message } | ConvertTo-Json -Compress
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Method Post -Uri "$url/alert" -TimeoutSec 20 `
        -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' } `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
        -UserAgent "tpix-diskwatch/1.0 ($Node)" | Out-Null
}

# log เกิน 1MB ตัดเหลือส่วนท้าย — ตัวเฝ้าดิสก์ต้องไม่กลายเป็นตัวถมดิสก์เสียเอง
if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 1MB) {
    Get-Content $Log -Tail 2000 | Set-Content $Log -Encoding UTF8
}

foreach ($r in $Rules) {
    $drive = Get-PSDrive -Name $r.Drive -PSProvider FileSystem -ErrorAction SilentlyContinue
    if (-not $drive) { continue }
    $free = [math]::Round($drive.Free / 1GB, 1)

    if ($free -lt $r.Crit)     { $severity = 'critical'; $limit = $r.Crit }
    elseif ($free -lt $r.Warn) { $severity = 'warning';  $limit = $r.Warn }
    else { Write-Log "OK $($r.Drive): ว่าง $free GB"; continue }

    $message = "ดิสก์ $($r.Drive): ของเครื่องแม่ VM (.250) เหลือ $free GB (ต่ำกว่า $limit GB) — " +
        "ถ้าเต็ม VMware จะพัก VM ทุกตัว (prod + เชน) ทันที · ลบ/ย้ายไฟล์ หรือย่อดิสก์ VM " +
        "(zero-fill + vmware-toolbox-cmd disk shrinkonly)"
    try {
        Send-Alert -Key ('host_disk_low_' + $r.Drive.ToLower()) -Severity $severity -Message $message
        Write-Log "ALERT $severity $($r.Drive): ว่าง $free GB"
    } catch {
        # ส่งไม่ถึงก็ต้องเหลือร่องรอยให้เห็นจาก Event Viewer แม้ไม่มีใครเปิดไฟล์ log
        Write-Log "SEND FAILED $($r.Drive): ว่าง $free GB — $($_.Exception.Message)"
        try { Write-EventLog -LogName Application -Source 'TPIX-DiskWatch' -EventId 1001 -EntryType Warning -Message $message } catch {}
    }
}
