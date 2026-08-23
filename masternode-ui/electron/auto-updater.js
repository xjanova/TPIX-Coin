/**
 * TPIX Master Node — ตัวอัปเดตอัตโนมัติ
 *
 * ดึงอัปเดตผ่านเซิร์ฟเวอร์ TPIX (https://tpix.online/updates/masternode)
 * ไม่ใช่จาก GitHub โดยตรง
 *
 * ทำไมต้องผ่านเซิร์ฟเวอร์:
 * repo ของโปรแกรมนี้เป็นไพรเวท ถ้าให้แอปคุยกับ GitHub เองต้องฝัง token
 * ลงในไฟล์ .exe ที่แจกให้ผู้ใช้ — ซึ่งใครก็แกะออกมาได้ และ token ที่มีสิทธิ์
 * อ่าน repo ไพรเวทตัวหนึ่ง มักเปิดตัวอื่นได้หมด เซิร์ฟเวอร์จึงเป็นคนถือ token
 * ไปดึงแทน แล้วส่งต่อให้แอป ตัวแอปที่แจกออกไปจึงไม่มีความลับติดไปเลย
 *
 * ผลพลอยได้: ตรรกะเลือก release ย้ายไปอยู่ฝั่งเซิร์ฟเวอร์ที่เดียว
 * (รวมถึงการข้าม release ที่ไม่มี latest.yml ซึ่งเคยทำให้เด้ง 404 ใส่หน้าผู้ใช้)
 * แก้ทีเดียวมีผลกับทุกเครื่องทันที ไม่ต้องรอผู้ใช้อัปเดตแอปก่อน
 *
 * Developed by Xman Studio
 */

const { autoUpdater } = require('electron-updater');
const { ipcMain, BrowserWindow } = require('electron');
let log;
try { log = require('electron-log'); } catch { log = console; }

// ปลายทางอัปเดต — ห้ามเปลี่ยน URL นี้เด็ดขาด
// เพราะมันถูกฝังอยู่ในไฟล์ .exe ที่แจกออกไปแล้วทุกเครื่อง เปลี่ยนเมื่อไหร่
// เครื่องเก่าจะหาอัปเดตไม่เจออีกเลยและไม่มีทางรู้ตัว (ตั้ง env ได้เพื่อทดสอบ)
const UPDATE_FEED_URL = process.env.TPIX_UPDATE_FEED_URL
    || 'https://tpix.online/updates/masternode';
const UPDATE_CHECK_INTERVAL = 30 * 60 * 1000; // 30 minutes

class AppUpdater {
    constructor() {
        this.updateAvailable = false;
        this.updateDownloaded = false;
        this.updateInfo = null;
        this.downloadProgress = null;
        this.error = null;
        this.errorCode = null;
        this.checking = false;
        this._checkTimer = null;
        this._firstCheckTimer = null;
        this._downloading = false;

        this._configureAutoUpdater();
        this._setupIPC();
    }

    /**
     * Configure electron-updater settings.
     */
    _configureAutoUpdater() {
        // Don't auto-download — let user decide
        autoUpdater.autoDownload = false;
        autoUpdater.autoInstallOnAppQuit = true;
        autoUpdater.allowDowngrade = false;

        // ปลายทางมีตัวเดียวคงที่ — เซิร์ฟเวอร์เป็นคนเลือก release ให้แล้ว
        this._applyFeed();

        // Use simple logger
        autoUpdater.logger = {
            info: (...args) => console.log('[Updater]', ...args),
            warn: (...args) => console.warn('[Updater]', ...args),
            error: (...args) => console.error('[Updater]', ...args),
        };

        // ─── Events ────────────────────────────────

        autoUpdater.on('checking-for-update', () => {
            this.checking = true;
            this.error = null;
            this.errorCode = null;
            this._sendToRenderer('update:status', this.getStatus());
        });

        autoUpdater.on('update-available', (info) => {
            this.checking = false;
            this.updateAvailable = true;
            this.updateInfo = {
                version: info.version,
                releaseDate: info.releaseDate,
                releaseName: info.releaseName || `v${info.version}`,
                releaseNotes: typeof info.releaseNotes === 'string'
                    ? info.releaseNotes
                    : (info.releaseNotes || []).map(n => n.note || '').join('\n'),
            };
            this._sendToRenderer('update:status', this.getStatus());
        });

        autoUpdater.on('update-not-available', (info) => {
            this.checking = false;
            this.updateAvailable = false;
            this.updateInfo = null;
            this._sendToRenderer('update:status', this.getStatus());
        });

        autoUpdater.on('download-progress', (progress) => {
            this.downloadProgress = {
                percent: Math.round(progress.percent),
                transferred: progress.transferred,
                total: progress.total,
                bytesPerSecond: progress.bytesPerSecond,
            };
            this._sendToRenderer('update:progress', this.downloadProgress);
        });

        autoUpdater.on('update-downloaded', (info) => {
            this.updateDownloaded = true;
            this.downloadProgress = null;
            this._downloading = false;
            this._sendToRenderer('update:status', this.getStatus());
        });

        autoUpdater.on('error', (err) => {
            const norm = this._normalizeError(err);
            this.checking = false;
            this._downloading = false;
            // A failed download must not leave a frozen progress bar behind
            this.downloadProgress = null;
            this.error = norm.message;
            this.errorCode = norm.code;
            this._sendToRenderer('update:status', this.getStatus());
        });
    }

