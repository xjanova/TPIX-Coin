/**
 * TPIX Master Node — Electron Main Process
 * Manages the application window, tray icon, and node lifecycle.
 * Developed by Xman Studio
 */

const { app, BrowserWindow, ipcMain, Tray, Menu, dialog, shell } = require('electron');
const path = require('path');
const TpixDatabase = require('./database');
const NodeManager = require('./node-manager');
const WalletManager = require('./wallet-manager');
const TransactionManager = require('./transaction-manager');
const AppUpdater = require('./auto-updater');

let mainWindow = null;
let tray = null;
let db = null;
let nodeManager = null;
let walletManager = null;
let txManager = null;
let appUpdater = null;

const isDev = process.env.NODE_ENV === 'development';

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1280,
        height: 820,
        minWidth: 960,
        minHeight: 640,
        frame: false,
        transparent: false,
        backgroundColor: '#0a0e1a',
        titleBarStyle: 'hidden',
        titleBarOverlay: {
            color: '#0a0e1a',
            symbolColor: '#ffffff',
            height: 36,
        },
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
        },
        icon: path.join(__dirname, '..', 'assets', 'icon.ico'),
    });

    mainWindow.loadFile(path.join(__dirname, '..', 'src', 'index.html'));

    if (isDev) {
        mainWindow.webContents.openDevTools({ mode: 'detach' });
    }

    mainWindow.on('close', (e) => {
        if (nodeManager && nodeManager.isRunning()) {
            e.preventDefault();
            mainWindow.hide();
        }
    });

    mainWindow.on('closed', () => {
        mainWindow = null;
    });
}

function createTray() {
    try {
        tray = new Tray(path.join(__dirname, '..', 'assets', 'icon.ico'));
    } catch {
        return;
    }

    const contextMenu = Menu.buildFromTemplate([
        {
            label: 'Open TPIX Master Node',
            click: () => {
                if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
                else { createWindow(); }
            },
        },
        { type: 'separator' },
        { label: 'Node Status', enabled: false, id: 'status' },
        { type: 'separator' },
        {
            label: 'Quit',
            click: async () => {
                if (nodeManager && nodeManager.isRunning()) await nodeManager.stop();
                app.quit();
            },
        },
    ]);

    tray.setToolTip('TPIX Master Node');
    tray.setContextMenu(contextMenu);
    tray.on('click', () => { if (mainWindow) { mainWindow.show(); mainWindow.focus(); } });
}

// ─── IPC Handlers ──────────────────────────────────────────────

