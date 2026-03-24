/**
 * TPIX Master Node — Built-in Wallet Manager
 * Creates, imports, and manages an Ethereum-compatible wallet
 * for staking and node registration on TPIX Chain.
 * Developed by Xman Studio
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');
const http = require('http');

const TPIX_RPC = 'https://rpc.tpix.online';
const DATA_DIR = path.join(os.homedir(), '.tpix-node');
const WALLET_FILE = path.join(DATA_DIR, 'wallet.json');

class WalletManager {
    constructor() {
        this.address = null;
        this.privateKey = null;
        this.mnemonic = null;
        this._loaded = false;
    }

    /**
     * Check if a wallet file exists.
     */
    exists() {
        return fs.existsSync(WALLET_FILE);
    }

    /**
     * Create a new wallet (random private key).
     * @param {string} password - User-supplied password for encryption
     * Returns { address, privateKey }
     */
    create(password = '') {
        const privKeyBytes = crypto.randomBytes(32);
        const privateKey = '0x' + privKeyBytes.toString('hex');
        const address = this._privateKeyToAddress(privKeyBytes);

        this.privateKey = privateKey;
        this.address = address;
        this._loaded = true;

        this._save(password);

        return {
            address,
            privateKey,
            created: true,
        };
    }

    /**
     * Import wallet from private key.
     */
    importFromKey(privateKey, password = '') {
        if (!privateKey.startsWith('0x')) {
            privateKey = '0x' + privateKey;
        }

        if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
            throw new Error('Invalid private key format (must be 64 hex characters)');
        }

        const privKeyBytes = Buffer.from(privateKey.slice(2), 'hex');
        const address = this._privateKeyToAddress(privKeyBytes);

        this.privateKey = privateKey;
        this.address = address;
        this._loaded = true;

        this._save(password || '');

        return { address, imported: true };
    }

    /**
     * Get the wallet address.
     */
    getAddress() {
        this._ensureLoaded();
        return this.address;
    }

    /**
     * Get wallet balance from TPIX Chain RPC.
     */
    async getBalance() {
        this._ensureLoaded();
        if (!this.address) return '0';

        try {
            const result = await this._rpcCall('eth_getBalance', [this.address, 'latest']);
            const { ethers } = require('ethers');
            return parseFloat(ethers.formatEther(result)).toFixed(4);
        } catch {
            return '0';
        }
    }

    /**
     * Export private key — requires password.
     */
    exportKey(password = '') {
        this._ensureLoaded(password);
        return this.privateKey;
    }

    /**
     * Load wallet from file.
     */
    _ensureLoaded(password = '') {
        if (this._loaded) return;

        if (fs.existsSync(WALLET_FILE)) {
            try {
                const data = JSON.parse(fs.readFileSync(WALLET_FILE, 'utf-8'));
                this.address = data.address;

                if (data.encryptedKey) {
                    const key = this._deriveKey(password, data.salt);
                    const decipher = crypto.createDecipheriv(
                        'aes-256-gcm',
                        key,
                        Buffer.from(data.iv, 'hex')
                    );
                    decipher.setAuthTag(Buffer.from(data.authTag, 'hex'));
                    let decrypted = decipher.update(data.encryptedKey, 'hex', 'utf8');
                    decrypted += decipher.final('utf8');
                    this.privateKey = decrypted;
                }

                this._loaded = true;
            } catch (err) {
                console.error('Failed to load wallet:', err.message);
                // Wrong password will throw "Unsupported state or unable to authenticate data"
                throw new Error('Failed to decrypt wallet. Wrong password?');
            }
        }
    }

    /**
     * Save wallet to encrypted file with password-based encryption.
     */
    _save(password = '') {
        if (!fs.existsSync(DATA_DIR)) {
            fs.mkdirSync(DATA_DIR, { recursive: true });
        }

        // Generate random salt for PBKDF2
        const salt = crypto.randomBytes(32).toString('hex');
        const key = this._deriveKey(password, salt);
        const iv = crypto.randomBytes(12);
        const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

        let encrypted = cipher.update(this.privateKey, 'utf8', 'hex');
        encrypted += cipher.final('hex');
        const authTag = cipher.getAuthTag();

        const walletData = {
            address: this.address,
            encryptedKey: encrypted,
            iv: iv.toString('hex'),
            authTag: authTag.toString('hex'),
            salt: salt,
            createdAt: new Date().toISOString(),
            chainId: 4289,
        };

        fs.writeFileSync(WALLET_FILE, JSON.stringify(walletData, null, 2), { mode: 0o600 });
    }

    /**
     * Derive encryption key using PBKDF2 with user password + machine salt.
     * 100,000 iterations for brute-force resistance.
     */
    _deriveKey(password = '', salt = '') {
        const machineId = os.hostname() + os.userInfo().username;
        const combined = password + ':' + machineId + ':' + salt;
        return crypto.pbkdf2Sync(combined, 'tpix-node-wallet:' + salt, 100000, 32, 'sha256');
    }

    /**
     * Derive Ethereum address from private key.
     * Uses ethers.js Wallet for correct Keccak-256 hashing.
     * NOTE: Do NOT use crypto.createHash('sha3-256') — Ethereum uses Keccak-256,
     * which is different from NIST SHA3-256.
     */
    _privateKeyToAddress(privKeyBytes) {
        const { ethers } = require('ethers');
        const privateKey = '0x' + privKeyBytes.toString('hex');
        const wallet = new ethers.Wallet(privateKey);
        return wallet.address.toLowerCase();
    }

    /**
     * Make an RPC call to TPIX Chain.
     */
    _rpcCall(method, params = []) {
        return new Promise((resolve, reject) => {
            const url = new URL(TPIX_RPC);
            const client = url.protocol === 'https:' ? https : http;

            const body = JSON.stringify({
                jsonrpc: '2.0',
                method,
                params,
                id: Date.now(),
            });

            const req = client.request(
                {
                    hostname: url.hostname,
                    port: url.port || (url.protocol === 'https:' ? 443 : 80),
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
                    res.on('data', (c) => (data += c));
                    res.on('end', () => {
                        try {
                            const json = JSON.parse(data);
                            json.error ? reject(new Error(json.error.message)) : resolve(json.result);
                        } catch {
                            reject(new Error('Invalid response'));
                        }
                    });
                }
            );
            req.on('error', reject);
            req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
            req.write(body);
            req.end();
        });
    }
}

module.exports = WalletManager;
