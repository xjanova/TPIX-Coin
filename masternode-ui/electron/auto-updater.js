/**
 * TPIX Master Node — Auto Updater
 * Downloads updates from GitHub Releases (xjanova/TPIX-Coin)
 * Uses electron-updater for seamless background updates.
 *
 * NOTE: the repo publishes TWO products under the same tag namespace —
 * the Flutter wallet APK (auto-released on every wallet push) and this
 * Electron app. electron-updater's github provider always reads the repo's
 * "latest release", which is often a wallet-only release with no latest.yml
 * → HTTP 404. So we resolve the newest release that actually carries a
 * Windows update channel file ourselves and feed that to the generic
 * provider. The github provider stays as a fallback.
 *
 * Developed by Xman Studio
 */

const https = require('https');
const { autoUpdater } = require('electron-updater');
const { ipcMain, BrowserWindow } = require('electron');
let log;
try { log = require('electron-log'); } catch { log = console; }

// GitHub repo: xjanova/TPIX-Coin
const GH_OWNER = 'xjanova';
const GH_REPO = 'TPIX-Coin';
const CHANNEL_FILE = 'latest.yml';
const UPDATE_CHECK_INTERVAL = 30 * 60 * 1000; // 30 minutes
const FEED_CACHE_TTL = 5 * 60 * 1000;         // re-resolve the feed tag at most every 5 min
const MAX_RELEASE_PAGES = 3;                  // scan up to 300 releases
const API_TIMEOUT = 12000;
const API_MAX_BYTES = 8 * 1024 * 1024;        // cap response size — never trust remote length
const TAG_PATTERN = /^[A-Za-z0-9._+-]{1,100}$/; // reject anything that could escape the URL path

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
        this._feedTag = null;
        this._feedTagAt = 0;

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

        // Default feed — replaced on every check by _applyFeed()
        this._applyFeed(null);

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
     * Minimal GitHub REST GET. Returns parsed JSON.
     */
    _ghApi(path) {
        return new Promise((resolve, reject) => {
            const req = https.request({
                host: 'api.github.com',
                path,
                method: 'GET',
                headers: {
                    'User-Agent': 'TPIX-MasterNode-Updater',
                    Accept: 'application/vnd.github+json',
                },
                timeout: API_TIMEOUT,
            }, (res) => {
                if (res.statusCode !== 200) {
                    const e = new Error(`GitHub API ${res.statusCode}`);
                    e.code = String(res.statusCode);
                    res.resume();
                    reject(e);
                    return;
                }
                let body = '';
                let bytes = 0;
                res.setEncoding('utf8');
                res.on('data', (chunk) => {
                    bytes += Buffer.byteLength(chunk);
                    if (bytes > API_MAX_BYTES) {
                        req.destroy(new Error('GitHub API response too large'));
                        return;
                    }
                    body += chunk;
                });
                res.on('end', () => {
                    try { resolve(JSON.parse(body)); }
                    catch { reject(new Error('Invalid response from GitHub API')); }
                });
                res.on('error', reject);
            });
            req.on('timeout', () => req.destroy(new Error('GitHub API timeout')));
            req.on('error', reject);
            req.end();
        });
    }

    /**
     * Find the newest published release that actually carries a Windows
     * update channel file — wallet-only releases are skipped.
     * Returns the tag name, or null when nothing suitable exists.
     */
    async _resolveFeedTag() {
        const now = Date.now();
        if (this._feedTag && (now - this._feedTagAt) < FEED_CACHE_TTL) return this._feedTag;

        for (let page = 1; page <= MAX_RELEASE_PAGES; page++) {
            const releases = await this._ghApi(
                `/repos/${GH_OWNER}/${GH_REPO}/releases?per_page=100&page=${page}`
            );
            if (!Array.isArray(releases) || releases.length === 0) break;

            // GitHub returns releases newest-first, so the first hit is the newest
            const hit = releases.find((rel) => rel
                && rel.draft === false
                && rel.prerelease === false
                && TAG_PATTERN.test(String(rel.tag_name || ''))
                && Array.isArray(rel.assets)
                && rel.assets.some((a) => a && a.name === CHANNEL_FILE)
                && rel.assets.some((a) => a && /\.exe$/i.test(String(a.name)))
            );
            if (hit) {
                this._feedTag = String(hit.tag_name);
                this._feedTagAt = now;
                return this._feedTag;
            }
            if (releases.length < 100) break;
        }
        return null;
    }

    /**
     * Point electron-updater at a specific release tag (generic provider),
     * or fall back to the plain github provider when we couldn't resolve one.
     */
    _applyFeed(tag) {
        if (tag && TAG_PATTERN.test(tag)) {
            autoUpdater.setFeedURL({
                provider: 'generic',
                url: `https://github.com/${GH_OWNER}/${GH_REPO}/releases/download/${encodeURIComponent(tag)}`,
                channel: 'latest',
            });
            return;
        }
        autoUpdater.setFeedURL({
            provider: 'github',
            owner: GH_OWNER,
            repo: GH_REPO,
            releaseType: 'release',
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
            let tag = null;
            try {
                tag = await this._resolveFeedTag();
            } catch (e) {
                // API unreachable / rate-limited → let the github provider try
                console.warn('[Updater] feed resolve failed:', e.message);
            }
            this._applyFeed(tag);

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
