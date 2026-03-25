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

    // Wallet management (password required for create/import/export)
    wallet: {
        create: (password) => ipcRenderer.invoke('wallet:create', password),
        import: (privateKey, password) => ipcRenderer.invoke('wallet:import', privateKey, password),
        getAddress: () => ipcRenderer.invoke('wallet:getAddress'),
        getBalance: () => ipcRenderer.invoke('wallet:getBalance'),
        exportKey: (password) => ipcRenderer.invoke('wallet:exportKey', password),
        exists: () => ipcRenderer.invoke('wallet:exists'),
    },
});
