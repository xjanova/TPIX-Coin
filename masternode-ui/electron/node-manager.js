/**
 * TPIX Master Node — Node Process Manager
 * Manages the Polygon Edge process lifecycle, configuration,
 * RPC communication, and system metrics.
 * Developed by Xman Studio
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const EventEmitter = require('events');
const {
    rpcCall: sharedRpcCall,
    setEndpoint,
    getEndpoint,
    TPIX_RPC,
    LEGACY_DEFAULTS,
} = require('./rpc-client');
const { decodeValidators } = require('./ibft-extra');
const chainHealth = require('./chain-health');

const CHAIN_ID = 4289;

// blockTime ที่ genesis ตั้งไว้ — ใช้เป็น "ค่าสำรองสุดท้าย" เท่านั้น ห้ามใช้คำนวณตรงๆ
//
// แก้ 2026-08-05: เดิมค่านี้ถูกใช้ประมาณ block number ตอน RPC ล่ม
//     blockNumber = last_reward_block + Math.floor(elapsedSeconds / BLOCK_TIME)
// ตรวจเชนจริงเมื่อ 2026-08-05 แล้วพบว่าบล็อกออกทุก ~6 วินาที ไม่ใช่ 2
// (validator 1 ใน 4 ไม่ propose → IBFT timeout รอบละ ~10s ดู chain-health.js)
// → สูตรเดิมประมาณ block number **เกินไป 3 เท่า** แล้วค่านั้นถูกเขียนลงเป็น
//   checkpoint การจ่ายรางวัล staking (db.updateStakingRewardCheckpoint)
// ตอนนี้ใช้ chainHealth.measuredBlockTime() ที่วัดจากเชนจริง (median ของช่องว่าง
// บล็อก เพื่อไม่ให้ round timeout ที่เป็น outlier ลากค่าเพี้ยน)
const BLOCK_TIME_FALLBACK = 2; // seconds

/**
 * บล็อกล่าสุดเก่ากว่ากี่วินาทีถึงเรียกว่า "เชนหยุดออกบล็อก"
 * 30 วิ = ~15 บล็อกที่ควรจะออกมาแล้ว มากพอไม่ให้ไฟกะพริบตอนเน็ตสะดุด
 */
const STALL_SECONDS = 30;

// Tier definitions — stake in TPIX, APY as decimal
const TIER_CONFIG = {
    light:     { stake: 10000,    apyMin: 0.04, apyMax: 0.06, lockDays: 7 },
    sentinel:  { stake: 100000,   apyMin: 0.07, apyMax: 0.09, lockDays: 30 },
    guardian:  { stake: 1000000,  apyMin: 0.10, apyMax: 0.12, lockDays: 90 },
    validator: { stake: 10000000, apyMin: 0.15, apyMax: 0.20, lockDays: 180 },
};

class NodeManager extends EventEmitter {
    constructor(db) {
        super();
        this.db = db; // TpixDatabase instance for reward tracking
        this.process = null;
        this.status = 'stopped'; // stopped, starting, running, syncing, error
        this.mode = 'idle';      // idle | monitoring (เฝ้าดูผ่าน RPC) | node (รันโหนดจริง)
        this.config = null;
        this.logs = [];
        this.maxLogs = 500;
        this.metricsInterval = null;
        this.statusInterval = null;
        this.rewardInterval = null;
        this.startTime = null;

        this.dataDir = path.join(os.homedir(), '.tpix-node');
        this.configPath = path.join(this.dataDir, 'config.json');

        // Ensure data dir exists
        if (!fs.existsSync(this.dataDir)) {
            fs.mkdirSync(this.dataDir, { recursive: true });
        }

        // Load saved config
        this.loadConfig();
    }

    // ─── Configuration ─────────────────────────────────────────

