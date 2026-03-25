/**
 * TPIX Master Node — Multi-Wallet Manager
 * Supports up to 128 wallets with SQLite persistence.
 * Each wallet is encrypted with AES-256-GCM (password + machine ID + salt).
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

class WalletManager {
    constructor(database) {
        this.db = database;
        this._migrateOldWallet();
    }

    // ─── Migration from wallet.json ─────────────────────────────

    _migrateOldWallet() {
        if (!fs.existsSync(OLD_WALLET_FILE)) return;
        if (this.db.getWalletCount() > 0) return; // Already migrated

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
                // Backup old file
                fs.renameSync(OLD_WALLET_FILE, OLD_WALLET_FILE + '.bak');
                console.log('[Wallet] Migrated wallet.json to SQLite (slot 1)');
            }
        } catch (err) {
            console.error('[Wallet] Migration failed:', err.message);
        }
    }

    // ─── Create / Import ────────────────────────────────────────

    /**
     * Create a new wallet.
     * @param {string} password
     * @param {string} [name]
     * @returns {{ id, slot, name, address, privateKey }}
     */
    create(password = '', name) {
        const count = this.db.getWalletCount();
        if (count >= MAX_WALLETS) {
            throw new Error(`Maximum ${MAX_WALLETS} wallets reached`);
        }

        const privKeyBytes = crypto.randomBytes(32);
        const privateKey = '0x' + privKeyBytes.toString('hex');
        const address = this._privateKeyToAddress(privKeyBytes);
        const slot = this.db.getNextSlot();
        const walletName = name || `Wallet ${slot}`;

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

        if (isFirst) {
            this.db.setActiveWallet(id);
        }

        return { id, slot, name: walletName, address, privateKey };
    }

    /**
     * Import wallet from private key.
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

        // Check duplicate
        const existing = this.db.getWalletByAddress(address);
        if (existing) {
            throw new Error('This wallet is already imported (slot ' + existing.slot + ')');
        }

        const slot = this.db.getNextSlot();
        const walletName = name || `Wallet ${slot}`;
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

        return { id, slot, name: walletName, address, imported: true };
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

        // Verify password by attempting decryption
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

    /**
     * Get balances for all wallets (batched to avoid rate-limiting).
     */
    async getBalances() {
        const wallets = this.db.listWallets();
        const results = {};
        const { ethers } = require('ethers');

        // Batch in groups of 5
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
            // Small delay between batches
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

    _encrypt(privateKey, password = '') {
        const salt = crypto.randomBytes(32).toString('hex');
        const key = this._deriveKey(password, salt);
        const iv = crypto.randomBytes(12);
        const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

        let encrypted = cipher.update(privateKey, 'utf8', 'hex');
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
        try {
            const key = this._deriveKey(password, walletRow.salt);
            const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(walletRow.iv, 'hex'));
            decipher.setAuthTag(Buffer.from(walletRow.auth_tag, 'hex'));
            let decrypted = decipher.update(walletRow.encrypted_key, 'hex', 'utf8');
            decrypted += decipher.final('utf8');
            return decrypted;
        } catch {
            throw new Error('Failed to decrypt wallet. Wrong password?');
        }
    }

    _deriveKey(password = '', salt = '') {
        const machineId = os.hostname() + os.userInfo().username;
        const combined = password + ':' + machineId + ':' + salt;
        return crypto.pbkdf2Sync(combined, 'tpix-node-wallet:' + salt, 100000, 32, 'sha256');
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
