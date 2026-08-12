/**
 * Simple dev server to preview the UI in browser (for development only).
 * Mocks the window.tpix IPC API so the Vue app can render.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3847;
const PKG_VERSION = require('./package.json').version;
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
    '.webp': 'image/webp',
};

const MOCK_SCRIPT = `
<script>
// Mock IPC bridge for browser preview
window.tpix = {
    node: {
        start: async () => ({ success: true }),
        stop: async () => ({ success: true }),
        status: async () => ({ status: 'stopped', nodeName: 'tpix-preview', tier: 'light', uptime: 0 }),
        getConfig: async () => ({ nodeName: 'tpix-preview', tier: 'light', rpcUrl: 'https://rpc1.tpix.online', p2pPort: 30303, maxPeers: 50 }),
        saveConfig: async () => ({ success: true }),
        getLogs: async () => [],
        onStatusUpdate: () => {},
        onLog: () => {},
        onMetrics: () => {},
        // ตัวจริงมี event นี้ ถ้า mock ไม่มี onMounted จะโยน TypeError แล้วหยุดกลางคัน
        onRewardAccrued: () => {},
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
                const r = await fetch('https://rpc1.tpix.online/', {
                    method: 'POST', headers: {'Content-Type':'application/json'},
                    body: JSON.stringify({jsonrpc:'2.0',method:'eth_blockNumber',params:[],id:1})
                });
                const d = await r.json();
                const bn = parseInt(d.result, 16);
                const r2 = await fetch('https://rpc1.tpix.online/', {
                    method: 'POST', headers: {'Content-Type':'application/json'},
                    body: JSON.stringify({jsonrpc:'2.0',method:'eth_getBlockByNumber',params:[d.result, false],id:2})
                });
                const d2 = await r2.json();
                const bt = parseInt(d2.result.timestamp, 16);
                const age = Math.floor(Date.now()/1000) - bt;
                return { blockNumber: bn, blockTime: bt, blockAge: age, isProducing: age < 30, peerCount: 3, chainId: 4289, validators: [], validatorCount: 4, rpcEndpoint: 'https://rpc1.tpix.online' };
            } catch { return { blockNumber: 67787, blockAge: 999, isProducing: false, peerCount: 3, chainId: 4289, validators: [], validatorCount: 4, rpcEndpoint: 'https://rpc1.tpix.online' }; }
        },
        getBlockNumber: async () => 67787,
        getPeerCount: async () => 0,
    },
    chain: {
        // ล้อรายงานจาก chain-health.js เพื่อให้พรีวิวในเบราว์เซอร์เห็นการ์ดสุขภาพเชนจริง
        health: async () => {
            const post = async (method, params = []) => {
                const r = await fetch('https://rpc1.tpix.online/', {
                    method: 'POST', headers: {'Content-Type':'application/json'},
                    body: JSON.stringify({jsonrpc:'2.0', method, params, id: 1})
                });
                return (await r.json()).result;
            };
            try {
                const [tipHex, peerHex, ver] = await Promise.all([
                    post('eth_blockNumber'), post('net_peerCount'), post('web3_clientVersion'),
                ]);
                const head = await post('eth_getBlockByNumber', ['latest', false]);
                const age = Math.floor(Date.now()/1000) - parseInt(head.timestamp, 16);
                const stalled = age >= 30;
                return {
                    checkedAt: Date.now(), ok: !stalled, severity: stalled ? 'critical' : 'ok',
                    tip: parseInt(tipHex, 16), headAge: age, stalled, chainId: 4289,
                    expectedBlockTime: 2, actualBlockTime: 2, slowRatio: 1, timeouts: 0,
                    peerCount: parseInt(peerHex, 16), validators: 4, missingProposers: 0,
                    clientVersion: ver,
                    messages: stalled
                        ? [{ level: 'critical', text: 'เชนหยุดออกบล็อก — บล็อกล่าสุดเก่าไปแล้ว ' + age + ' วินาที' }]
                        : [{ level: 'info', text: 'เชนปกติ — บล็อก 2s, peer ' + parseInt(peerHex, 16) + ', validator 4 ตัว' }],
                };
            } catch (e) {
                return { checkedAt: Date.now(), ok: false, severity: 'critical',
                    messages: [{ level: 'critical', text: 'ติดต่อเชนไม่ได้: ' + e.message }] };
            }
        },
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
        getVersion: async () => '${PKG_VERSION}',
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
    // เดิมเป็นรายการ "ไฟล์ไบนารี" ซึ่งลืม .webp ไว้ → ไฟล์ถูกอ่านแบบ utf-8
    // แล้วบวมจาก 43,466 เป็น 78,650 ไบต์ เบราว์เซอร์ถอดรหัสไม่ออก
    // (logo.webp ก็พังด้วยมาตลอดโดยไม่มีใครทัก)
    // กลับด้านตรรกะ: ระบุเฉพาะไฟล์ "ข้อความ" ที่เหลือถือเป็นไบนารีหมด
    const isText = ['.html', '.js', '.css', '.json', '.txt', '.map'].includes(ext);
    const isBinary = !isText;

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