    loadConfig() {
        try {
            if (fs.existsSync(this.configPath)) {
                this.config = JSON.parse(fs.readFileSync(this.configPath, 'utf-8'));
            }
        } catch {
            this.config = null;
        }

        if (this.config) {
            // ── ย้ายค่าเริ่มต้นเก่าที่ค้างอยู่ในเครื่องผู้ใช้ ────────────────────────
            //
            // ผู้ใช้ที่เคยเปิดแอปมาก่อนจะมี rpcUrl เก่าฝังอยู่ใน ~/.tpix-node/config.json
            // แค่แก้ค่าคงที่ในโค้ดจึงไม่พอ — คนเก่ายังยิงไปปลายทางเดิมที่มี WAF ขวาง
            // ย้ายเฉพาะกรณีที่ค่าเดิม "เท่ากับค่าเริ่มต้นเก่าเป๊ะ" เพื่อไม่ทับค่าที่ผู้ใช้ตั้งเอง
            const saved = String(this.config.rpcUrl || '').trim().replace(/\/+$/, '');
            if (!saved || LEGACY_DEFAULTS.some(u => u.replace(/\/+$/, '') === saved)) {
                this.config.rpcUrl = TPIX_RPC;
                this._configMigrated = true;
            }

            if (Number(this.config.chainId) !== CHAIN_ID) {
                this.config.chainId = CHAIN_ID;
                this._configMigrated = true;
            }

            if (this._configMigrated) {
                try {
                    fs.writeFileSync(this.configPath, JSON.stringify(this.config, null, 2));
                } catch {
                    // เขียนไม่ได้ก็ยังใช้ค่าใหม่ในหน่วยความจำต่อไปได้
                }
            }
        }

        if (!this.config) {
            this.config = {
                nodeName: `tpix-node-${Math.random().toString(36).slice(2, 8)}`,
                tier: 'light',
                walletAddress: '',
                rewardWallet: '', // wallet address to receive node rewards (defaults to walletAddress if empty)
                // แอดเดรสสัญญา NodeRegistryV2 — ว่าง = ยังไม่ deploy
                // แอปจะกลับไปใช้โหมดประมาณการในเครื่องที่ติดป้ายไว้ว่าไม่ใช่เงินจริง
                registryAddress: '',
                rpcUrl: TPIX_RPC,
                chainId: CHAIN_ID,
                p2pPort: 30303,
                rpcPort: 8545,
                dashboardPort: 3847,
                maxPeers: 50,
                dataDir: this.dataDir,
                autoStart: false,
                bootnodes: [],
            };
        }

        // ปลายทางที่ผู้ใช้ตั้งไว้ต้องเป็นตัวเดียวกับที่ทั้งแอปใช้ (กระเป๋า/ธุรกรรม/explorer)
        setEndpoint(this.config.rpcUrl);
    }

    saveConfig(newConfig) {
        // Whitelist allowed config keys to prevent injection
        const ALLOWED = ['nodeName', 'tier', 'walletAddress', 'rewardWallet', 'registryAddress', 'rpcUrl', 'chainId', 'p2pPort', 'rpcPort', 'dashboardPort', 'maxPeers', 'autoStart', 'bootnodes'];
        if (newConfig) {
            for (const key of Object.keys(newConfig)) {
                if (ALLOWED.includes(key)) {
                    this.config[key] = newConfig[key];
                }
            }
        }
        fs.writeFileSync(this.configPath, JSON.stringify(this.config, null, 2));
        setEndpoint(this.config.rpcUrl);
    }

    getConfig() {
        return { ...this.config };
    }

    getDataDir() {
        return this.dataDir;
    }

    // ─── Preflight ก่อนเริ่มโหนดจริง ────────────────────────────

    /**
     * เข้าโหมดเฝ้าดูเชน — อ่านสถานะผ่าน RPC ได้ครบ แต่ไม่ได้ผลิตบล็อก
     *
     * ของเดิมตั้ง `this.status = 'monitoring'` แล้วเรียก setStatus('running') ทับทันที
     * ค่าที่ตั้งไว้จึงหายไปเฉยๆ หน้าจอเลยแยกไม่ออกว่ากำลัง "เฝ้าดู" หรือ "รันโหนดจริง"
     * ตอนนี้เก็บไว้คนละช่อง (mode) แล้วส่งออกไปกับ getStatus() ให้ UI บอกความจริงได้
     */
    enterMonitoringMode() {
        this.mode = 'monitoring';
        this.setStatus('running');
        this.startMonitoring();
    }

    /** ที่อยู่ของ genesis.json ที่ติดมากับตัวแอป (dev / หลัง build) */
    findBundledGenesis() {
        const candidates = [
            path.join(__dirname, '..', 'chain', 'genesis.json'),
            path.join(process.resourcesPath || '', 'chain', 'genesis.json'),
        ];

        for (const p of candidates) {
            try {
                if (fs.existsSync(p)) return p;
            } catch {}
        }

        return null;
    }