function setupIPC() {
    // Initialize core services
    db = new TpixDatabase();
    nodeManager = new NodeManager();
    walletManager = new WalletManager(db);
    txManager = new TransactionManager(db);

    // ═══════════════════════════════════════════════════════════
    //  WALLET — Multi-wallet (up to 128)
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('wallet:create', (_, password, name) => {
        try {
            if (typeof password !== 'string') password = '';
            return { success: true, data: walletManager.create(password, name) };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:import', (_, privateKey, password, name) => {
        try {
            if (typeof privateKey !== 'string') throw new Error('Invalid input');
            if (typeof password !== 'string') password = '';
            return { success: true, data: walletManager.importFromKey(privateKey, password, name) };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:listWallets', () => {
        return walletManager.listWallets();
    });

    ipcMain.handle('wallet:getWalletCount', () => {
        return walletManager.getWalletCount();
    });

    ipcMain.handle('wallet:getActiveWallet', () => {
        const w = walletManager.getActiveWallet();
        return w ? { id: w.id, slot: w.slot, name: w.name, address: w.address } : null;
    });

    ipcMain.handle('wallet:switchWallet', (_, walletId) => {
        try {
            walletManager.switchWallet(walletId);
            return { success: true };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:renameWallet', (_, walletId, newName) => {
        try {
            walletManager.renameWallet(walletId, newName);
            return { success: true };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:deleteWallet', (_, walletId, password) => {
        try {
            if (typeof password !== 'string') password = '';
            walletManager.deleteWallet(walletId, password);
            return { success: true };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    // Backward-compatible
    ipcMain.handle('wallet:getAddress', () => {
        try { return walletManager.getAddress(); }
        catch { return null; }
    });

    ipcMain.handle('wallet:getBalance', async (_, walletId) => {
        try { return await walletManager.getBalance(walletId); }
        catch { return '0'; }
    });

    ipcMain.handle('wallet:getBalances', async () => {
        try { return await walletManager.getBalances(); }
        catch { return {}; }
    });

    ipcMain.handle('wallet:exportKey', (_, walletId, password) => {
        try {
            if (typeof password !== 'string') password = '';
            return walletManager.exportKey(walletId, password);
        } catch { return null; }
    });

    ipcMain.handle('wallet:exists', () => {
        return walletManager.exists();
    });

    // ═══════════════════════════════════════════════════════════
    //  QR CODE
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('wallet:getQRCode', async (_, walletId) => {
        try { return await walletManager.generateQR(walletId); }
        catch { return null; }
    });

    // ═══════════════════════════════════════════════════════════
    //  TRANSACTIONS
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('wallet:sendTransaction', async (_, toAddress, amount, password) => {
        try {
            const activeWallet = walletManager.getActiveWallet();
            if (!activeWallet) throw new Error('No active wallet');
            if (typeof password !== 'string') password = '';

            // Decrypt private key
            const privateKey = walletManager.exportKey(activeWallet.id, password);
            if (!privateKey) throw new Error('Wrong password');

            const result = await txManager.sendTransaction(
                privateKey, activeWallet.address, toAddress, amount, activeWallet.id
            );
            return { success: true, data: result };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:estimateGas', async (_, toAddress, amount) => {
        try {
            return { success: true, data: await txManager.estimateGas(toAddress, amount) };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:getTransactions', (_, walletId, page, limit) => {
        try {
            if (!walletId) {
                const active = walletManager.getActiveWallet();
                walletId = active ? active.id : null;
            }
            if (!walletId) return { transactions: [], total: 0 };
            return db.getTransactions(walletId, page || 1, limit || 20);
        } catch { return { transactions: [], total: 0 }; }
    });

    ipcMain.handle('wallet:getTxStatus', async (_, txHash) => {
        try { return await txManager.getTxStatus(txHash); }
        catch { return { status: 'unknown' }; }
    });

    ipcMain.handle('wallet:scanTransactions', async (_, walletId, blockCount) => {
        try {
            let address;
            if (walletId) {
                const w = db.getWallet(walletId);
                address = w ? w.address : null;
            } else {
                const active = walletManager.getActiveWallet();
                walletId = active ? active.id : null;
                address = active ? active.address : null;
            }
            if (!walletId || !address) return { success: false, error: 'No wallet' };
            await txManager.scanIncoming(walletId, address, blockCount || 100);
            return { success: true };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    // ═══════════════════════════════════════════════════════════
    //  REWARDS
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('wallet:getRewards', (_, walletId) => {
        try {
            if (!walletId) {
                const active = walletManager.getActiveWallet();
                walletId = active ? active.id : null;
            }
            if (!walletId) return { rewards: [], total: 0 };
            const rewards = db.getRewards(walletId);
            const total = db.getTotalRewards(walletId);
            return { rewards, total };
        } catch { return { rewards: [], total: 0 }; }
    });

    // ═══════════════════════════════════════════════════════════
    //  SETTINGS (SQLite)
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('db:getSetting', (_, key) => {
        return db.getSetting(key);
    });

    ipcMain.handle('db:setSetting', (_, key, value) => {
        db.setSetting(key, value);
        return { success: true };
    });

    // ═══════════════════════════════════════════════════════════
    //  NODE LIFECYCLE
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('node:start', async (_, config) => {
        try { await nodeManager.start(config); return { success: true }; }
        catch (err) { return { success: false, error: err.message }; }
    });

    ipcMain.handle('node:stop', async () => {
        try { await nodeManager.stop(); return { success: true }; }
        catch (err) { return { success: false, error: err.message }; }
    });

    ipcMain.handle('node:status', () => nodeManager.getStatus());
    ipcMain.handle('node:getConfig', () => nodeManager.getConfig());
    ipcMain.handle('node:saveConfig', (_, config) => { nodeManager.saveConfig(config); return { success: true }; });
    ipcMain.handle('node:getLogs', (_, count) => nodeManager.getLogs(count || 100));

    // RPC queries
    ipcMain.handle('rpc:call', async (_, method, params) => nodeManager.rpcCall(method, params));
    ipcMain.handle('rpc:getNetworkStats', async () => nodeManager.getNetworkStats());
    ipcMain.handle('rpc:getBlockNumber', async () => nodeManager.getBlockNumber());
    ipcMain.handle('rpc:getPeerCount', async () => nodeManager.getPeerCount());

    // System
    ipcMain.handle('system:getMetrics', () => nodeManager.getSystemMetrics());
    ipcMain.handle('system:openDataDir', () => { shell.openPath(nodeManager.getDataDir()); });
    ipcMain.handle('system:openExternal', (_, url) => {
        try {
            const parsed = new URL(url);
            if (['http:', 'https:'].includes(parsed.protocol)) shell.openExternal(url);
        } catch {}
    });

    // Window controls
    ipcMain.handle('window:minimize', () => mainWindow?.minimize());
    ipcMain.handle('window:maximize', () => {
        if (mainWindow?.isMaximized()) mainWindow.unmaximize();
        else mainWindow?.maximize();
    });
    ipcMain.handle('window:close', () => mainWindow?.close());

    // Forward node events to renderer
    nodeManager.on('status-change', (status) => { mainWindow?.webContents.send('node:statusUpdate', status); });
    nodeManager.on('log', (line) => { mainWindow?.webContents.send('node:log', line); });
    nodeManager.on('metrics', (metrics) => { mainWindow?.webContents.send('node:metrics', metrics); });
}

// ─── App Lifecycle ─────────────────────────────────────────────

app.whenReady().then(() => {
    setupIPC();
    createWindow();
    createTray();

    appUpdater = new AppUpdater();
    appUpdater.startAutoCheck();
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        if (!nodeManager || !nodeManager.isRunning()) app.quit();
    }
});

app.on('activate', () => { if (!mainWindow) createWindow(); });

app.on('before-quit', (e) => {
    if (nodeManager && nodeManager.isRunning()) {
        e.preventDefault();
        nodeManager.stop().then(() => app.quit());
    }
});

app.on('quit', () => {
    if (txManager) txManager.stopAll();
    if (db) db.close();
});
