/**
 * TPIX Master Node — Electron Main Process
 * Manages the application window, tray icon, and node lifecycle.
 * Developed by Xman Studio
 */

const { app, BrowserWindow, ipcMain, Tray, Menu, dialog, shell, session } = require('electron');
const path = require('path');
const TpixDatabase = require('./database');
const NodeManager = require('./node-manager');
const WalletManager = require('./wallet-manager');
const TransactionManager = require('./transaction-manager');
const IdentityManager = require('./identity-manager');
const AppUpdater = require('./auto-updater');

let mainWindow = null;
let tray = null;
let db = null;
let nodeManager = null;
let walletManager = null;
let txManager = null;
let identityManager = null;
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

    // Grant camera permission for QR scanning
    session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
        if (permission === 'media') {
            callback(true);
        } else {
            callback(false);
        }
    });

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

// Sanitize error messages before sending to renderer process.
// Strips file paths, stack traces, and internal details.
function sanitizeError(err) {
    const msg = err && err.message ? err.message : String(err);
    // Known safe error messages to pass through
    const safePatterns = [
        'Wallet not found', 'No active wallet', 'Wrong password',
        'Invalid input', 'Invalid address', 'Invalid private key',
        'Maximum', 'already exists', 'already imported',
        'Password is required', 'Sale not active', 'No wallet',
        'Name cannot be empty', 'Name too long', 'not found',
        'rate limit', 'circuit breaker', 'RPC timeout',
        'Insufficient', 'Amount must be', 'Invalid mnemonic',
    ];
    for (const pattern of safePatterns) {
        if (msg.includes(pattern)) return msg;
    }
    // Generic message for unknown errors (log full error server-side)
    console.error('[IPC Error]', err);
    return 'Operation failed. Please try again.';
}