    /**
     * ทำให้มี genesis.json อยู่ใน data dir แน่ๆ — ถ้าไม่มีก็คัดจากที่ติดมากับแอป
     *
     * @returns {string|null} พาธของ genesis.json ที่ใช้ได้ หรือ null ถ้าไม่มีเลย
     */
    ensureGenesis() {
        const target = path.join(this.dataDir, 'genesis.json');

        if (fs.existsSync(target)) {
            // ไฟล์ที่ค้างอยู่อาจเป็นของเชนเก่าก่อน regenesis — เช็ค chainID ให้ตรงก่อนใช้
            try {
                const g = JSON.parse(fs.readFileSync(target, 'utf-8'));
                const id = g && g.params && Number(g.params.chainID);
                if (id && id !== CHAIN_ID) {
                    const backup = target + '.old-chain-' + id;
                    fs.renameSync(target, backup);
                    this.addLog('warn',
                        `genesis.json ที่มีอยู่เป็นของเชน ${id} ไม่ใช่ ${CHAIN_ID} — `
                        + `ย้ายไปเก็บไว้ที่ ${path.basename(backup)} แล้วใช้ของใหม่แทน`);
                } else {
                    return target;
                }
            } catch {
                this.addLog('warn', 'genesis.json ที่มีอยู่อ่านไม่ออก — จะเขียนทับด้วยของที่ติดมากับแอป');
            }
        }

        const bundled = this.findBundledGenesis();
        if (!bundled) return null;

        try {
            fs.copyFileSync(bundled, target);
            this.addLog('info', 'คัดลอก genesis.json ที่ติดมากับแอปไปไว้ที่ ' + target);

            return target;
        } catch (err) {
            this.addLog('error', 'คัดลอก genesis.json ไม่สำเร็จ: ' + err.message);

            return null;
        }
    }

    /** อ่านรายชื่อ bootnode ที่จะใช้ — ของที่ผู้ใช้ตั้งเองมาก่อน ไม่มีค่อยเอาจาก genesis */
    resolveBootnodes(genesisPath) {
        if (Array.isArray(this.config.bootnodes) && this.config.bootnodes.length > 0) {
            return this.config.bootnodes;
        }

        try {
            const g = JSON.parse(fs.readFileSync(genesisPath, 'utf-8'));

            return Array.isArray(g.bootnodes) ? g.bootnodes : [];
        } catch {
            return [];
        }
    }

    /**
     * ลองต่อ TCP ไปยัง bootnode แต่ละตัว
     *
     * multiaddr ที่รองรับ: /ip4/HOST/tcp/PORT/p2p/ID และ /dns4/HOST/tcp/PORT/p2p/ID
     * ตัวที่ชี้ชื่อ container ภายใน docker (เช่น /ip4/tpix-validator-1/...) จะต่อไม่ติด
     * จากเครื่องผู้ใช้อยู่แล้ว — ซึ่งเป็นประเด็นที่ต้องรู้ ไม่ใช่ซ่อนไว้
     */
    async probeBootnodes(genesisPath, timeoutMs = 4000) {
        const net = require('net');
        const list = this.resolveBootnodes(genesisPath);

        // ยิงพร้อมกันทุกตัว — แต่ละตัวไม่เกี่ยวกัน ถ้าไล่ทีละตัวแล้วทุกตัวหมดเวลา
        // ผู้ใช้ต้องนั่งรอ (จำนวน bootnode × timeout) วินาทีหลังกดปุ่มเริ่มโหนด
        const results = await Promise.all(list.map(async (addr) => {
            const m = /^\/(?:ip4|ip6|dns4|dns6|dns)\/([^/]+)\/tcp\/(\d+)/.exec(String(addr));
            if (!m) {
                return { addr, ok: false, error: 'รูปแบบ multiaddr ไม่ถูกต้อง' };
            }

            const host = m[1];
            const port = Number(m[2]);
            const ok = await new Promise((resolve) => {
                const sock = new net.Socket();
                let done = false;
                const finish = (val) => {
                    if (done) return;
                    done = true;
                    try { sock.destroy(); } catch {}
                    resolve(val);
                };
                sock.setTimeout(timeoutMs);
                sock.once('connect', () => finish(true));
                sock.once('timeout', () => finish(false));
                sock.once('error', () => finish(false));
                try { sock.connect(port, host); } catch { finish(false); }
            });

            return { addr, host, port, ok, error: ok ? null : 'ต่อไม่ติดภายใน ' + timeoutMs + 'ms' };
        }));

        return { reachable: results.some(r => r.ok), results };
    }

    // ─── Node Lifecycle ────────────────────────────────────────

