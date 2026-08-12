# ภาพประกอบในแอป — ทำซ้ำยังไง

ภาพทุกใบใน `src/art/` **เจนขึ้นเอง ไม่ได้ซื้อ ไม่ได้ hotlink จากที่ไหน**
ต้นทุน **0 เครดิต** (ยืนยันด้วยยอดคงเหลือก่อน/หลัง: 49,355 → 49,355 หลังเจน 8 ใบ)

## ทำไมถึงฟรี

บัญชี Magnific เป็น Premium+ ที่มี unlimited — แต่ **unlimited ผูกกับเว็บแอป ไม่ใช่ API**
connector จะรายงานตรง ๆ ว่า `unlimitedAppliesHere: false` แปลว่า**ยิงผ่าน API เสียเครดิต**
ส่วนปุ่มในเว็บเขียนว่า `Generate Unlimited` = ฟรี

ดังนั้นวิธีที่ใช้คือ **ส่งงานผ่านเบราว์เซอร์ (ฟรี) แล้วดึงไฟล์ผ่าน read API (ฟรีเช่นกัน)**
ตัวที่กำหนดราคาคือ *ช่องทาง* ไม่ใช่โมเดล

## ขั้นตอน

1. เปิด `https://www.magnific.com/app/ai-image-generator` ใน Chrome ที่ล็อกอินไว้แล้ว
   (หน้า `/ai/image-generator` เป็นหน้าขาย ไม่ใช่ editor)
2. ช่องพรอมป์เป็น `div[contenteditable="true"]` — เซ็ต `.value` ไม่ติด
   ต้อง `focus()` → `execCommand('selectAll')` → `execCommand('insertText', false, prompt)`
3. **ด่านตรวจว่ากรอกติดจริง**: ปุ่ม `[data-cy="generate-button"]` ต้องพลิกจาก
   `disabled:true` เป็น `false` และป้ายเปลี่ยนจาก `Generate` เป็น `Generate Unlimited`
   (ป้ายนี้มาช้าได้เกิน 2 วินาที ต้องวนรอ ไม่ใช่เช็คครั้งเดียว)
4. **การ์ดกันจ่ายเงิน** — ถ้าป้ายปุ่มมีตัวเลขแปลว่ากำลังจะคิดเครดิต ให้หยุดทันที:
   ```js
   if (/\d/.test(btn.innerText)) throw new Error('ABORT: cost shown -> ' + btn.innerText);
   ```
5. สัดส่วนภาพ: `[data-cy="image-aspect-ratio-input"]` → เลือก `[data-cy="popover-option-16:9"]`
   ค่าที่ตั้งไว้**คงอยู่ข้ามการเจน** ตั้งครั้งเดียวใช้ได้ทั้งชุด
6. ดึงผลผ่าน read API: `creations_search` → `creations_wait` → `curl` URL ที่ได้
   **ค้นด้วยข้อความในพรอมป์ ห้ามหยิบใบล่าสุด** — ประวัติเป็นของทั้งบัญชี
   อาจมีงานของ session อื่นแทรกเข้ามา (จึงตั้งชื่อพรอมป์ขึ้นต้นด้วย `TPIX-` ไว้)

## กับดักที่เจอจริงตอนทำ

| อาการ | สาเหตุจริง |
|---|---|
| ยัด ≥4 งานต่อ 1 คำสั่ง แล้ว error timeout | CDP `Runtime.evaluate` ตายที่ 45 วินาที **แต่งานส่งไปแล้ว** — อย่ายิงซ้ำ ให้ไปเช็ค `creations_search` ก่อน |
| หน่วงเวลาคงที่ระหว่างงาน แล้วงานหาย | คิวเต็มปุ่มจะ disabled ชั่วคราว ต้องวน `while (btn.disabled)` รอ ไม่ใช่ `sleep()` |
| ภาพขึ้น 0×0 ในพรีวิว ทั้งที่ HTTP 200 | `dev-server.js` ไม่รู้จัก `.webp` เลยอ่านแบบ utf-8 → ไฟล์บวมจาก 43,466 เป็น 78,650 ไบต์ **แก้แล้ว** (กลับด้านตรรกะเป็น "ระบุเฉพาะไฟล์ข้อความ") |
| `convert` บน Windows | เป็นตัวแปลง FAT→NTFS ของ Windows **ไม่ใช่ ImageMagick** — ใช้ `ffmpeg` แทน |

## แปลงไฟล์

```bash
# การ์ดระดับโหนด (ต้นฉบับ 2048×2048)
ffmpeg -y -i in.png -vf "scale=640:640"  -c:v libwebp -quality 82 -compression_level 6 out.webp
# ภาพหัวหน้า (ต้นฉบับ 2752×1536)
ffmpeg -y -i in.png -vf "scale=1600:-2" -c:v libwebp -quality 80 -compression_level 6 out.webp
```

ดิบ 36 MB → **299 KB** (ย่อ ~124 เท่า) · **ลบ PNG ดิบทิ้งได้** เจนใหม่ฟรีอยู่แล้ว ไม่ต้องถ่วง repo

## ภาพที่มีตอนนี้

| ไฟล์ | ใช้ที่ไหน | สัดส่วน |
|---|---|---|
| `tier-light.webp` · `tier-sentinel.webp` · `tier-guardian.webp` · `tier-validator.webp` | แถบหัวการ์ดเลือกระดับโหนด (หน้าตั้งค่าโหนด) | 1:1 640px |
| `hero-setup.webp` | แบนเนอร์หัวหน้าตั้งค่าโหนด | 16:9 1600px |
| `hero-dashboard.webp` | พื้นหลังจาง ๆ ของแดชบอร์ด (`.page-art`, opacity .20) | 16:9 1600px |
| `hero-about.webp` | แบนเนอร์หัวหน้าเกี่ยวกับ | 16:9 1600px |
| `empty-wallet.webp` | ภาพประกอบตอนยังไม่มีกระเป๋า | 16:9 1600px |

โทนคุมให้ตรง design system: กรมท่าเกือบดำ `#030712` + นีออน cyan `#06b6d4` / violet `#a855f7`
พรอมป์ทุกใบปิดท้ายด้วย `no text, no letters, no words, no people` — ตัวอักษรที่ AI เจนออกมาใช้ไม่ได้

## กฎ CSS ที่ห้ามลืม

ภาพพื้นหลังเป็น `position: absolute` → **เนื้อหาต้องลอยเหนือมัน** ไม่งั้นกดปุ่มไม่ได้
ปิดช่องนี้ทั้งหน้าไว้ด้วยกฎเดียวใน `styles.css`:

```css
.page > *:not(.page-art) { position: relative; z-index: 1; }
```

ตรวจว่ายังไม่ทับกันด้วย `document.elementFromPoint()` ที่กลางปุ่ม
(ต้อง `scrollIntoView({behavior:'instant'})` ก่อน ไม่งั้นได้ `null` เพราะอยู่นอกจอ)
