/**
 * TPIX Master Node — Electron Main Process
 * Manages the application window, tray icon, and node lifecycle.
 * Developed by Xman Studio
 */

const { app, BrowserWindow, ipcMain, Tray, Menu, dialog, shell } = require('electron');
const path = require('path');
const NodeManager = require('./node-manager');
const WalletManager = require('./wallet-manager');
const AppUpdater = require('./auto-updater');

let mainWindow = null;
let tray = null;
let nodeManager = null;
let walletManager = null;
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
    // Use a simple icon path - in production would be a proper .ico
    try {
        tray = new Tray(path.join(__dirname, '..', 'assets', 'icon.ico'));
    } catch {
        // Tray icon not available, skip
        return;
    }

    const contextMenu = Menu.buildFromTemplate([
        {
            label: 'Open TPIX Master Node',
            click: () => {
                if (mainWindow) {
                    mainWindow.show();
                    mainWindow.focus();
                } else {
                    createWindow();
                }
            },
        },
        { type: 'separator' },
        {
            label: 'Node Status',
            enabled: false,
            id: 'status',
        },
        { type: 'separator' },
        {
            label: 'Quit',
            click: async () => {
                if (nodeManager && nodeManager.isRunning()) {
                    await nodeManager.stop();
                }
                app.quit();
            },
        },
    ]);

    tray.setToolTip('TPIX Master Node');
    tray.setContextMenu(contextMenu);
    tray.on('click', () => {
        if (mainWindow) {
            mainWindow.show();
            mainWindow.focus();
        }
    });
}

// ─── IPC Handlers ──────────────────────────────────────────────

function setupIPC() {
    nodeManager = new NodeManager();
    walletManager = new WalletManager();

    // Wallet handlers
    ipcMain.handle('wallet:create', (_, password) => {
        try {
            if (typeof password !== 'string') password = '';
            return { success: true, data: walletManager.create(password) };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:import', (_, privateKey, password) => {
        try {
            if (typeof privateKey !== 'string') throw new Error('Invalid input');
            if (typeof password !== 'string') password = '';
            return { success: true, data: walletManager.importFromKey(privateKey, password) };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('wallet:getAddress', () => {
        try {
            return walletManager.getAddress();
        } catch {
            return null;
        }
    });

    ipcMain.handle('wallet:getBalance', async () => {
        try {
            return await walletManager.getBalance();
        } catch {
            return '0';
        }
    });

    ipcMain.handle('wallet:exportKey', (_, password) => {
        try {
            if (typeof password !== 'string') password = '';
            return walletManager.exportKey(password);
        } catch (err) {
            return null;
        }
    });

    ipcMain.handle('wallet:exists', () => {
        return walletManager.exists();
    });

    // Node lifecycle
    ipcMain.handle('node:start', async (_, config) => {
        try {
            await nodeManager.start(config);
            return { success: true };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('node:stop', async () => {
        try {
            await nodeManager.stop();
            return { success: true };
        } catch (err) {
            return { success: false, error: err.message };
        }
    });

    ipcMain.handle('node:status', () => {
        return nodeManager.getStatus();
    });

    ipcMain.handle('node:getConfig', () => {
        return nodeManager.getConfig();
    });

    ipcMain.handle('node:saveConfig', (_, config) => {
        nodeManager.saveConfig(config);
        return { success: true };
    });

    ipcMain.handle('node:getLogs', (_, count) => {
        return nodeManager.getLogs(count || 100);
    });

    // RPC queries
    ipcMain.handle('rpc:call', async (_, method, params) => {
        return nodeManager.rpcCall(method, params);
    });

    ipcMain.handle('rpc:getNetworkStats', async () => {
        return nodeManager.getNetworkStats();
    });

    ipcMain.handle('rpc:getBlockNumber', async () => {
        return nodeManager.getBlockNumber();
    });

    ipcMain.handle('rpc:getPeerCount', async () => {
        return nodeManager.getPeerCount();
    });

    // System
    ipcMain.handle('system:getMetrics', () => {
        return nodeManager.getSystemMetrics();
    });

    ipcMain.handle('system:openDataDir', () => {
        const dataDir = nodeManager.getDataDir();
        shell.openPath(dataDir);
    });

    ipcMain.handle('system:openExternal', (_, url) => {
        try {
            const parsed = new URL(url);
            if (['http:', 'https:'].includes(parsed.protocol)) {
                shell.openExternal(url);
            }
        } catch { /* invalid URL, ignore */ }
    });

    // Window controls
    ipcMain.handle('window:minimize', () => mainWindow?.minimize());
    ipcMain.handle('window:maximize', () => {
        if (mainWindow?.isMaximized()) {
            mainWindow.unmaximize();
        } else {
            mainWindow?.maximize();
        }
    });
    ipcMain.handle('window:close', () => mainWindow?.close());

    // Forward node events to renderer
    nodeManager.on('status-change', (status) => {
        mainWindow?.webContents.send('node:statusUpdate', status);
    });

    nodeManager.on('log', (line) => {
        mainWindow?.webContents.send('node:log', line);
    });

    nodeManager.on('metrics', (metrics) => {
        mainWindow?.webContents.send('node:metrics', metrics);
    });
}

// ─── App Lifecycle ─────────────────────────────────────────────

app.whenReady().then(() => {
    setupIPC();
    createWindow();
    createTray();

    // Auto-updater: check GitHub releases for new versions
    appUpdater = new AppUpdater();
    appUpdater.startAutoCheck();
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        if (!nodeManager || !nodeManager.isRunning()) {
            app.quit();
        }
    }
});

app.on('activate', () => {
    if (!mainWindow) createWindow();
});

app.on('before-quit', (e) => {
    if (nodeManager && nodeManager.isRunning()) {
        e.preventDefault();
        nodeManager.stop().then(() => app.quit());
    }
});