    async start(overrideConfig) {
        if (this.process) {
            throw new Error('Node is already running');
        }

        if (overrideConfig) {
            this.saveConfig(overrideConfig);
        }

        this.setStatus('starting');
        this.startTime = Date.now();
        this._lastSavedUptime = 0;
        this.addLog('info', `Starting TPIX Master Node "${this.config.nodeName}"...`);
        this.addLog('info', `Tier: ${this.config.tier} | Chain: ${this.config.chainId}`);
        this.addLog('info', `Wallet: ${this._maskAddress(this.config.walletAddress) || 'Not set'}`);
        this.addLog('info', `Reward Wallet: ${this._maskAddress(this.config.rewardWallet || this.config.walletAddress) || 'Not set'}`);

        // Determine the binary path
        const binPath = this.findBinary();

        if (!binPath) {
            this.addLog('warn', 'ไม่พบไฟล์ polygon-edge — จะทำงานเป็นโหมดเฝ้าดูเชนอย่างเดียว');
            this.addLog('info', 'โหมดนี้อ่านสถานะเชนผ่าน RPC ได้ครบ แต่ไม่ได้ผลิตบล็อกเอง');
            this.enterMonitoringMode();
            return;
        }

        // ── genesis.json — ติดมากับตัวแอปแล้ว ไม่ต้องให้ผู้ใช้ไปหาโหลดเอง ──────────
        //
        // ของเดิมบอกว่า "ดาวน์โหลดจาก tpix.online" ซึ่ง**ไม่มีไฟล์นั้นอยู่จริง**
        // (ตรวจ 2026-08-11: /genesis.json → 404) ผู้ใช้จึงติดตายตรงนี้ 100%
        const genesisPath = this.ensureGenesis();
        if (!genesisPath) {
            this.addLog('error',
                'ไม่พบ genesis.json ทั้งในเครื่องและในตัวแอป — วางไฟล์ไว้ที่ ' + this.dataDir + ' แล้วลองใหม่');
            this.setStatus('error');
            return;
        }

        // ── ต่อเข้าเครือข่าย P2P ได้จริงไหม ────────────────────────────────────────
        //
        // ถ้า bootnode ต่อไม่ติด โหนดจะขึ้นมาแล้วนั่งเงียบไม่ sync อะไรเลย
        // ผู้ใช้เห็นสถานะ "running" แต่บล็อกไม่ขยับ แล้วเข้าใจว่าแอปพัง
        // เช็คก่อนดีกว่า แล้วบอกความจริงถ้าเข้าไม่ได้
        const probe = await this.probeBootnodes(genesisPath);
        if (!probe.reachable) {
            this.addLog('warn',
                `ต่อ bootnode ไม่ได้สักตัว (ลอง ${probe.results.length} ที่) — `
                + 'พอร์ต P2P ของเชนยังไม่ได้เปิดให้เครื่องนอกเข้า');
            probe.results.forEach(r => this.addLog('info', `  ${r.host}:${r.port} → ${r.error || 'ต่อไม่ได้'}`));
            this.addLog('warn',
                'เริ่มโหนดตอนนี้จะได้โหนดที่ไม่ sync กับใครเลย จึงเปลี่ยนเป็นโหมดเฝ้าดูเชนแทน');
            this.addLog('info',
                'ให้ผู้ดูแลเชนเปิดพอร์ต 10001-10004 ที่ firewall แล้วสั่ง polygon-edge ด้วย '
                + '--nat <ไอพีสาธารณะ> เพื่อให้โหนดจากข้างนอกเข้าร่วมได้');
            this.enterMonitoringMode();
            return;
        }

        this.addLog('info', `ต่อ bootnode ได้ ${probe.results.filter(r => r.ok).length} ตัว — เริ่มโหนดจริง`);

        // Initialize node secrets/key if not done yet
        const chainDataDir = path.join(this.dataDir, 'chain-data');
        const consensusKeyPath = path.join(chainDataDir, 'consensus', 'validator.key');
        if (!fs.existsSync(consensusKeyPath)) {
            this.addLog('info', 'Initializing node keys (first run)...');
            try {
                const { execFileSync } = require('child_process');
                execFileSync(binPath, ['secrets', 'init', '--data-dir', chainDataDir], {
                    timeout: 30000,
                    cwd: this.dataDir,
                });
                this.addLog('info', 'Node keys initialized successfully.');
            } catch (err) {
                this.addLog('error', `Failed to initialize node keys: ${err.message}`);
                this.setStatus('error');
                return;
            }
        }

        // Build command args for polygon-edge
        const args = this.buildArgs(this.resolveBootnodes(genesisPath));
        this.mode = 'node';
        this.addLog('info', `Binary: ${binPath}`);
        this.addLog('info', `Args: ${args.join(' ')}`);

        try {
            this.process = spawn(binPath, args, {
                cwd: this.dataDir,
                stdio: ['ignore', 'pipe', 'pipe'],
                env: { ...process.env },
            });

            this.process.stdout.on('data', (data) => {
                const lines = data.toString().split('\n').filter(Boolean);
                lines.forEach((line) => {
                    this.addLog('stdout', line);
                    // Detect syncing state
                    if (line.includes('syncing') || line.includes('Synchronising')) {
                        this.setStatus('syncing');
                    } else if (line.includes('Imported') || line.includes('block sealed')) {
                        this.setStatus('running');
                    }
                });
            });

            this.process.stderr.on('data', (data) => {
                const lines = data.toString().split('\n').filter(Boolean);
                lines.forEach((line) => this.addLog('stderr', line));
            });

            this.process.on('exit', (code) => {
                this.addLog('info', `Node process exited with code ${code}`);
                this.process = null;
                this.setStatus(code === 0 ? 'stopped' : 'error');
                this.stopMonitoring();
            });

            this.process.on('error', (err) => {
                this.addLog('error', `Process error: ${err.message}`);
                this.process = null;
                this.setStatus('error');
                this.stopMonitoring();
            });

            this.setStatus('running');
            this.startMonitoring();
        } catch (err) {
            this.addLog('error', `Failed to start: ${err.message}`);
            this.setStatus('error');
            throw err;
        }
    }

