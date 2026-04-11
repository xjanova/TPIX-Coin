/**
 * TPIX Master Node — Multi-Wallet Manager (HD + Living Identity)
 * Supports up to 128 wallets with BIP-39 HD derivation + SQLite persistence.
 * Each wallet is encrypted with AES-256-GCM (password + machine ID + salt).
 *
 * HD Path: m/44'/4289'/0'/0/{index}
 * Chain ID: 4289 (TPIX Chain)
 *
 * Developed by Xman Studio
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { rpcCall } = require('./rpc-client');

const DATA_DIR = path.join(os.homedir(), '.tpix-node');
const OLD_WALLET_FILE = path.join(DATA_DIR, 'wallet.json');
const MAX_WALLETS = 128;
const HD_PATH_PREFIX = "m/44'/4289'/0'/0/";

class WalletManager {
    constructor(database) {
        this.db = database;
        this._migrateOldWallet();
    }

    // ─── Migration from wallet.json ─────────────────────────────

    _migrateOldWallet() {
        if (!fs.existsSync(OLD_WALLET_FILE)) return;
        if (this.db.getWalletCount() > 0) return;

        try {
            const data = JSON.parse(fs.readFileSync(OLD_WALLET_FILE, 'utf-8'));
            if (data.address && data.encryptedKey) {
                this.db.insertWallet({
                    slot: 1,
                    name: 'Wallet 1',
                    address: data.address,
                    encryptedKey: data.encryptedKey,
                    iv: data.iv,
                    authTag: data.authTag,
                    salt: data.salt,
                    isActive: true,
                });
                fs.renameSync(OLD_WALLET_FILE, OLD_WALLET_FILE + '.bak');
                console.log('[Wallet] Migrated wallet.json to SQLite (slot 1)');
            }
        } catch (err) {
            console.error('[Wallet] Migration failed:', err.message);
        }
    }

    // ─── HD Wallet (BIP-39 / BIP-44) ─────────────────────────

    /**
     * Initialize HD wallet with a new mnemonic seed.
     * @param {string} password - Master password to encrypt the seed
     * @returns {{ mnemonic: string, seedId: number }}
     */
    initHDWallet(password = '') {
        if (!password || password.length === 0) {
            throw new Error('Password is required to create a wallet');
        }
        const existing = this.db.getDefaultSeed();
        if (existing) {
            throw new Error('HD wallet already initialized. Use createFromSeed() to add wallets.');
        }

        const { ethers } = require('ethers');
        const wallet = ethers.Wallet.createRandom();
        const mnemonic = wallet.mnemonic.phrase;

        // Encrypt and store seed
        const { encryptedKey, iv, authTag, salt } = this._encrypt(mnemonic, password);
        const seedId = this.db.insertSeed({
            encryptedMnemonic: encryptedKey,
            iv,
            authTag,
            salt,
        });

        console.log('[Wallet] HD wallet initialized (seed ID:', seedId, ')');
        return { mnemonic, seedId };
    }

    /**
     * Create a new wallet derived from HD seed.
     * @param {string} password - Master password
     * @param {string} [name] - Wallet name
     * @returns {{ id, slot, name, address, hdIndex, mnemonic? }}
     */
    createFromSeed(password = '', name) {
        if (!password || password.length === 0) {
            throw new Error('Password is required to create a wallet');
        }
        const count = this.db.getWalletCount();
        if (count >= MAX_WALLETS) {
            throw new Error(`Maximum ${MAX_WALLETS} wallets reached`);
        }

        let seed = this.db.getDefaultSeed();
        let mnemonic;
        let isNewSeed = false;

        if (!seed) {
            // First wallet — create HD seed
            const result = this.initHDWallet(password);
            mnemonic = result.mnemonic;
            seed = this.db.getDefaultSeed();
            isNewSeed = true;
        } else {
            // Decrypt existing seed
            mnemonic = this._decryptSeed(seed, password);
        }

        const { ethers } = require('ethers');
        const hdIndex = seed.wallet_count;
        const hdPath = HD_PATH_PREFIX + hdIndex;
        const hdNode = ethers.HDNodeWallet.fromPhrase(mnemonic, '', hdPath);

        const privateKey = hdNode.privateKey;
        const address = hdNode.address.toLowerCase();

        // Check duplicate
        const existing = this.db.getWalletByAddress(address);
        if (existing) {
            throw new Error('This wallet already exists (slot ' + existing.slot + ')');
        }

        const slot = this.db.getNextSlot();
        const walletName = name || `Wallet ${slot}`;
        const encrypted = this._encrypt(privateKey, password);
        const isFirst = count === 0;

        const id = this.db.insertWallet({
            slot,
            name: walletName,
            address,
            encryptedKey: encrypted.encryptedKey,
            iv: encrypted.iv,
            authTag: encrypted.authTag,
            salt: encrypted.salt,
            isActive: isFirst,
        });

        // Mark as HD wallet
        try {
            this.db.db.prepare('UPDATE wallets SET is_hd = 1, hd_index = ?, seed_id = ? WHERE id = ?')
                .run(hdIndex, seed.id, id);
        } catch { /* columns may not exist yet */ }

        // Update seed wallet count
        this.db.updateSeedWalletCount(seed.id, hdIndex + 1);

        if (isFirst) {
            this.db.setActiveWallet(id);
        }

        const result = { id, slot, name: walletName, address, hdIndex, isHD: true };
        if (isNewSeed) {
            result.mnemonic = mnemonic;
            result.privateKey = privateKey;
        }
        return result;
    }

    /**
     * Recover all HD wallets from a mnemonic phrase.
     * @param {string} mnemonic - 12/24 word seed phrase
     * @param {string} password - Password to encrypt wallets
     * @param {number} [scanCount=10] - How many addresses to scan
     * @returns {{ recovered: number, wallets: Array }}
     */
    async recoverFromMnemonic(mnemonic, password = '', scanCount = 10) {
        const { ethers } = require('ethers');

        // Validate mnemonic
        if (!ethers.Mnemonic.isValidMnemonic(mnemonic)) {
            throw new Error('Invalid mnemonic phrase');
        }

        // Store encrypted seed
        let seed = this.db.getDefaultSeed();
        if (!seed) {
            const encrypted = this._encrypt(mnemonic, password);
            this.db.insertSeed({
                encryptedMnemonic: encrypted.encryptedKey,
                iv: encrypted.iv,
                authTag: encrypted.authTag,
                salt: encrypted.salt,
            });
            seed = this.db.getDefaultSeed();
        }

        const recovered = [];
        let maxIndex = 0;

        for (let i = 0; i < scanCount; i++) {
            const hdPath = HD_PATH_PREFIX + i;
            const hdNode = ethers.HDNodeWallet.fromPhrase(mnemonic, '', hdPath);
            const address = hdNode.address.toLowerCase();

            // Check if already exists
            const existing = this.db.getWalletByAddress(address);
            if (existing) continue;

            // Check if address has balance or transactions
            let hasActivity = false;
            try {
                const balance = await this._rpcCall('eth_getBalance', [address, 'latest']);
                hasActivity = balance && balance !== '0x0';
            } catch { }

            if (!hasActivity && i >= 3 && recovered.length === 0) {
                // No activity found in first 3 addresses and nothing recovered, stop
                break;
            }

            if (hasActivity || i < 3) {
                const slot = this.db.getNextSlot();
                const encrypted = this._encrypt(hdNode.privateKey, password);
                const isFirst = this.db.getWalletCount() === 0;

                const id = this.db.insertWallet({
                    slot,
                    name: `Wallet ${slot}`,
                    address,
                    encryptedKey: encrypted.encryptedKey,
                    iv: encrypted.iv,
                    authTag: encrypted.authTag,
                    salt: encrypted.salt,
                    isActive: isFirst,
                });

                try {
                    this.db.db.prepare('UPDATE wallets SET is_hd = 1, hd_index = ?, seed_id = ? WHERE id = ?')
                        .run(i, seed.id, id);
                } catch { }

                if (isFirst) this.db.setActiveWallet(id);
                maxIndex = Math.max(maxIndex, i);
                recovered.push({ id, slot, address, hdIndex: i });
            }
        }

        this.db.updateSeedWalletCount(seed.id, maxIndex + 1);
        return { recovered: recovered.length, wallets: recovered };
    }

    /**
     * Get the mnemonic phrase (requires password).
     */
    getMnemonic(password = '') {
        const seed = this.db.getDefaultSeed();
        if (!seed) return null;
        return this._decryptSeed(seed, password);
    }

    /**
     * Check if HD wallet is initialized
     */
    hasHDSeed() {
        return !!this.db.getDefaultSeed();
    }

    // ─── Create / Import (legacy + HD) ──────────────────────────

    /**
     * Create a new wallet. Uses HD derivation if seed exists, otherwise creates HD seed first.
     */
    create(password = '', name) {
        return this.createFromSeed(password, name);
    }

    /**
     * Import wallet from private key (standalone, not HD).
     */
    importFromKey(privateKey, password = '', name) {
        const count = this.db.getWalletCount();
        if (count >= MAX_WALLETS) {
            throw new Error(`Maximum ${MAX_WALLETS} wallets reached`);
        }

        if (!privateKey.startsWith('0x')) privateKey = '0x' + privateKey;
        if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) {
            throw new Error('Invalid private key format (must be 64 hex characters)');
        }

        const privKeyBytes = Buffer.from(privateKey.slice(2), 'hex');
        const address = this._privateKeyToAddress(privKeyBytes);

        const existing = this.db.getWalletByAddress(address);
        if (existing) {
            throw new Error('This wallet is already imported (slot ' + existing.slot + ')');
        }

        const slot = this.db.getNextSlot();
        const walletName = name || `Imported ${slot}`;
        const { encryptedKey, iv, authTag, salt } = this._encrypt(privateKey, password);
        const isFirst = count === 0;

        const id = this.db.insertWallet({
            slot,
            name: walletName,
            address,
            encryptedKey,
            iv,
            authTag,
            salt,
            isActive: isFirst,
        });

        if (isFirst) this.db.setActiveWallet(id);

        return { id, slot, name: walletName, address, imported: true, isHD: false };
    }

    // ─── Wallet Management ──────────────────────────────────────

    listWallets() {
        return this.db.listWallets();
    }

    getWalletCount() {
        return this.db.getWalletCount();
    }

    getActiveWallet() {
        return this.db.getActiveWallet();
    }

    switchWallet(walletId) {
        const wallet = this.db.getWallet(walletId);
        if (!wallet) throw new Error('Wallet not found');
        this.db.setActiveWallet(walletId);
    }

    renameWallet(walletId, newName) {
        if (!newName || newName.trim().length === 0) throw new Error('Name cannot be empty');
        if (newName.length > 50) throw new Error('Name too long (max 50 chars)');
        this.db.renameWallet(walletId, newName.trim());
    }

    deleteWallet(walletId, password = '') {
        const wallet = this.db.getWallet(walletId);
        if (!wallet) throw new Error('Wallet not found');
        this._decrypt(wallet, password);
        this.db.deleteWallet(walletId);
    }

    // ─── Backward-compatible methods ────────────────────────────

    exists() {
        return this.db.walletExists();
    }

    getAddress() {
        const wallet = this.db.getActiveWallet();
        return wallet ? wallet.address : null;
    }

    async getBalance(walletId) {
        let address;
        if (walletId) {
            const wallet = this.db.getWallet(walletId);
            address = wallet ? wallet.address : null;
        } else {
            address = this.getAddress();
        }

        if (!address) return '0';

        try {
            const result = await this._rpcCall('eth_getBalance', [address, 'latest']);
            const { ethers } = require('ethers');
            return parseFloat(ethers.formatEther(result)).toFixed(4);
        } catch {
            return '0';
        }
    }

    async getBalances() {
        const wallets = this.db.listWallets();
        const results = {};
        const { ethers } = require('ethers');

        for (let i = 0; i < wallets.length; i += 5) {
            const batch = wallets.slice(i, i + 5);
            const promises = batch.map(async (w) => {
                try {
                    const hex = await this._rpcCall('eth_getBalance', [w.address, 'latest']);
                    return { address: w.address, balance: parseFloat(ethers.formatEther(hex)).toFixed(4) };
                } catch {
                    return { address: w.address, balance: '0' };
                }
            });
            const batchResults = await Promise.all(promises);
            for (const r of batchResults) {
                results[r.address] = r.balance;
            }
            if (i + 5 < wallets.length) {
                await new Promise(r => setTimeout(r, 300));
            }
        }

        return results;
    }

    exportKey(walletId, password = '') {
        let wallet;
        if (walletId) {
            wallet = this.db.getWallet(walletId);
        } else {
            wallet = this.db.getActiveWallet();
        }
        if (!wallet) throw new Error('Wallet not found');
        return this._decrypt(wallet, password);
    }

    // ─── QR Code ────────────────────────────────────────────────

    async generateQR(walletId) {
        let address;
        if (walletId) {
            const wallet = this.db.getWallet(walletId);
            address = wallet ? wallet.address : null;
        } else {
            address = this.getAddress();
        }
        if (!address) throw new Error('No wallet found');

        const QRCode = require('qrcode');
        const uri = `ethereum:${address}@4289`;
        return QRCode.toDataURL(uri, { width: 280, margin: 2, color: { dark: '#00BCD4', light: '#0a0e1a' } });
    }

    // ─── Encryption ─────────────────────────────────────────────

    _encrypt(data, password = '') {
        const salt = crypto.randomBytes(32).toString('hex');
        const key = this._deriveKey(password, salt);
        const iv = crypto.randomBytes(12);
        const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

        let encrypted = cipher.update(data, 'utf8', 'hex');
        encrypted += cipher.final('hex');
        const authTag = cipher.getAuthTag();

        return {
            encryptedKey: encrypted,
            iv: iv.toString('hex'),
            authTag: authTag.toString('hex'),
            salt,
        };
    }

    _decrypt(walletRow, password = '') {
        // Try current iteration count (600K) first
        try {
            const key = this._deriveKey(password, walletRow.salt, 600000);
            const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(walletRow.iv, 'hex'));
            decipher.setAuthTag(Buffer.from(walletRow.auth_tag, 'hex'));
            let decrypted = decipher.update(walletRow.encrypted_key, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            return decrypted;
        } catch {
            // Fall back to legacy iteration count (100K) for pre-upgrade wallets
            try {
                const legacyKey = this._deriveKey(password, walletRow.salt, 100000);
                const decipher = crypto.createDecipheriv('aes-256-gcm', legacyKey, Buffer.from(walletRow.iv, 'hex'));
                decipher.setAuthTag(Buffer.from(walletRow.auth_tag, 'hex'));
                let decrypted = decipher.update(walletRow.encrypted_key, 'hex', 'utf8');
                decrypted += decipher.final('utf8');

                // Auto-migrate: re-encrypt with stronger iterations
                const upgraded = this._encrypt(decrypted, password);
                try {
                    this.db.db.prepare(
                        'UPDATE wallets SET encrypted_key = ?, iv = ?, auth_tag = ?, salt = ? WHERE id = ?'
                    ).run(upgraded.encryptedKey, upgraded.iv, upgraded.authTag, upgraded.salt, walletRow.id);
                    console.log('[Wallet] Migrated wallet', walletRow.id, 'to 600K PBKDF2 iterations');
                } catch { /* migration is best-effort */ }

                return decrypted;
            } catch {
                throw new Error('Failed to decrypt wallet. Wrong password?');
            }
        }
    }

    _decryptSeed(seedRow, password = '') {
        // Try current iteration count (600K) first
        try {
            const key = this._deriveKey(password, seedRow.salt, 600000);
            const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(seedRow.iv, 'hex'));
            decipher.setAuthTag(Buffer.from(seedRow.auth_tag, 'hex'));
            let decrypted = decipher.update(seedRow.encrypted_mnemonic, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            return decrypted;
        } catch {
            // Fall back to legacy iteration count (100K) for pre-upgrade seeds
            try {
                const legacyKey = this._deriveKey(password, seedRow.salt, 100000);
                const decipher = crypto.createDecipheriv('aes-256-gcm', legacyKey, Buffer.from(seedRow.iv, 'hex'));
                decipher.setAuthTag(Buffer.from(seedRow.auth_tag, 'hex'));
                let decrypted = decipher.update(seedRow.encrypted_mnemonic, 'hex', 'utf8');
                decrypted += decipher.final('utf8');

                // Auto-migrate: re-encrypt with stronger iterations
                const upgraded = this._encrypt(decrypted, password);
                try {
                    this.db.db.prepare(
                        'UPDATE hd_seeds SET encrypted_mnemonic = ?, iv = ?, auth_tag = ?, salt = ? WHERE id = ?'
                    ).run(upgraded.encryptedKey, upgraded.iv, upgraded.authTag, upgraded.salt, seedRow.id);
                    console.log('[Wallet] Migrated seed', seedRow.id, 'to 600K PBKDF2 iterations');
                } catch { /* migration is best-effort */ }

                return decrypted;
            } catch {
                throw new Error('Failed to decrypt seed. Wrong password?');
            }
        }
    }

    _deriveKey(password = '', salt = '', iterations = 600000) {
        const machineId = os.hostname() + os.userInfo().username;
        const combined = password + ':' + machineId + ':' + salt;
        return crypto.pbkdf2Sync(combined, 'tpix-node-wallet:' + salt, iterations, 32, 'sha256');
    }

    _privateKeyToAddress(privKeyBytes) {
        const { ethers } = require('ethers');
        const privateKey = '0x' + privKeyBytes.toString('hex');
        const wallet = new ethers.Wallet(privateKey);
        return wallet.address.toLowerCase();
    }

    // ─── RPC ────────────────────────────────────────────────────

    _rpcCall(method, params = []) {
        return rpcCall(method, params, 10000);
    }
}

module.exports = WalletManager;
