/**
 * TPIX Master Node — Preload Script (IPC Bridge)
 * Exposes safe APIs to the renderer process.
 * Uses removeAllListeners before adding to prevent leaks.
 */

const { contextBridge, ipcRenderer } = require('electron');

/** Safe event listener — removes previous before adding new */
function onEvent(channel, cb) {
    ipcRenderer.removeAllListeners(channel);
    ipcRenderer.on(channel, (_, data) => cb(data));
}

contextBridge.exposeInMainWorld('tpix', {
    // Node lifecycle
    node: {
        start: (config) => ipcRenderer.invoke('node:start', config),
        stop: () => ipcRenderer.invoke('node:stop'),
        status: () => ipcRenderer.invoke('node:status'),
        getConfig: () => ipcRenderer.invoke('node:getConfig'),
        saveConfig: (config) => ipcRenderer.invoke('node:saveConfig', config),
        getLogs: (count) => ipcRenderer.invoke('node:getLogs', count),
        onStatusUpdate: (cb) => onEvent('node:statusUpdate', cb),
        onLog: (cb) => onEvent('node:log', cb),
        onMetrics: (cb) => onEvent('node:metrics', cb),
        onRewardAccrued: (cb) => onEvent('node:rewardAccrued', cb),
    },

    // Staking
    staking: {
        validateBalance: (walletAddress, tier) => ipcRenderer.invoke('staking:validateBalance', walletAddress, tier),
        register: (data) => ipcRenderer.invoke('staking:register', data),
        getActive: (walletId) => ipcRenderer.invoke('staking:getActive', walletId),
        getHistory: (walletId) => ipcRenderer.invoke('staking:getHistory', walletId),
        stop: (walletId) => ipcRenderer.invoke('staking:stop', walletId),
    },

    // RPC
    rpc: {
        call: (method, params) => ipcRenderer.invoke('rpc:call', method, params),
        getNetworkStats: () => ipcRenderer.invoke('rpc:getNetworkStats'),
        getBlockNumber: () => ipcRenderer.invoke('rpc:getBlockNumber'),
        getPeerCount: () => ipcRenderer.invoke('rpc:getPeerCount'),
    },

    // System
    system: {
        getMetrics: () => ipcRenderer.invoke('system:getMetrics'),
        openDataDir: () => ipcRenderer.invoke('system:openDataDir'),
        openExternal: (url) => ipcRenderer.invoke('system:openExternal', url),
    },

    // Window
    window: {
        minimize: () => ipcRenderer.invoke('window:minimize'),
        maximize: () => ipcRenderer.invoke('window:maximize'),
        close: () => ipcRenderer.invoke('window:close'),
    },

    // Auto-update
    update: {
        check: () => ipcRenderer.invoke('update:check'),
        download: () => ipcRenderer.invoke('update:download'),
        install: () => ipcRenderer.invoke('update:install'),
        getStatus: () => ipcRenderer.invoke('update:getStatus'),
        getVersion: () => ipcRenderer.invoke('update:getVersion'),
        onStatus: (cb) => onEvent('update:status', cb),
        onProgress: (cb) => onEvent('update:progress', cb),
    },

    // Wallet — multi-wallet (up to 128) with HD support
    wallet: {
        // Create / Import
        create: (password, name) => ipcRenderer.invoke('wallet:create', password, name),
        import: (privateKey, password, name) => ipcRenderer.invoke('wallet:import', privateKey, password, name),

        // HD Wallet
        hasHDSeed: () => ipcRenderer.invoke('wallet:hasHDSeed'),
        getMnemonic: (password) => ipcRenderer.invoke('wallet:getMnemonic', password),
        recoverFromMnemonic: (mnemonic, password) => ipcRenderer.invoke('wallet:recoverFromMnemonic', mnemonic, password),

        // Multi-wallet management
        listWallets: () => ipcRenderer.invoke('wallet:listWallets'),
        getWalletCount: () => ipcRenderer.invoke('wallet:getWalletCount'),
        getActiveWallet: () => ipcRenderer.invoke('wallet:getActiveWallet'),
        switchWallet: (id) => ipcRenderer.invoke('wallet:switchWallet', id),
        renameWallet: (id, name) => ipcRenderer.invoke('wallet:renameWallet', id, name),
        deleteWallet: (id, password) => ipcRenderer.invoke('wallet:deleteWallet', id, password),

        // Balance
        getAddress: () => ipcRenderer.invoke('wallet:getAddress'),
        getBalance: (walletId) => ipcRenderer.invoke('wallet:getBalance', walletId),
        getBalances: () => ipcRenderer.invoke('wallet:getBalances'),
        exportKey: (walletId, password) => ipcRenderer.invoke('wallet:exportKey', walletId, password),
        exists: () => ipcRenderer.invoke('wallet:exists'),

        // QR Code
        getQRCode: (walletId) => ipcRenderer.invoke('wallet:getQRCode', walletId),

        // Transactions
        sendTransaction: (to, amount, password) => ipcRenderer.invoke('wallet:sendTransaction', to, amount, password),
        estimateGas: (to, amount) => ipcRenderer.invoke('wallet:estimateGas', to, amount),
        getTransactions: (walletId, page, limit) => ipcRenderer.invoke('wallet:getTransactions', walletId, page, limit),
        getTxStatus: (txHash) => ipcRenderer.invoke('wallet:getTxStatus', txHash),
        scanTransactions: (walletId, blockCount) => ipcRenderer.invoke('wallet:scanTransactions', walletId, blockCount),

        // Rewards
        getRewards: (walletId) => ipcRenderer.invoke('wallet:getRewards', walletId),
    },

    // Explorer
    explorer: {
        getBlock: (num) => ipcRenderer.invoke('explorer:getBlock', num),
        getLatestBlocks: (count) => ipcRenderer.invoke('explorer:getLatestBlocks', count),
        getTx: (hash) => ipcRenderer.invoke('explorer:getTx', hash),
    },

    // Living Identity
    identity: {
        getStatus: (walletId) => ipcRenderer.invoke('identity:getStatus', walletId),
        setSecurityQuestions: (walletId, questions) => ipcRenderer.invoke('identity:setSecurityQuestions', walletId, questions),
        getSecurityQuestions: (walletId) => ipcRenderer.invoke('identity:getSecurityQuestions', walletId),
        setRecoveryKey: (walletId, key, hint) => ipcRenderer.invoke('identity:setRecoveryKey', walletId, key, hint),
        verifyRecovery: (walletId, data) => ipcRenderer.invoke('identity:verifyRecovery', walletId, data),
    },

    // Database settings
    db: {
        getSetting: (key) => ipcRenderer.invoke('db:getSetting', key),
        setSetting: (key, value) => ipcRenderer.invoke('db:setSetting', key, value),
    },
});