    async stop() {
        if (this._stopping) return; // Guard against double-call
        this._stopping = true;

        this.addLog('info', 'Stopping node...');
        this.stopMonitoring();

        if (this.process) {
            const pid = this.process.pid;
            await new Promise((resolve) => {
                let resolved = false;
                const done = () => {
                    if (resolved) return;
                    resolved = true;
                    this.process = null;
                    this.setStatus('stopped');
                    this.addLog('info', 'Node stopped.');
                    resolve();
                };

                this.process.once('exit', done);

                // Final timeout — force resolve after 20 seconds no matter what
                setTimeout(done, 20000);

                // Graceful shutdown — Windows doesn't support SIGTERM reliably
                if (os.platform() === 'win32') {
                    const { execFile } = require('child_process');
                    const safePid = String(Math.floor(Number(pid)));
                    execFile('taskkill', ['/PID', safePid, '/T'], () => {
                        // Force kill after 10 seconds if still alive
                        setTimeout(() => {
                            if (this.process) {
                                execFile('taskkill', ['/PID', safePid, '/T', '/F'], () => {});
                            }
                        }, 10000);
                    });
                } else {
                    try { this.process.kill('SIGTERM'); } catch {}
                    setTimeout(() => {
                        try { if (this.process) this.process.kill('SIGKILL'); } catch {}
                    }, 10000);
                }
            });
        }

        this.mode = 'idle';
        this.setStatus('stopped');
        this._stopping = false;
    }

    isRunning() {
        return this.status === 'running' || this.status === 'syncing' || this.status === 'starting';
    }

    // ─── Binary Management ─────────────────────────────────────

    findBinary() {
        const names = ['polygon-edge.exe', 'polygon-edge', 'tpix-node.exe', 'tpix-node'];
        const searchPaths = [
            path.join(this.dataDir, 'bin'),
            path.join(__dirname, '..', 'bin'),
            path.join(process.resourcesPath || '', 'bin'),
        ];

        for (const dir of searchPaths) {
            for (const name of names) {
                const fullPath = path.join(dir, name);
                if (fs.existsSync(fullPath)) {
                    return fullPath;
                }
            }
        }

        return null;
    }

    buildArgs(bootnodes) {
        const args = ['server'];

        args.push('--data-dir', path.join(this.dataDir, 'chain-data'));
        args.push('--chain', path.join(this.dataDir, 'genesis.json'));
        args.push('--grpc-address', `0.0.0.0:${this.config.rpcPort + 1000}`);
        args.push('--libp2p', `0.0.0.0:${this.config.p2pPort}`);
        args.push('--jsonrpc', `127.0.0.1:${this.config.rpcPort}`);
        args.push('--max-peers', String(this.config.maxPeers));
        args.push('--block-gas-target', '20000000');

        // Only real Validator-tier nodes (IBFT2 sealers) seal blocks
        // Guardian, Sentinel, Light nodes do NOT seal
        if (this.config.tier === 'validator') {
            args.push('--seal');
        }

        // ถ้าไม่ส่งมา ให้ใช้ของที่ผู้ใช้ตั้งไว้ — ส่วนของ genesis ผู้เรียกจะเตรียมมาให้
        const list = (bootnodes && bootnodes.length > 0)
            ? bootnodes
            : (this.config.bootnodes || []);

        list.forEach((bn) => {
            args.push('--bootnode', bn);
        });

        return args;
    }

    // ─── Monitoring ────────────────────────────────────────────

    startMonitoring() {
        // Poll metrics every 5 seconds
        this.metricsInterval = setInterval(() => {
            const metrics = this.getSystemMetrics();
            this.emit('metrics', metrics);
        }, 5000);

        // Poll chain status every 10 seconds
        this.statusInterval = setInterval(async () => {
            try {
                const status = await this.getFullStatus();
                this.emit('status-change', status);
            } catch {
                // RPC might not be ready yet
            }
        }, 10000);

        // Reward accrual every 60 seconds
        this.rewardInterval = setInterval(() => {
            this.accrueRewards();
        }, 60000);
        // First accrual after 30 seconds
        this._firstRewardTimeout = setTimeout(() => this.accrueRewards(), 30000);
    }

