# เครื่องแม่ VM — WIN-8083NJGR9TE (123.253.62.250)

Windows Server 2019 + VMware Workstation รัน VM ทั้งหมดของ production:

| VM | IP | หน้าที่ |
|---|---|---|
| prod | 123.253.62.251 | tpix.online (ThaiXTrade), thaiprompt |
| เชน | 123.253.62.252 | validator 4 ตัว + Blockscout + nginx RPC |

เครื่องแม่ล่ม = ทุกอย่างล่มพร้อมกัน รวมหลังบ้านที่ควรร้องเตือนด้วย จึงต้องกันต้นเหตุที่เครื่องแม่เอง

## เหตุที่เคยเกิด (2026-09-26)

- **02:18–12:57** D: เต็ม → Workstation พัก VM ทุกตัว ค้างที่หน้าต่าง "disk full: Retry/Cancel" 10 ชม.
- **21:49** Windows Update รีสตาร์ทเครื่องแม่เอง ปิดตัวค้าง 40 นาทีจนต้องกดรีเซ็ต → VM ดับกะทันหัน
  → validator ทำบล็อกท้ายๆ หาย (ยังไม่ได้ flush ลงดิสก์) แล้วออกบล็อกใหม่ทับ → validator-3 แยกเชน
  ต้อง clone ข้อมูลจาก validator ตัวอื่นกู้ (เชนหยุดระหว่างกู้ 114 วินาที)

## สิ่งที่ตั้งไว้

### Windows Update ไม่รีสตาร์ทเอง
`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`

| ค่า | ความหมาย |
|---|---|
| `AUOptions = 7` | ดาวน์โหลดเอง · แจ้งให้ติดตั้ง · **แจ้งให้รีสตาร์ท** (Server 2016 ขึ้นไป) |
| `NoAutoUpdate = 0` | ยังตรวจหาอัปเดตตามปกติ |
| `NoAutoRebootWithLoggedOnUsers = 1` | ชั้นสอง — มีคนล็อกอินค้างอยู่ห้ามรีสตาร์ท |

ค่าเดิมคือ `AUOptions = 3` ซึ่งกันแค่ "การติดตั้ง" — พอมีอะไรติดตั้งไปแล้ว Windows ยังนัดรีสตาร์ทเอง
นอก active hours (08–17) ได้อยู่ นั่นคือที่เกิดตอน 21:49
สำรองค่าเดิม: `C:\ProgramData\TPIX\backup\wu-policy-20260927-010201.reg`

### เฝ้าพื้นที่ดิสก์
`host-diskwatch.ps1` → Task Scheduler `\TPIX\TPIX Host Disk Watch` (SYSTEM ทุก 30 นาที)
ขึ้นคาดแดงหลังบ้าน tpix.online เป็น node `vmhost-250` เมื่อ D: < 60/30 GB หรือ C: < 15/8 GB (warning/critical)
log อยู่ที่ `C:\ProgramData\TPIX\host-diskwatch.log` · ส่งไม่ถึงก็ลง Event Log (Application, source `TPIX-DiskWatch`)

ดิสก์ของ VM ไม่รองรับ TRIM (`DISC-MAX 0B`) — ลบไฟล์ใน VM แล้วไฟล์ .vmdk ไม่หดตาม ต้องย่อเอง
(zero-fill ในเครื่อง VM แล้ว `vmware-toolbox-cmd disk shrinkonly`) — ระหว่างย่อ VM จะค้าง วางแผนช่วงคนน้อย

## ขั้นตอนบำรุงรักษาเครื่องแม่ (อัปเดต Windows / รีบูต)

1. **ปิด VM ด้วย Shut Down Guest ทีละตัว ห้าม Power Off** — ปิดกะทันหันคือบล็อกหายและเชนแยก
   เคยเจอ: สั่งปิดตัวเดียวแล้วอีกสองตัวดับตามไปด้วย ตรวจทั้งสามตัวทุกครั้งหลังสั่งเปิด/ปิดใน Workstation
2. ติดตั้งอัปเดต แล้วรีบูต
3. เปิด VM แล้วตรวจเชนว่า validator ทั้ง 4 ตัวอยู่ความสูงเดียวกันและเดินต่อ:
   ```bash
   for p in 8545 8546 8547 8548; do
     curl -s -X POST -H 'content-type: application/json' \
       --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:$p
     echo
   done
   ```
   ตัวไหนค้างอยู่ที่เดิมทั้งที่ตัวอื่นเดิน = แยกเชน — restart ทั้งวงไม่ช่วย ต้อง clone ข้อมูลจากตัวที่ดี
   (ดูโน้ต 2026-09-26 ในสมอง: หยุดตัวที่เสีย + ตัวต้นทาง → คัด `blockchain`, `trie`,
   `consensus/{metadata,snapshots}` โดยเก็บคีย์ของตัวที่เสียไว้ → เปิดตัวต้นทางก่อน แล้วค่อยเปิดตัวที่เสีย)
