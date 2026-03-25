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
const https = require('https');
const http = require('http');
const EventEmitter = require('events');

const TPIX_RPC = 'https://rpc.tpix.online';
const CHAIN_ID = 4289;
const BLOCK_TIME = 2; // seconds

class NodeManager extends EventEmitter {
    constructor() {
        super();
        this.process = null;
        this.status = 'stopped'; // stopped, starting, running, syncing, error
        this.config = null;
        this.logs = [];
        this.maxLogs = 500;
        this.metricsInterval = null;
        this.statusInterval = null;
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

        if (!this.config) {
            this.config = {
                nodeName: `tpix-node-${Math.random().toString(36).slice(2, 8)}`,
                tier: 'light',
                walletAddress: '',
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
    }

    saveConfig(newConfig) {
        // Whitelist allowed config keys to prevent injection
        const ALLOWED = ['nodeName', 'tier', 'walletAddress', 'rpcUrl', 'chainId', 'p2pPort', 'rpcPort', 'dashboardPort', 'maxPeers', 'autoStart', 'bootnodes'];
        if (newConfig) {
            for (const key of Object.keys(newConfig)) {
                if (ALLOWED.includes(key)) {
                    this.config[key] = newConfig[key];
                }
            }
        }
        fs.writeFileSync(this.configPath, JSON.stringify(this.config, null, 2));
    }

    getConfig() {
        return { ...this.config };
    }

    getDataDir() {
        return this.dataDir;
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
        this.addLog('info', `Starting TPIX Master Node "${this.config.nodeName}"...`);
        this.addLog('info', `Tier: ${this.config.tier} | Chain: ${this.config.chainId}`);
        this.addLog('info', `Wallet: ${this.config.walletAddress || 'Not set'}`);

        // Determine the binary path
        const binPath = this.findBinary();

        if (!binPath) {
            this.addLog('warn', 'Polygon Edge binary not found — running in monitoring mode only.');
            this.addLog('info', 'The node will monitor the TPIX Chain via RPC but cannot produce blocks.');
            this.status = 'monitoring';
            this.setStatus('running');
            this.startMonitoring();
            return;
        }

        // Ensure genesis.json exists
        const genesisPath = path.join(this.dataDir, 'genesis.json');
        if (!fs.existsSync(genesisPath)) {
            this.addLog('error', 'genesis.json not found. Please download it from tpix.online or place it in: ' + this.dataDir);
            this.setStatus('error');
            return;
        }

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
        const args = this.buildArgs();
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
                    const { exec } = require('child_process');
                    exec(`taskkill /PID ${pid} /T`, () => {
                        // Force kill after 10 seconds if still alive
                        setTimeout(() => {
                            if (this.process) {
                                exec(`taskkill /PID ${pid} /T /F`, () => {});
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

    buildArgs() {
        const args = ['server'];

        args.push('--data-dir', path.join(this.dataDir, 'chain-data'));
        args.push('--chain', path.join(this.dataDir, 'genesis.json'));
        args.push('--grpc-address', `0.0.0.0:${this.config.rpcPort + 1000}`);
        args.push('--libp2p', `0.0.0.0:${this.config.p2pPort}`);
        args.push('--jsonrpc', `127.0.0.1:${this.config.rpcPort}`);
        args.push('--max-peers', String(this.config.maxPeers));
        args.push('--block-gas-target', '20000000');

        // Only validators seal blocks
        if (this.config.tier === 'validator') {
            args.push('--seal');
        }

        if (this.config.bootnodes && this.config.bootnodes.length > 0) {
            this.config.bootnodes.forEach((bn) => {
                args.push('--bootnode', bn);
            });
        }

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
    }

    // ─── RPC Communication ─────────────────────────────────────

    async rpcCall(method, params = []) {
        const rpcUrl = this.config.rpcUrl || TPIX_RPC;

        return new Promise((resolve, reject) => {
            const url = new URL(rpcUrl);
            const isHttps = url.protocol === 'https:';
            const client = isHttps ? https : http;

            const body = JSON.stringify({
                jsonrpc: '2.0',
                method,
                params,
                id: Date.now(),
            });

            const req = client.request(
                {
                    hostname: url.hostname,
                    port: url.port || (isHttps ? 443 : 80),
                    path: url.pathname,
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Content-Length': Buffer.byteLength(body),
                    },
                    timeout: 10000,
                },
                (res) => {
                    let data = '';
                    res.on('data', (chunk) => (data += chunk));
                    res.on('end', () => {
                        try {
                            const json = JSON.parse(data);
                            if (json.error) {
                                reject(new Error(json.error.message));
                            } else {
                                resolve(json.result);
                            }
                        } catch (e) {
                            reject(new Error('Invalid JSON response'));
                        }
                    });
                }
            );

            req.on('error', reject);
            req.on('timeout', () => {
                req.destroy();
                reject(new Error('RPC timeout'));
            });
            req.write(body);
            req.end();
        });
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
            const isProducing = blockAge < 30;

            // Extract validators from extraData
            let validators = [];
            if (block && block.extraData) {
                const extraHex = block.extraData.slice(2);
                let idx = extraHex.indexOf('94', 64);
                while (idx !== -1 && idx < extraHex.length - 40 && validators.length < 20) {
                    const addr = '0x' + extraHex.slice(idx + 2, idx + 42);
                    if (/^0x[0-9a-f]{40}$/.test(addr)) {
                        validators.push(addr);
                    }
                    idx = extraHex.indexOf('94', idx + 42);
                }
            }

            return {
                blockNumber,
                blockTime,
                blockAge,
                isProducing,
                peerCount: parseInt(peerHex, 16),
                chainId: parseInt(chainId, 10),
                validators,
                validatorCount: validators.length,
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
                error: err.message,
            };
        }
    }

    // ─── Status ────────────────────────────────────────────────

    getStatus() {
        return {
            status: this.status,
            nodeName: this.config?.nodeName,
            tier: this.config?.tier,
            wallet: this.config?.walletAddress,
            uptime: this.startTime ? Math.floor((Date.now() - this.startTime) / 1000) : 0,
            pid: this.process?.pid || null,
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