    stopMonitoring() {
        if (this.metricsInterval) {
            clearInterval(this.metricsInterval);
            this.metricsInterval = null;
        }
        if (this.statusInterval) {
            clearInterval(this.statusInterval);
            this.statusInterval = null;
        }
        if (this.rewardInterval) {
            clearInterval(this.rewardInterval);
            this.rewardInterval = null;
        }
        if (this._firstRewardTimeout) {
            clearTimeout(this._firstRewardTimeout);
            this._firstRewardTimeout = null;
        }

        // Update staking uptime when stopping
        this._updateStakingUptime();
    }

    // ─── Reward Accrual ─────────────────────────────────────────

    /**
     * Calculate and store rewards based on tier APY and uptime.
     * Rewards are calculated per-minute based on the average APY of the tier.
     * Formula: rewardPerMinute = (stake * avgAPY) / (365.25 * 24 * 60)
     *
     * ⚠️ นี่คือ **ยอดประมาณการในเครื่อง** ไม่ใช่การจ่ายเงินจริง
     * ยังไม่ได้ deploy สัญญา staking ของมาสเตอร์โหนดขึ้น TPIX Chain
     * (ดู contracts/deployed-contracts.json — contracts เป็น array ว่าง)
     * ตัวเลขที่ได้จึงลงแค่ตาราง `rewards` ใน SQLite พร้อม txHash สังเคราะห์
     * ไม่มี transaction บนเชน และเงินไม่เข้ากระเป๋าผู้ใช้
     * UI ต้องติดป้าย "ประมาณการ" ทุกที่ที่แสดงตัวเลขนี้
     */
    accrueRewards() {
        if (!this.db || !this.config) return;
        if (this.status !== 'running' && this.status !== 'syncing') return;

        try {
            const staking = this.db.getActiveStaking();
            if (!staking) return;

            const tier = TIER_CONFIG[staking.tier];
            if (!tier) return;

            const now = Math.floor(Date.now() / 1000);
            const lastRewardTime = staking.last_reward_time || Math.floor(new Date(staking.registered_at).getTime() / 1000);
            const elapsedSeconds = now - lastRewardTime;

            // Minimum 60 seconds between reward calculations
            if (elapsedSeconds < 55) return;

            // Calculate reward: stake * avgAPY * (elapsedSeconds / secondsPerYear)
            const avgAPY = (tier.apyMin + tier.apyMax) / 2;
            const stakeAmount = BigInt(staking.stake_amount);
            const SECONDS_PER_YEAR = 365.25 * 24 * 3600;

            // Calculate in wei precision: reward = stake * avgAPY * elapsed / secondsPerYear
            // Use integer math: reward = stake * (avgAPY * 1e8) * elapsed / (secondsPerYear * 1e8)
            const apyScaled = BigInt(Math.round(avgAPY * 1e8));
            const elapsedBig = BigInt(elapsedSeconds);
            const yearSecondsBig = BigInt(Math.round(SECONDS_PER_YEAR * 1e8));

            const rewardWei = (stakeAmount * apyScaled * elapsedBig) / yearSecondsBig;

            if (rewardWei <= 0n) return;

            // Get current block number for the reward record
            //
            // ถ้า RPC ตอบไม่ได้ ต้องประมาณจากเวลาที่ผ่านไป — แต่ต้องหารด้วย blockTime
            // ที่ **วัดจากเชนจริง** ไม่ใช่ค่าใน genesis (ดูคอมเมนต์ที่ BLOCK_TIME_FALLBACK)
            this.getBlockNumber().then(async blockNumber => {
                if (!blockNumber) {
                    let bt = BLOCK_TIME_FALLBACK;
                    try {
                        bt = await chainHealth.measuredBlockTime();
                    } catch {
                        // วัดไม่ได้ก็ใช้ค่าสำรอง — อย่าให้ตัววัดทำให้การจ่ายรางวัลล้ม
                    }
                    if (!Number.isFinite(bt) || bt <= 0) bt = BLOCK_TIME_FALLBACK;
                    blockNumber = staking.last_reward_block + Math.floor(elapsedSeconds / bt);
                    this.addLog('warn',
                        `RPC ตอบไม่ได้ — ประมาณ block number จาก blockTime ที่วัดได้ ${bt}s `
                        + `(ค่าใน genesis คือ ${BLOCK_TIME_FALLBACK}s)`);
                }

                // Determine which wallet gets the reward
                const rewardWalletAddress = staking.reward_wallet || staking.wallet_address;
                // Find wallet_id for the reward wallet
                let rewardWalletId = staking.wallet_id;
                if (rewardWalletAddress !== staking.wallet_address) {
                    const rw = this.db.getWalletByAddress(rewardWalletAddress);
                    if (rw) rewardWalletId = rw.id;
                }

                // Insert reward record
                this.db.insertReward({
                    walletId: rewardWalletId,
                    blockNumber,
                    amount: rewardWei.toString(),
                    timestamp: now,
                    // ไม่ใช่ tx hash จริง — ขึ้นต้น estimate- เพื่อให้แยกออกทันทีถ้ามีของจริงเข้ามาทีหลัง
                    txHash: `estimate-${staking.id}-${blockNumber}-${now}`,
                });

                // Update checkpoint
                this.db.updateStakingRewardCheckpoint(staking.id, blockNumber, now);

                // Log reward
                const rewardTpix = Number(rewardWei) / 1e18;
                this.addLog('info', `Reward estimate +${rewardTpix.toFixed(4)} TPIX (${staking.tier} tier, ${elapsedSeconds}s uptime) — local estimate, not an on-chain payout`);

                // Emit reward event to frontend
                this.emit('reward-accrued', {
                    isEstimate: true,
                    amount: rewardWei.toString(),
                    amountTpix: rewardTpix.toFixed(4),
                    blockNumber,
                    tier: staking.tier,
                    timestamp: now,
                });
            }).catch(() => {
                // If RPC fails, still calculate reward with estimated block
            });
        } catch (err) {
            this.addLog('warn', `Reward accrual error: ${err.message}`);
        }
    }

