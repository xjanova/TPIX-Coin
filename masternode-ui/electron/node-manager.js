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

        if (!this.config) {
            this.config = {
                nodeName: `tpix-node-${Math.random().toString(36).slice(2, 8)}`,
                tier: 'light',
                walletAddress: '',
                rewardWallet: '', // wallet address to receive node rewards (defaults to walletAddress if empty)
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
        const ALLOWED = ['nodeName', 'tier', 'walletAddress', 'rewardWallet', 'rpcUrl', 'chainId', 'p2pPort', 'rpcPort', 'dashboardPort', 'maxPeers', 'autoStart', 'bootnodes'];
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
        this._lastSavedUptime = 0;
        this.addLog('info', `Starting TPIX Master Node "${this.config.nodeName}"...`);
        this.addLog('info', `Tier: ${this.config.tier} | Chain: ${this.config.chainId}`);
        this.addLog('info', `Wallet: ${this.config.walletAddress || 'Not set'}`);
        this.addLog('info', `Reward Wallet: ${this.config.rewardWallet || this.config.walletAddress || 'Not set'}`);

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

        // Only real Validator-tier nodes (IBFT2 sealers) seal blocks
        // Guardian, Sentinel, Light nodes do NOT seal
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
            this.getBlockNumber().then(blockNumber => {
                if (!blockNumber) blockNumber = staking.last_reward_block + Math.floor(elapsedSeconds / BLOCK_TIME);

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
                    txHash: `reward-${staking.id}-${blockNumber}-${now}`,
                });

                // Update checkpoint
                this.db.updateStakingRewardCheckpoint(staking.id, blockNumber, now);

                // Log reward
                const rewardTpix = Number(rewardWei) / 1e18;
                this.addLog('info', `Reward accrued: ${rewardTpix.toFixed(4)} TPIX (${staking.tier} tier, ${elapsedSeconds}s uptime)`);

                // Emit reward event to frontend
                this.emit('reward-accrued', {
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

            // Extract validators from IBFT2 extraData using proper RLP decode
            // Layout: [0:32] vanity + RLP([validators[], proposerSeal, committedSeals[]])
            // Each validator entry can be either a bare address or a list [address, blsKey]
            let validators = [];
            if (block && block.extraData && block.extraData.length > 66) {
                try {
                    const buf = Buffer.from(block.extraData.slice(2), 'hex');
                    // RLP decoder: returns { dataStart, dataLen, totalLen }
                    const rlp = (b, p) => {
                        const x = b[p];
                        if (x <= 0x7f) return { ds: p, dl: 1, tl: 1 };
                        if (x <= 0xb7) { const l = x - 0x80; return { ds: p+1, dl: l, tl: 1+l }; }
                        if (x <= 0xbf) { const n = x-0xb7; let l=0; for(let i=0;i<n;i++) l=l*256+b[p+1+i]; return { ds: p+1+n, dl: l, tl: 1+n+l }; }
                        if (x <= 0xf7) { const l = x - 0xc0; return { ds: p+1, dl: l, tl: 1+l }; }
                        const n = x-0xf7; let l=0; for(let i=0;i<n;i++) l=l*256+b[p+1+i]; return { ds: p+1+n, dl: l, tl: 1+n+l };
                    };
                    const isList = (b, p) => b[p] >= 0xc0;

                    // Outer list → first element = validators list
                    const outer = rlp(buf, 32);
                    const valList = rlp(buf, outer.ds);
                    let pos = valList.ds;
                    const valEnd = valList.ds + valList.dl;
                    while (pos < valEnd) {
                        const item = rlp(buf, pos);
                        if (isList(buf, pos)) {
                            // Validator entry = [address, blsKey] — extract first item
                            const inner = rlp(buf, item.ds);
                            if (inner.dl === 20) {
                                validators.push('0x' + buf.slice(inner.ds, inner.ds + 20).toString('hex'));
                            }
                        } else if (item.dl === 20) {
                            // Bare address (simpler IBFT format)
                            validators.push('0x' + buf.slice(item.ds, item.ds + 20).toString('hex'));
                        }
                        pos += item.tl;
                    }
                } catch {}
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
module.exports.TIER_CONFIG = TIER_CONFIG;
