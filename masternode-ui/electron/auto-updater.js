/**
 * TPIX Master Node — Auto Updater
 * Downloads updates from GitHub Releases (xjanova/TPIX-Coin)
 * Uses electron-updater for seamless background updates.
 * Developed by Xman Studio
 */

const { autoUpdater } = require('electron-updater');
const { ipcMain, BrowserWindow } = require('electron');
let log;
try { log = require('electron-log'); } catch { log = console; }

// GitHub repo: xjanova/TPIX-Coin
const UPDATE_CHECK_INTERVAL = 30 * 60 * 1000; // 30 minutes

class AppUpdater {
    constructor() {
        this.updateAvailable = false;
        this.updateDownloaded = false;
        this.updateInfo = null;
        this.downloadProgress = null;
        this.error = null;
        this.checking = false;
        this._checkTimer = null;

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

        // GitHub provider config (reads from package.json "build.publish")
        // Can also set manually:
        autoUpdater.setFeedURL({
            provider: 'github',
            owner: 'xjanova',
            repo: 'TPIX-Coin',
            releaseType: 'release',
        });

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
            this._sendToRenderer('update:status', this.getStatus());
        });

        autoUpdater.on('error', (err) => {
            this.checking = false;
            this.error = err.message || 'Update check failed';
            this._sendToRenderer('update:status', this.getStatus());
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
        try {
            this.error = null;
            const result = await autoUpdater.checkForUpdates();
            return { success: true, data: this.getStatus() };
        } catch (err) {
            this.error = err.message;
            return { success: false, error: err.message };
        }
    }

    /**
     * Start downloading the update.
     */
    async downloadUpdate() {
        if (!this.updateAvailable) {
            return { success: false, error: 'No update available' };
        }

        try {
            this.downloadProgress = { percent: 0, transferred: 0, total: 0, bytesPerSecond: 0 };
            await autoUpdater.downloadUpdate();
            return { success: true };
        } catch (err) {
            this.error = err.message;
            return { success: false, error: err.message };
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
        };
    }

    /**
     * Start periodic update checks.
     */
    startAutoCheck() {
        // Check immediately on startup (after 10s delay for app init)
        setTimeout(() => this.checkForUpdates(), 10000);

        // Then check every 30 minutes
        this._checkTimer = setInterval(() => {
            this.checkForUpdates();
        }, UPDATE_CHECK_INTERVAL);
    }

    /**
     * Stop periodic update checks.
     */
    stopAutoCheck() {
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
