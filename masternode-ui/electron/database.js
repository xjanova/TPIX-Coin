/**
 * TPIX Master Node — SQLite Database Manager
 * Stores wallets, transaction history, rewards, and settings.
 * Uses better-sqlite3 for synchronous, fast, Electron-friendly access.
 * Developed by Xman Studio
 */

const Database = require('better-sqlite3');
const path = require('path');
const os = require('os');
const fs = require('fs');

const DATA_DIR = path.join(os.homedir(), '.tpix-node');
const DB_FILE = path.join(DATA_DIR, 'tpix-wallets.db');

const SCHEMA_VERSION = 1;
const MAX_WALLETS = 128;

class TpixDatabase {
    constructor() {
        if (!fs.existsSync(DATA_DIR)) {
            fs.mkdirSync(DATA_DIR, { recursive: true });
        }

        this.db = new Database(DB_FILE);
        this.db.pragma('journal_mode = WAL');
        this.db.pragma('foreign_keys = ON');

        this._initSchema();
        this._migrate();
    }

    // ─── Schema ─────────────────────────────────────────────────

    _initSchema() {
        this.db.exec(`
            CREATE TABLE IF NOT EXISTS wallets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                slot INTEGER UNIQUE NOT NULL,
                name TEXT NOT NULL,
                address TEXT NOT NULL UNIQUE,
                encrypted_key TEXT NOT NULL,
                iv TEXT NOT NULL,
                auth_tag TEXT NOT NULL,
                salt TEXT NOT NULL,
                chain_id INTEGER DEFAULT 4289,
                is_active INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT
            );

            CREATE TABLE IF NOT EXISTS transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                tx_hash TEXT NOT NULL UNIQUE,
                from_address TEXT NOT NULL,
                to_address TEXT NOT NULL,
                value TEXT NOT NULL,
                gas_used TEXT,
                gas_price TEXT,
                block_number INTEGER,
                block_timestamp INTEGER,
                status TEXT DEFAULT 'pending',
                direction TEXT NOT NULL,
                nonce INTEGER,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS rewards (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                block_number INTEGER,
                amount TEXT NOT NULL,
                timestamp INTEGER,
                tx_hash TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_tx_wallet ON transactions(wallet_id);
            CREATE INDEX IF NOT EXISTS idx_tx_hash ON transactions(tx_hash);
            CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(status);
            CREATE INDEX IF NOT EXISTS idx_rewards_wallet ON rewards(wallet_id);
        `);

        // Set schema version if not exists
        const ver = this.getSetting('schema_version');
        if (!ver) {
            this.setSetting('schema_version', String(SCHEMA_VERSION));
        }
    }

    _migrate() {
        const currentVer = parseInt(this.getSetting('schema_version') || '0', 10);
        if (currentVer < SCHEMA_VERSION) {
            // Future migrations go here
            this.setSetting('schema_version', String(SCHEMA_VERSION));
        }
    }

    // ─── Wallets ────────────────────────────────────────────────

    insertWallet({ slot, name, address, encryptedKey, iv, authTag, salt, isActive }) {
        const count = this.getWalletCount();
        if (count >= MAX_WALLETS) {
            throw new Error(`Maximum ${MAX_WALLETS} wallets reached`);
        }

        const stmt = this.db.prepare(`
            INSERT INTO wallets (slot, name, address, encrypted_key, iv, auth_tag, salt, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        `);
        const result = stmt.run(slot, name, address, encryptedKey, iv, authTag, salt, isActive ? 1 : 0, new Date().toISOString());
        return result.lastInsertRowid;
    }

    getWallet(id) {
        return this.db.prepare('SELECT * FROM wallets WHERE id = ?').get(id);
    }

    getWalletByAddress(address) {
        return this.db.prepare('SELECT * FROM wallets WHERE address = ?').get(address);
    }

    getActiveWallet() {
        return this.db.prepare('SELECT * FROM wallets WHERE is_active = 1').get();
    }

    listWallets() {
        return this.db.prepare('SELECT id, slot, name, address, is_active, created_at FROM wallets ORDER BY slot ASC').all();
    }

    getWalletCount() {
        const row = this.db.prepare('SELECT COUNT(*) as count FROM wallets').get();
        return row.count;
    }

    getNextSlot() {
        // Find the lowest available slot (1..128) to reuse deleted slots
        const usedSlots = this.db.prepare('SELECT slot FROM wallets ORDER BY slot ASC').all().map(r => r.slot);
        for (let i = 1; i <= MAX_WALLETS; i++) {
            if (!usedSlots.includes(i)) return i;
        }
        throw new Error(`Maximum ${MAX_WALLETS} wallets reached`);
    }