function setupIPC() {
    // Initialize core services
    db = new TpixDatabase();
    nodeManager = new NodeManager(db);
    walletManager = new WalletManager(db);
    txManager = new TransactionManager(db);
    identityManager = new IdentityManager(db);

    // ═══════════════════════════════════════════════════════════
    //  WALLET — Multi-wallet (up to 128)
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('wallet:create', (_, password, name) => {
        try {
            if (typeof password !== 'string') password = '';
            return { success: true, data: walletManager.create(password, name) };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('wallet:import', (_, privateKey, password, name) => {
        try {
            if (typeof privateKey !== 'string') throw new Error('Invalid input');
            if (typeof password !== 'string') password = '';
            return { success: true, data: walletManager.importFromKey(privateKey, password, name) };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
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
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('wallet:renameWallet', (_, walletId, newName) => {
        try {
            walletManager.renameWallet(walletId, newName);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('wallet:deleteWallet', (_, walletId, password) => {
        try {
            if (typeof password !== 'string') password = '';
            walletManager.deleteWallet(walletId, password);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
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
            const key = walletManager.exportKey(walletId, password);
            return { success: true, key };
        } catch (err) { return { success: false, error: sanitizeError(err) }; }
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
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('wallet:estimateGas', async (_, toAddress, amount) => {
        try {
            return { success: true, data: await txManager.estimateGas(toAddress, amount) };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
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
            return { success: false, error: sanitizeError(err) };
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
    //  STAKING
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('staking:validateBalance', async (_, walletAddress, tier) => {
        try {
            return await nodeManager.validateStakeBalance(walletAddress, tier);
        } catch (err) {
            return { valid: false, error: err.message };
        }
    });

    ipcMain.handle('staking:register', (_, { walletId, walletAddress, rewardWallet, tier, stakeAmount, nodeName }) => {
        try {
            const id = db.insertStaking({ walletId, walletAddress, rewardWallet, tier, stakeAmount, nodeName });
            return { success: true, stakingId: id };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('staking:getActive', (_, walletId) => {
        try {
            return db.getActiveStaking(walletId) || null;
        } catch { return null; }
    });

    ipcMain.handle('staking:getHistory', (_, walletId) => {
        try {
            if (!walletId) {
                const active = walletManager.getActiveWallet();
                walletId = active ? active.id : null;
            }
            if (!walletId) return [];
            return db.getStakingHistory(walletId);
        } catch { return []; }
    });

    ipcMain.handle('staking:stop', (_, walletId) => {
        try {
            if (!walletId) {
                const active = walletManager.getActiveWallet();
                walletId = active ? active.id : null;
            }
            if (!walletId) return { success: false, error: 'No wallet' };
            db.stopStaking(walletId);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    // ═══════════════════════════════════════════════════════════
    //  HD WALLET (BIP-39)
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('wallet:hasHDSeed', () => {
        return walletManager.hasHDSeed();
    });

    ipcMain.handle('wallet:getMnemonic', (_, password) => {
        try {
            if (typeof password !== 'string') password = '';
            const mnemonic = walletManager.getMnemonic(password);
            return { success: true, mnemonic };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('wallet:recoverFromMnemonic', async (_, mnemonic, password) => {
        try {
            if (typeof password !== 'string') password = '';
            const result = await walletManager.recoverFromMnemonic(mnemonic, password);
            return { success: true, data: result };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    // ═══════════════════════════════════════════════════════════
    //  LIVING IDENTITY
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('identity:getStatus', (_, walletId) => {
        try {
            if (!walletId) {
                const active = walletManager.getActiveWallet();
                walletId = active ? active.id : null;
            }
            if (!walletId) return null;
            return identityManager.getIdentityStatus(walletId);
        } catch { return null; }
    });

    ipcMain.handle('identity:setSecurityQuestions', (_, walletId, questions) => {
        try {
            identityManager.setSecurityQuestions(walletId, questions);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('identity:getSecurityQuestions', (_, walletId) => {
        try {
            return identityManager.getSecurityQuestions(walletId);
        } catch { return []; }
    });

    ipcMain.handle('identity:setRecoveryKey', (_, walletId, key, hint) => {
        try {
            identityManager.setRecoveryKey(walletId, key, hint);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('identity:verifyRecovery', (_, walletId, data) => {
        try {
            return identityManager.attemptRecovery(walletId, data);
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    // GPS Location
    ipcMain.handle('identity:registerGPS', (_, walletId, label, lat, lng) => {
        try {
            identityManager.registerGPSLocation(walletId, label, lat, lng);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('identity:getGPSLocations', (_, walletId) => {
        try {
            return identityManager.getGPSLocations(walletId);
        } catch { return []; }
    });

    ipcMain.handle('identity:removeGPS', (_, walletId, locationId) => {
        try {
            identityManager.removeGPSLocation(walletId, locationId);
            return { success: true };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('identity:verifyGPS', (_, walletId, lat, lng) => {
        try {
            return identityManager.verifyGPSLocation(walletId, lat, lng);
        } catch (err) {
            return { verified: false, error: err.message };
        }
    });

    // ═══════════════════════════════════════════════════════════
    //  EXPLORER — Block Browser via RPC
    // ═══════════════════════════════════════════════════════════

    ipcMain.handle('explorer:getBlock', async (_, blockNumber) => {
        try {
            const { rpcCall } = require('./rpc-client');
            const hexBlock = typeof blockNumber === 'number' ? '0x' + blockNumber.toString(16) : blockNumber;
            const block = await rpcCall('eth_getBlockByNumber', [hexBlock, true], 15000);
            return { success: true, data: block };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('explorer:getLatestBlocks', async (_, count) => {
        try {
            const { rpcCall } = require('./rpc-client');
            const latestHex = await rpcCall('eth_blockNumber', [], 10000);
            const latest = parseInt(latestHex, 16);
            const blocks = [];
            const fetchCount = Math.min(count || 20, 50);
            for (let i = 0; i < fetchCount && (latest - i) >= 0; i++) {
                const hex = '0x' + (latest - i).toString(16);
                const block = await rpcCall('eth_getBlockByNumber', [hex, false], 10000);
                if (block) blocks.push(block);
            }
            return { success: true, data: blocks };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('explorer:getTx', async (_, txHash) => {
        try {
            const { rpcCall } = require('./rpc-client');
            const tx = await rpcCall('eth_getTransactionByHash', [txHash], 10000);
            const receipt = await rpcCall('eth_getTransactionReceipt', [txHash], 10000);
            return { success: true, data: { tx, receipt } };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
    });

    ipcMain.handle('explorer:getAddressInfo', async (_, address) => {
        try {
            if (!address || typeof address !== 'string' || !/^0x[0-9a-fA-F]{40}$/.test(address)) {
                return { success: false, error: 'Invalid address format' };
            }
            const { rpcCall } = require('./rpc-client');
            const addr = address.toLowerCase();

            // Fetch balance and tx count in parallel
            const [balanceHex, txCountHex, latestHex] = await Promise.all([
                rpcCall('eth_getBalance', [addr, 'latest'], 10000),
                rpcCall('eth_getTransactionCount', [addr, 'latest'], 10000),
                rpcCall('eth_blockNumber', [], 10000),
            ]);

            // Scan recent blocks for transactions involving this address
            const latest = parseInt(latestHex, 16);
            const scanDepth = Math.min(500, latest);
            const transactions = [];
            const batchSize = 10;

            for (let i = 0; i < scanDepth && transactions.length < 50; i += batchSize) {
                const promises = [];
                for (let j = 0; j < batchSize && (i + j) < scanDepth; j++) {
                    const hex = '0x' + (latest - i - j).toString(16);
                    promises.push(rpcCall('eth_getBlockByNumber', [hex, true], 10000).catch(() => null));
                }
                const blocks = await Promise.all(promises);
                for (const block of blocks) {
                    if (!block || !block.transactions) continue;
                    for (const tx of block.transactions) {
                        if ((tx.from && tx.from.toLowerCase() === addr) ||
                            (tx.to && tx.to.toLowerCase() === addr)) {
                            transactions.push({
                                hash: tx.hash,
                                from: tx.from,
                                to: tx.to,
                                value: tx.value,
                                blockNumber: tx.blockNumber,
                                timestamp: block.timestamp,
                            });
                        }
                    }
                    if (transactions.length >= 50) break;
                }
            }

            return {
                success: true,
                data: {
                    address: addr,
                    balance: balanceHex,
                    txCount: txCountHex,
                    transactions,
                },
            };
        } catch (err) {
            return { success: false, error: sanitizeError(err) };
        }
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
        catch (err) { return { success: false, error: sanitizeError(err) }; }
    });

    ipcMain.handle('node:stop', async () => {
        try { await nodeManager.stop(); return { success: true }; }
        catch (err) { return { success: false, error: sanitizeError(err) }; }
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
    nodeManager.on('reward-accrued', (reward) => { mainWindow?.webContents.send('node:rewardAccrued', reward); });
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

let isQuitting = false;
app.on('before-quit', (e) => {
    if (isQuitting) return; // Prevent infinite loop
    if (nodeManager && nodeManager.isRunning()) {
        e.preventDefault();
        isQuitting = true;
        nodeManager.stop().finally(() => app.quit());
    }
});

app.on('quit', () => {
    if (txManager) txManager.stopAll();
    if (db) db.close();
});