    _updateStakingUptime() {
        if (!this.db || !this.startTime) return;
        try {
            const staking = this.db.getActiveStaking();
            if (!staking) return;
            const sessionUptime = Math.floor((Date.now() - this.startTime) / 1000);
            // _lastSavedUptime tracks what we've already written to DB for this session
            const delta = sessionUptime - (this._lastSavedUptime || 0);
            if (delta <= 0) return;
            this._lastSavedUptime = sessionUptime;
            this.db.updateStakingUptime(staking.id, staking.total_uptime_seconds + delta);
        } catch {}
    }

    /**
     * Validate if a wallet has sufficient balance for staking.
     * Returns { valid, balance, required, tier }
     */
    async validateStakeBalance(walletAddress, tier) {
        const tierConfig = TIER_CONFIG[tier];
        if (!tierConfig) return { valid: false, error: 'Invalid tier' };

        try {
            const balanceHex = await this.rpcCall('eth_getBalance', [walletAddress, 'latest']);
            const balanceWei = BigInt(balanceHex);
            const requiredWei = BigInt(tierConfig.stake) * BigInt('1000000000000000000');

            return {
                valid: balanceWei >= requiredWei,
                balance: balanceWei.toString(),
                balanceTpix: Number(balanceWei / BigInt('1000000000000000')) / 1000,
                required: requiredWei.toString(),
                requiredTpix: tierConfig.stake,
                tier,
                tierConfig,
            };
        } catch (err) {
            return { valid: false, error: `RPC error: ${err.message}` };
        }
    }

    // ─── RPC Communication ─────────────────────────────────────

    /**
     * ยิง JSON-RPC ผ่านชั้นขนส่งกลาง (rpc-client.js)
     *
     * เดิมไฟล์นี้มีตัวยิง HTTP เป็นของตัวเองอีกชุด แล้วสองชุดค่อยๆ เพี้ยนจากกัน
     * จนกลายเป็นบั๊กจริง: ชุดนี้ import `BROWSER_UA` จาก rpc-client แต่ rpc-client
     * ดันไม่ได้ export ออกมา → header เป็น undefined → Node โยน
     * ERR_HTTP_INVALID_HEADER_VALUE ทุกครั้งที่เรียก แปลว่าแดชบอร์ดอ่านเชนไม่ได้เลย
     * ตอนนี้เหลือทางเดียว ทั้งแอปใช้ UA/rate limit/circuit breaker/failover ชุดเดียวกัน
     */
    async rpcCall(method, params = [], timeout = 10000) {
        return sharedRpcCall(method, params, timeout);
    }

    async getBlockNumber() {
        try {
            const hex = await this.rpcCall('eth_blockNumber');
            return parseInt(hex, 16);
        } catch {
            return 0;
        }
    }

    async getPeerCount() {
        try {
            const hex = await this.rpcCall('net_peerCount');
            return parseInt(hex, 16);
        } catch {
            return 0;
        }
    }