    setActiveWallet(id) {
        const tx = this.db.transaction(() => {
            this.db.prepare('UPDATE wallets SET is_active = 0').run();
            this.db.prepare('UPDATE wallets SET is_active = 1 WHERE id = ?').run(id);
        });
        tx();
    }

    renameWallet(id, newName) {
        this.db.prepare('UPDATE wallets SET name = ?, updated_at = ? WHERE id = ?')
            .run(newName, new Date().toISOString(), id);
    }

    deleteWallet(id) {
        const wallet = this.getWallet(id);
        if (!wallet) throw new Error('Wallet not found');

        const wasActive = wallet.is_active;
        this.db.prepare('DELETE FROM wallets WHERE id = ?').run(id);

        // If deleted wallet was active, activate the first remaining wallet
        if (wasActive) {
            const first = this.db.prepare('SELECT id FROM wallets ORDER BY slot ASC LIMIT 1').get();
            if (first) {
                this.setActiveWallet(first.id);
            }
        }
    }

    walletExists() {
        return this.getWalletCount() > 0;
    }

    // ─── Transactions ───────────────────────────────────────────

    insertTransaction({ walletId, txHash, fromAddress, toAddress, value, gasUsed, gasPrice, blockNumber, blockTimestamp, status, direction, nonce }) {
        const stmt = this.db.prepare(`
            INSERT OR IGNORE INTO transactions
            (wallet_id, tx_hash, from_address, to_address, value, gas_used, gas_price, block_number, block_timestamp, status, direction, nonce, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `);
        return stmt.run(walletId, txHash, fromAddress, toAddress, value, gasUsed, gasPrice, blockNumber, blockTimestamp, status, direction, nonce, new Date().toISOString());
    }

    updateTransactionStatus(txHash, status, blockNumber, blockTimestamp, gasUsed) {
        this.db.prepare(`
            UPDATE transactions SET status = ?, block_number = ?, block_timestamp = ?, gas_used = ? WHERE tx_hash = ?
        `).run(status, blockNumber, blockTimestamp, gasUsed, txHash);
    }

    getTransactions(walletId, page = 1, limit = 20) {
        const offset = (page - 1) * limit;
        const total = this.db.prepare('SELECT COUNT(*) as count FROM transactions WHERE wallet_id = ?').get(walletId);
        const rows = this.db.prepare(`
            SELECT * FROM transactions WHERE wallet_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?
        `).all(walletId, limit, offset);
        return { transactions: rows, total: total.count, page, limit };
    }

    getTransactionByHash(txHash) {
        return this.db.prepare('SELECT * FROM transactions WHERE tx_hash = ?').get(txHash);
    }

    getPendingTransactions() {
        return this.db.prepare("SELECT * FROM transactions WHERE status = 'pending'").all();
    }

    // ─── Rewards ────────────────────────────────────────────────

    insertReward({ walletId, blockNumber, amount, timestamp, txHash }) {
        this.db.prepare(`
            INSERT OR IGNORE INTO rewards (wallet_id, block_number, amount, timestamp, tx_hash, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        `).run(walletId, blockNumber, amount, timestamp, txHash, new Date().toISOString());
    }

    getRewards(walletId, limit = 50) {
        return this.db.prepare(`
            SELECT * FROM rewards WHERE wallet_id = ? ORDER BY timestamp DESC LIMIT ?
        `).all(walletId, limit);
    }

    getTotalRewards(walletId) {
        // Sum amounts as strings to avoid REAL precision loss with large wei values
        const rows = this.db.prepare('SELECT amount FROM rewards WHERE wallet_id = ?').all(walletId);
        let total = BigInt(0);
        for (const r of rows) {
            try { total += BigInt(r.amount); } catch { /* skip invalid */ }
        }
        // Return as ether (number) for display
        return Number(total) / 1e18;
    }

    // ─── Settings ───────────────────────────────────────────────

    getSetting(key) {
        const row = this.db.prepare('SELECT value FROM settings WHERE key = ?').get(key);
        return row ? row.value : null;
    }

    setSetting(key, value) {
        this.db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)').run(key, value);
    }

    // ─── Cleanup ────────────────────────────────────────────────

    close() {
        if (this.db) {
            this.db.close();
            this.db = null;
        }
    }
}

module.exports = TpixDatabase;