    /**
     * Turn any updater failure into a short, safe, user-facing string.
     * electron-updater errors carry full stack traces + HTTP headers —
     * those must never reach the UI.
     */
    _normalizeError(err) {
        const code = err && err.code ? String(err.code) : '';
        const first = (err && err.message ? String(err.message) : '').split('\n')[0].trim();
        const probe = `${code} ${first}`;

        if (code === 'ERR_UPDATER_CHANNEL_FILE_NOT_FOUND' || /Cannot find [\w.-]+\.yml/i.test(first)) {
            return { code: 'NO_FEED', message: 'No Windows update package published yet' };
        }
        if (/not packed|dev-app-update|ERR_UPDATER_NO_PUBLISHED_VERSIONS/i.test(probe)) {
            return { code: 'DEV_MODE', message: 'Updates are disabled in this build' };
        }
        if (/ENOTFOUND|EAI_AGAIN|ECONNREFUSED|ECONNRESET|ETIMEDOUT|ENETUNREACH|EHOSTUNREACH|CERT_|timeout/i.test(probe)) {
            return { code: 'NETWORK', message: 'Cannot reach the update server' };
        }
        if (/\b(403|429)\b|rate limit/i.test(probe)) {
            return { code: 'RATE_LIMIT', message: 'Update server is busy' };
        }
        return { code: 'UNKNOWN', message: 'Update check failed' };
    }

    /**
     * ชี้ electron-updater ไปที่เซิร์ฟเวอร์ TPIX
     *
     * ไม่มีทางสำรองไป GitHub แล้ว — repo เป็นไพรเวท ถึงลองก็ได้ 404
     * เหลือไว้มีแต่จะทำให้ผู้ใช้เห็นข้อความผิดจนหาสาเหตุยากขึ้น
     */
    _applyFeed() {
        autoUpdater.setFeedURL({
            provider: 'generic',
            url: UPDATE_FEED_URL,
            channel: 'latest',
        });
    }

    /**
     * Set up IPC handlers for renderer communication.
     */
    _setupIPC() {
        ipcMain.handle('update:check', async () => {
            return this.checkForUpdates();
        });

        ipcMain.handle('update:download', async () => {
            return this.downloadUpdate();
        });

        ipcMain.handle('update:install', () => {
            return this.installUpdate();
        });

        ipcMain.handle('update:getStatus', () => {
            return this.getStatus();
        });

        ipcMain.handle('update:getVersion', () => {
            const { app } = require('electron');
            return app.getVersion();
        });
    }

    /**
     * Check for updates from GitHub Releases.
     */
    async checkForUpdates() {
        // Double-tap guard — "Check Now" can be hammered
        if (this.checking) return { success: true, data: this.getStatus() };

        this.checking = true;
        this.error = null;
        this.errorCode = null;
        this._sendToRenderer('update:status', this.getStatus());

        try {
            this._applyFeed();

            await autoUpdater.checkForUpdates();
            this.checking = false;
            this._sendToRenderer('update:status', this.getStatus());
            return { success: true, data: this.getStatus() };
        } catch (err) {
            const norm = this._normalizeError(err);
            this.checking = false;
            this.error = norm.message;
            this.errorCode = norm.code;
            this._sendToRenderer('update:status', this.getStatus());
            return { success: false, error: norm.message, errorCode: norm.code };
        }
    }

    /**
     * Start downloading the update.
     */
    async downloadUpdate() {
        if (!this.updateAvailable) {
            return { success: false, error: 'No update available' };
        }
        // Double-tap guard — a second downloadUpdate() would race the first
        if (this._downloading) {
            return { success: true, data: this.getStatus() };
        }

        this._downloading = true;
        try {
            this.downloadProgress = { percent: 0, transferred: 0, total: 0, bytesPerSecond: 0 };
            this._sendToRenderer('update:progress', this.downloadProgress);
            await autoUpdater.downloadUpdate();
            return { success: true };
        } catch (err) {
            const norm = this._normalizeError(err);
            this.downloadProgress = null;
            this.error = norm.message;
            this.errorCode = norm.code;
            this._sendToRenderer('update:status', this.getStatus());
            return { success: false, error: norm.message, errorCode: norm.code };
        } finally {
            this._downloading = false;
        }
    }

    /**
     * Install the downloaded update and restart.
     */
    installUpdate() {
        if (!this.updateDownloaded) {
            return { success: false, error: 'No update downloaded' };
        }

        // This will quit the app and install the update
        autoUpdater.quitAndInstall(false, true);
        return { success: true };
    }

    /**
     * Get current update status.
     */
    getStatus() {
        return {
            checking: this.checking,
            updateAvailable: this.updateAvailable,
            updateDownloaded: this.updateDownloaded,
            updateInfo: this.updateInfo,
            downloadProgress: this.downloadProgress,
            error: this.error,
            errorCode: this.errorCode,
        };
    }

    /**
     * Start periodic update checks.
     */
    startAutoCheck() {
        // Check immediately on startup (after 10s delay for app init)
        this._firstCheckTimer = setTimeout(() => this.checkForUpdates(), 10000);

        // Then check every 30 minutes
        this._checkTimer = setInterval(() => {
            this.checkForUpdates();
        }, UPDATE_CHECK_INTERVAL);
    }

    /**
     * Stop periodic update checks.
     */
    stopAutoCheck() {
        if (this._firstCheckTimer) {
            clearTimeout(this._firstCheckTimer);
            this._firstCheckTimer = null;
        }
        if (this._checkTimer) {
            clearInterval(this._checkTimer);
            this._checkTimer = null;
        }
    }

    /**
     * Send event to renderer process.
     */
    _sendToRenderer(channel, data) {
        const windows = BrowserWindow.getAllWindows();
        windows.forEach((win) => {
            if (!win.isDestroyed()) {
                win.webContents.send(channel, data);
            }
        });
    }
}

module.exports = AppUpdater;
