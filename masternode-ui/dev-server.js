/**
 * Simple dev server to preview the UI in browser (for development only).
 * Mocks the window.tpix IPC API so the Vue app can render.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3847;
const SRC = path.join(__dirname, 'src');

const MIME = {
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.css': 'text/css',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
};

const MOCK_SCRIPT = `
<script>
// Mock IPC bridge for browser preview
window.tpix = {
    node: {
        start: async () => ({ success: true }),
        stop: async () => ({ success: true }),
        status: async () => ({ status: 'stopped', nodeName: 'tpix-preview', tier: 'light', uptime: 0 }),
        getConfig: async () => ({ nodeName: 'tpix-preview', tier: 'light', rpcUrl: 'https://rpc.tpix.online', p2pPort: 30303, maxPeers: 50 }),
        saveConfig: async () => ({ success: true }),
        getLogs: async () => [],
        onStatusUpdate: () => {},
        onLog: () => {},
        onMetrics: () => {},
    },
    rpc: {
        call: async (method) => {
            if (method === 'eth_blockNumber') return '0x108cb';
            if (method === 'net_peerCount') return '0x0';
            if (method === 'net_version') return '4289';
            return null;
        },
        getNetworkStats: async () => {
            // Fetch real data from TPIX RPC
            try {
                const r = await fetch('https://rpc.tpix.online/', {
                    method: 'POST', headers: {'Content-Type':'application/json'},
                    body: JSON.stringify({jsonrpc:'2.0',method:'eth_blockNumber',params:[],id:1})
                });
                const d = await r.json();
                const bn = parseInt(d.result, 16);
                const r2 = await fetch('https://rpc.tpix.online/', {
                    method: 'POST', headers: {'Content-Type':'application/json'},
                    body: JSON.stringify({jsonrpc:'2.0',method:'eth_getBlockByNumber',params:[d.result, false],id:2})
                });
                const d2 = await r2.json();
                const bt = parseInt(d2.result.timestamp, 16);
                const age = Math.floor(Date.now()/1000) - bt;
                return { blockNumber: bn, blockTime: bt, blockAge: age, isProducing: age < 30, peerCount: 0, chainId: 4289, validators: [], validatorCount: 3 };
            } catch { return { blockNumber: 67787, blockAge: 999, isProducing: false, peerCount: 0, chainId: 4289, validators: [], validatorCount: 3 }; }
        },
        getBlockNumber: async () => 67787,
        getPeerCount: async () => 0,
    },
    system: {
        getMetrics: async () => ({ cpu: 12, memoryUsed: 4096, memoryTotal: 16384, memoryPercent: 25, platform: 'win32', arch: 'x64' }),
        openDataDir: () => {},
        openExternal: (url) => window.open(url, '_blank'),
    },
    window: {
        minimize: () => {},
        maximize: () => {},
        close: () => {},
    },
    update: {
        check: async () => ({ success: true, data: { checking: false, updateAvailable: false, updateDownloaded: false, updateInfo: null, downloadProgress: null, error: null }}),
        download: async () => ({ success: true }),
        install: () => ({ success: true }),
        getStatus: async () => ({ checking: false, updateAvailable: false, updateDownloaded: false, updateInfo: null, downloadProgress: null, error: null }),
        getVersion: async () => '1.0.0',
        onStatus: () => {},
        onProgress: () => {},
    },
    wallet: {
        create: async () => ({ success: true, data: { address: '0x' + Array(40).fill(0).map(()=>Math.floor(Math.random()*16).toString(16)).join(''), privateKey: '0x' + Array(64).fill(0).map(()=>Math.floor(Math.random()*16).toString(16)).join(''), created: true }}),
        import: async () => ({ success: true, data: { address: '0xabc123...', imported: true }}),
        getAddress: async () => null,
        getBalance: async () => '0',
        exportKey: async () => '0x...',
        exists: async () => false,
    },
};
</script>
`;

http.createServer((req, res) => {
    let filePath = req.url === '/' ? '/index.html' : req.url;
    let fullPath = path.join(SRC, filePath);
    // Also check assets directory for logo etc.
    if (!fs.existsSync(fullPath)) {
        const assetPath = path.join(__dirname, 'assets', path.basename(filePath));
        if (fs.existsSync(assetPath)) fullPath = assetPath;
    }
    const ext = path.extname(fullPath);

    if (!fs.existsSync(fullPath)) {
        res.writeHead(404);
        res.end('Not found');
        return;
    }

    const mimeType = MIME[ext] || 'application/octet-stream';
    const isBinary = ['.png', '.ico', '.jpg', '.jpeg', '.gif', '.svg'].includes(ext);

    if (isBinary) {
        const content = fs.readFileSync(fullPath);
        res.writeHead(200, { 'Content-Type': mimeType });
        res.end(content);
        return;
    }

    let content = fs.readFileSync(fullPath, 'utf-8');

    // Inject mock IPC for browser preview
    if (ext === '.html') {
        content = content.replace('<script src="renderer.js"></script>', MOCK_SCRIPT + '<script src="renderer.js"></script>');
    }

    res.writeHead(200, { 'Content-Type': mimeType });
    res.end(content);
}).listen(PORT, () => {
    console.log(`TPIX Master Node preview: http://localhost:${PORT}`);
});