    async getNetworkStats() {
        try {
            const [blockHex, peerHex, chainId] = await Promise.all([
                this.rpcCall('eth_blockNumber'),
                this.rpcCall('net_peerCount').catch(() => '0x0'),
                this.rpcCall('net_version').catch(() => '4289'),
            ]);

            const blockNumber = parseInt(blockHex, 16);

            // Get latest block for timestamp
            const block = await this.rpcCall('eth_getBlockByNumber', [blockHex, false]);
            const blockTime = block ? parseInt(block.timestamp, 16) : 0;
            const blockAge = blockTime ? Math.floor(Date.now() / 1000) - blockTime : 0;

            // เชนตั้งไว้ 2 วิ/บล็อก — เผื่อไว้ 15 บล็อกก่อนจะเรียกว่า "หยุดออกบล็อก"
            // (ถ้าค้างจริงแบบ 8 ส.ค. 69 ที่ round ไต่ขึ้นเรื่อยๆ ค่านี้จะพุ่งเป็นชั่วโมง)
            //
            // ห้ามใส่เงื่อนไข `blockAge >= 0` — นาฬิกาเครื่องผู้ใช้ช้ากว่าเชนแค่วินาทีเดียว
            // อายุก็ติดลบแล้ว ซึ่งแปลว่าเชน "ใหม่กว่าที่เราคิด" ไม่ใช่เชนหยุด
            const isProducing = blockTime > 0 && blockAge < STALL_SECONDS;

            // รายชื่อ validator อ่านจาก extraData — เชนนี้ไม่มีเมธอด ibft_* ให้เรียก
            const validators = decodeValidators(block && block.extraData);

            return {
                blockNumber,
                blockTime,
                blockAge,
                isProducing,
                peerCount: parseInt(peerHex, 16),
                chainId: parseInt(chainId, 10),
                validators,
                validatorCount: validators.length,
                rpcEndpoint: getEndpoint(),
            };
        } catch (err) {
            return {
                blockNumber: 0,
                blockAge: -1,
                isProducing: false,
                peerCount: 0,
                chainId: CHAIN_ID,
                validators: [],
                validatorCount: 0,
                rpcEndpoint: getEndpoint(),
                error: err.message,
            };
        }
    }

    // ─── Status ────────────────────────────────────────────────

    getStatus() {
        return {
            status: this.status,
            // 'monitoring' = เฝ้าดูเชนผ่าน RPC · 'node' = รัน polygon-edge จริง
            mode: this.mode,
            nodeName: this.config?.nodeName,
            tier: this.config?.tier,
            wallet: this.config?.walletAddress,
            uptime: this.startTime ? Math.floor((Date.now() - this.startTime) / 1000) : 0,
            pid: this.process?.pid || null,
            rpcEndpoint: getEndpoint(),
        };
    }

    async getFullStatus() {
        const base = this.getStatus();
        const network = await this.getNetworkStats();
        return { ...base, network };
    }

    setStatus(newStatus) {
        if (this.status !== newStatus) {
            this.status = newStatus;
            this.emit('status-change', this.getStatus());
        }
    }

    // ─── Logging ───────────────────────────────────────────────

    addLog(level, message) {
        const entry = {
            time: new Date().toISOString(),
            level,
            message,
        };
        this.logs.push(entry);
        if (this.logs.length > this.maxLogs) {
            this.logs.shift();
        }
        this.emit('log', entry);
    }

    getLogs(count) {
        return this.logs.slice(-count);
    }

    // ─── System Metrics ────────────────────────────────────────

    _maskAddress(addr) {
        if (!addr || addr.length < 10) return addr;
        return addr.substring(0, 6) + '...' + addr.substring(addr.length - 4);
    }

    getSystemMetrics() {
        const cpus = os.cpus();
        const totalMem = os.totalmem();
        const freeMem = os.freemem();
        const usedMem = totalMem - freeMem;

        // Real-time CPU usage (delta between snapshots)
        let cpuUsage = 0;
        if (cpus.length > 0) {
            let totalIdle = 0, totalTick = 0;
            for (const cpu of cpus) {
                const total = Object.values(cpu.times).reduce((a, b) => a + b, 0);
                totalIdle += cpu.times.idle;
                totalTick += total;
            }
            if (this._prevCpuIdle !== undefined) {
                const idleDelta = totalIdle - this._prevCpuIdle;
                const totalDelta = totalTick - this._prevCpuTotal;
                cpuUsage = totalDelta > 0 ? Math.round(100 - (idleDelta / totalDelta) * 100) : 0;
            }
            this._prevCpuIdle = totalIdle;
            this._prevCpuTotal = totalTick;
        }

        return {
            cpu: cpuUsage,
            memoryUsed: Math.round(usedMem / 1024 / 1024),
            memoryTotal: Math.round(totalMem / 1024 / 1024),
            memoryPercent: Math.round((usedMem / totalMem) * 100),
            platform: os.platform(),
            arch: os.arch(),
            hostname: os.hostname(),
            uptime: os.uptime(),
            nodeUptime: this.startTime ? Math.floor((Date.now() - this.startTime) / 1000) : 0,
        };
    }
}

module.exports = NodeManager;
module.exports.TIER_CONFIG = TIER_CONFIG;
