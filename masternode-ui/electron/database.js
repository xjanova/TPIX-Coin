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

const SCHEMA_VERSION = 3;
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

        // Schema v2: HD wallet + Living Identity tables
        this.db.exec(`
            CREATE TABLE IF NOT EXISTS hd_seeds (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                encrypted_mnemonic TEXT NOT NULL,
                iv TEXT NOT NULL,
                auth_tag TEXT NOT NULL,
                salt TEXT NOT NULL,
                wallet_count INTEGER DEFAULT 0,
                created_at TEXT NOT NULL
            );

            -- Identity tables are created by IdentityManager._ensureTables()

            CREATE TABLE IF NOT EXISTS node_staking (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                wallet_address TEXT NOT NULL,
                reward_wallet TEXT,
                tier TEXT NOT NULL DEFAULT 'light',
                stake_amount TEXT NOT NULL DEFAULT '0',
                node_name TEXT,
                status TEXT NOT NULL DEFAULT 'active',
                registered_at TEXT NOT NULL,
                stopped_at TEXT,
                total_uptime_seconds INTEGER DEFAULT 0,
                last_reward_block INTEGER DEFAULT 0,
                last_reward_time INTEGER DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_staking_wallet ON node_staking(wallet_id);
            CREATE INDEX IF NOT EXISTS idx_staking_status ON node_staking(status);
        `);

        // Set schema version if not exists
        const ver = this.getSetting('schema_version');
        if (!ver) {
            this.setSetting('schema_version', String(SCHEMA_VERSION));
        }
    }

    _migrate() {
        const currentVer = parseInt(this.getSetting('schema_version') || '0', 10);

        if (currentVer < 2) {
            // v2: Add HD wallet columns to wallets table
            try {
                this.db.exec(`ALTER TABLE wallets ADD COLUMN is_hd INTEGER DEFAULT 0`);
            } catch { /* column may already exist */ }
            try {
                this.db.exec(`ALTER TABLE wallets ADD COLUMN hd_index INTEGER DEFAULT -1`);
            } catch { /* column may already exist */ }
            try {
                this.db.exec(`ALTER TABLE wallets ADD COLUMN seed_id INTEGER DEFAULT NULL`);
            } catch { /* column may already exist */ }
        }

        if (currentVer < 3) {
            // v3: Node staking table (created in _initSchema)
            // Ensure it exists for upgrades from v2
            try {
                this.db.exec(`
                    CREATE TABLE IF NOT EXISTS node_staking (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                        wallet_address TEXT NOT NULL,
                        reward_wallet TEXT,
                        tier TEXT NOT NULL DEFAULT 'light',
                        stake_amount TEXT NOT NULL DEFAULT '0',
                        node_name TEXT,
                        status TEXT NOT NULL DEFAULT 'active',
                        registered_at TEXT NOT NULL,
                        stopped_at TEXT,
                        total_uptime_seconds INTEGER DEFAULT 0,
                        last_reward_block INTEGER DEFAULT 0,
                        last_reward_time INTEGER DEFAULT 0
                    );
                    CREATE INDEX IF NOT EXISTS idx_staking_wallet ON node_staking(wallet_id);
                    CREATE INDEX IF NOT EXISTS idx_staking_status ON node_staking(status);
                `);
            } catch { /* table may already exist */ }
        }

        if (currentVer < SCHEMA_VERSION) {
            this.setSetting('schema_version', String(SCHEMA_VERSION));
        }
    }

    // ─── HD Seeds ─────────────────────────────────────────────

    insertSeed({ encryptedMnemonic, iv, authTag, salt }) {
        const stmt = this.db.prepare(`
            INSERT INTO hd_seeds (encrypted_mnemonic, iv, auth_tag, salt, wallet_count, created_at)
            VALUES (?, ?, ?, ?, 0, ?)
        `);
        const result = stmt.run(encryptedMnemonic, iv, authTag, salt, new Date().toISOString());
        return result.lastInsertRowid;
    }

    getSeed(id) {
        return this.db.prepare('SELECT * FROM hd_seeds WHERE id = ?').get(id);
    }

    getDefaultSeed() {
        return this.db.prepare('SELECT * FROM hd_seeds ORDER BY id ASC LIMIT 1').get();
    }

    updateSeedWalletCount(seedId, count) {
        this.db.prepare('UPDATE hd_seeds SET wallet_count = ? WHERE id = ?').run(count, seedId);
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
        // Return as string in ether with BigInt precision
        if (total === 0n) return 0;
        const WEI = BigInt('1000000000000000000');
        const whole = total / WEI;
        const frac = total % WEI;
        const fracStr = frac.toString().padStart(18, '0').slice(0, 6).replace(/0+$/, '');
        const result = fracStr ? `${whole}.${fracStr}` : `${whole}`;
        return parseFloat(result);
    }

    // ─── Node Staking ────────────────────────────────────────────

    insertStaking({ walletId, walletAddress, rewardWallet, tier, stakeAmount, nodeName }) {
        // Deactivate any previous staking for this wallet
        this.db.prepare("UPDATE node_staking SET status = 'stopped', stopped_at = ? WHERE wallet_id = ? AND status = 'active'")
            .run(new Date().toISOString(), walletId);

        const stmt = this.db.prepare(`
            INSERT INTO node_staking (wallet_id, wallet_address, reward_wallet, tier, stake_amount, node_name, status, registered_at)
            VALUES (?, ?, ?, ?, ?, ?, 'active', ?)
        `);
        const result = stmt.run(walletId, walletAddress, rewardWallet || walletAddress, tier, stakeAmount, nodeName, new Date().toISOString());
        return result.lastInsertRowid;
    }

    getActiveStaking(walletId) {
        if (walletId) {
            return this.db.prepare("SELECT * FROM node_staking WHERE wallet_id = ? AND status = 'active' ORDER BY id DESC LIMIT 1").get(walletId);
        }
        return this.db.prepare("SELECT * FROM node_staking WHERE status = 'active' ORDER BY id DESC LIMIT 1").get();
    }

    getStakingHistory(walletId) {
        return this.db.prepare('SELECT * FROM node_staking WHERE wallet_id = ? ORDER BY id DESC LIMIT 20').all(walletId);
    }

    updateStakingUptime(stakingId, uptimeSeconds) {
        this.db.prepare('UPDATE node_staking SET total_uptime_seconds = ? WHERE id = ?').run(uptimeSeconds, stakingId);
    }

    updateStakingRewardCheckpoint(stakingId, blockNumber, timestamp) {
        this.db.prepare('UPDATE node_staking SET last_reward_block = ?, last_reward_time = ? WHERE id = ?')
            .run(blockNumber, timestamp, stakingId);
    }

    stopStaking(walletId) {
        this.db.prepare("UPDATE node_staking SET status = 'stopped', stopped_at = ? WHERE wallet_id = ? AND status = 'active'")
            .run(new Date().toISOString(), walletId);
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
