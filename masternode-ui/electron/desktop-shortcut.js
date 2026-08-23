/**
 * TPIX Master Node — ตัวดูแลช็อตคัตบนเดสก์ท็อป
 *
 * ทำไมต้องมีไฟล์นี้:
 * ตัวติดตั้ง NSIS สร้างไอคอนให้เฉพาะ "ตอนติดตั้งครั้งแรก" เท่านั้น พอเป็นการติดตั้งทับ
 * มันจะเข้าโหมด keepShortcuts=true แล้วข้ามการสร้างไอคอนทั้งดุ้น (installer.nsh:196-226)
 * และถึงจะตั้ง createDesktopShortcut:"always" แล้ว ก็ยังมี ${ifNot} ${isUpdated} คร่อมอยู่
 * แปลว่าสายอัปเดตอัตโนมัติ (autoInstallOnAppQuit) ไม่มีวันสร้างไอคอนคืนให้เลย
 *
 * ไฟล์นี้จึงเป็นด่านสุดท้าย — เช็กทุกครั้งที่เปิดโปรแกรม ถ้าไอคอนหายก็สร้างคืนให้เอง
 * ห้ามโยน error ออกไปเด็ดขาด ไอคอนหายไม่ใช่เหตุผลที่จะทำให้แอปเปิดไม่ขึ้น
 */

const { app, shell } = require('electron');
const fs = require('fs');
const path = require('path');

// ต้องตรงกับ build.productName ใน package.json เป๊ะๆ ไม่งั้นจะได้ไอคอนซ้ำ 2 อัน
// (NSIS ตั้งชื่อไฟล์เป็น "$DESKTOP\${SHORTCUT_NAME}.lnk" ซึ่งมาจาก productName)
const SHORTCUT_NAME = 'TPIX Master Node';

// ต้องตรงกับ build.appId — ใช้จัดกลุ่มไอคอนบนแถบงานและการปักหมุดให้ถูกตัว
const APP_USER_MODEL_ID = 'com.xmanstudio.tpix-masternode';

/**
 * เหตุผลที่ต้องข้าม (คืน null = ทำต่อได้)
 */
function skipReason() {
    if (process.platform !== 'win32') return 'ไม่ใช่ Windows';
    if (!app.isPackaged) return 'รันจากซอร์ส (dev)';
    // รุ่น portable แตกไฟล์ลงโฟลเดอร์ชั่วคราวที่หายไปหลังปิดโปรแกรม
    // สร้างช็อตคัตชี้ไปตรงนั้น = ไอคอนตายตั้งแต่ครั้งถัดไป
    if (process.env.PORTABLE_EXECUTABLE_DIR) return 'รุ่น portable';
    return null;
}

/**
 * เช็กว่ามีช็อตคัตบนเดสก์ท็อปไหม ถ้าไม่มี (หรือชี้ผิดที่) ก็สร้าง/ซ่อมให้
 * @returns {{ created: boolean, reason: string }}
 */
function ensureDesktopShortcut() {
    const skip = skipReason();
    if (skip) return { created: false, reason: `ข้าม — ${skip}` };

    try {
        const target = process.execPath;
        const linkPath = path.join(app.getPath('desktop'), `${SHORTCUT_NAME}.lnk`);

        if (fs.existsSync(linkPath)) {
            let currentTarget = null;
            try {
                currentTarget = shell.readShortcutLink(linkPath).target;
            } catch {
                // ไฟล์ .lnk เสียจนอ่านไม่ออก → ปล่อยให้เขียนทับข้างล่าง
            }
            if (currentTarget && path.normalize(currentTarget).toLowerCase()
                              === path.normalize(target).toLowerCase()) {
                return { created: false, reason: 'มีอยู่แล้ว' };
            }
        }

        // 'create' = เขียนทับได้ถ้ามีไฟล์อยู่แล้ว (ต่างจาก 'replace' ที่พังถ้าไฟล์ไม่มี)
        const ok = shell.writeShortcutLink(linkPath, 'create', {
            target,
            cwd: path.dirname(target),
            icon: target,
            iconIndex: 0,
            appUserModelId: APP_USER_MODEL_ID,
            description: 'TPIX Chain Master Node',
        });

        if (ok) {
            console.log('[shortcut] สร้างช็อตคัตบนเดสก์ท็อปคืนให้แล้ว:', linkPath);
            return { created: true, reason: 'สร้างใหม่' };
        }
        console.warn('[shortcut] เขียนไฟล์ .lnk ไม่สำเร็จ:', linkPath);
        return { created: false, reason: 'เขียนไม่สำเร็จ' };
    } catch (err) {
        // เดสก์ท็อปถูกย้ายไป OneDrive / โดนล็อกสิทธิ์ / ดิสก์เต็ม — บันทึกไว้แล้วไปต่อ
        console.warn('[shortcut] ดูแลช็อตคัตไม่สำเร็จ:', err.message);
        return { created: false, reason: err.message };
    }
}

module.exports = { ensureDesktopShortcut, SHORTCUT_NAME };
