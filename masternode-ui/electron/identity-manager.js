/**
 * TPIX Living Identity Manager
 * "ยิ่งใช้ ยิ่งปลอดภัย — ลืมได้ แต่ chain จำให้"
 *
 * Layer 1: Knowledge Proof (Security Questions + Recovery Key)
 * Layer 2: Chain Proof (Transaction History Quiz)
 * Layer 3: Time Lock (48h-7d recovery delay)
 * Layer 4: Social Proof (Guardian wallets - future)
 *
 * Developed by Xman Studio
 */

const crypto = require('crypto');

class IdentityManager {
    constructor(database) {
        this.db = database;
        this._ensureTables();
    }

    _ensureTables() {
        this.db.db.exec(`
            CREATE TABLE IF NOT EXISTS security_questions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                question_index INTEGER NOT NULL,
                question_text TEXT NOT NULL,
                answer_hash TEXT NOT NULL,
                answer_salt TEXT NOT NULL,
                created_at TEXT NOT NULL,
                UNIQUE(wallet_id, question_index)
            );

            CREATE TABLE IF NOT EXISTS recovery_keys (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL UNIQUE REFERENCES wallets(id) ON DELETE CASCADE,
                key_hash TEXT NOT NULL,
                key_salt TEXT NOT NULL,
                hint TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS identity_anchors (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                anchor_type TEXT NOT NULL,
                anchor_hash TEXT NOT NULL,
                anchor_salt TEXT NOT NULL,
                metadata TEXT,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS recovery_requests (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                request_type TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                layers_passed TEXT DEFAULT '[]',
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                completed_at TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_sq_wallet ON security_questions(wallet_id);
            CREATE INDEX IF NOT EXISTS idx_rk_wallet ON recovery_keys(wallet_id);
            CREATE INDEX IF NOT EXISTS idx_ia_wallet ON identity_anchors(wallet_id);
            CREATE INDEX IF NOT EXISTS idx_rr_wallet ON recovery_requests(wallet_id);
        `);
    }

    // ─── Security Questions (Layer 1) ──────────────────────

    /**
     * Set security questions for a wallet.
     * @param {number} walletId
     * @param {Array<{question: string, answer: string}>} questions - 5 Q&A pairs
     */
    setSecurityQuestions(walletId, questions) {
        if (!Array.isArray(questions) || questions.length < 3 || questions.length > 5) {
            throw new Error('Must provide 3-5 security questions');
        }

        const tx = this.db.db.transaction(() => {
            // Remove old questions
            this.db.db.prepare('DELETE FROM security_questions WHERE wallet_id = ?').run(walletId);

            const stmt = this.db.db.prepare(`
                INSERT INTO security_questions (wallet_id, question_index, question_text, answer_hash, answer_salt, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            `);

            for (let i = 0; i < questions.length; i++) {
                const { question, answer } = questions[i];
                if (!question || !answer) throw new Error('Question and answer are required');

                const salt = crypto.randomBytes(32).toString('hex');
                const hash = this._hashAnswer(answer, salt);

                stmt.run(walletId, i, question.trim(), hash, salt, new Date().toISOString());
            }
        });
        tx();
    }

    /**
     * Get security questions (without answers) for recovery
     */
    getSecurityQuestions(walletId) {
        const rows = this.db.db.prepare(
            'SELECT question_index, question_text FROM security_questions WHERE wallet_id = ? ORDER BY question_index'
        ).all(walletId);
        return rows;
    }

    /**
     * Check if wallet has security questions set
     */
    hasSecurityQuestions(walletId) {
        const row = this.db.db.prepare(
            'SELECT COUNT(*) as count FROM security_questions WHERE wallet_id = ?'
        ).get(walletId);
        return row.count >= 3;
    }

    /**
     * Verify answers - returns { passed: boolean, correct: number, total: number }
     * @param {number} walletId
     * @param {Array<{index: number, answer: string}>} answers
     */
    verifySecurityAnswers(walletId, answers) {
        const questions = this.db.db.prepare(
            'SELECT * FROM security_questions WHERE wallet_id = ? ORDER BY question_index'
        ).all(walletId);

        if (!questions.length) throw new Error('No security questions set');

        let correct = 0;
        for (const ans of answers) {
            const q = questions.find(q => q.question_index === ans.index);
            if (q) {
                const hash = this._hashAnswer(ans.answer, q.answer_salt);
                if (hash === q.answer_hash) correct++;
            }
        }

        const required = Math.min(3, questions.length);
        return {
            passed: correct >= required,
            correct,
            total: questions.length,
            required
        };
    }

    // ─── Recovery Key (Layer 1 supplement) ──────────────────

    /**
     * Set a 6-digit recovery key
     * @param {number} walletId
     * @param {string} recoveryKey - 6 digit PIN
     * @param {string} [hint] - optional hint
     */
    setRecoveryKey(walletId, recoveryKey, hint = '') {
        if (!/^\d{6}$/.test(recoveryKey)) {
            throw new Error('Recovery key must be exactly 6 digits');
        }

        const salt = crypto.randomBytes(32).toString('hex');
        const hash = this._hashAnswer(recoveryKey, salt);

        this.db.db.prepare(`
            INSERT OR REPLACE INTO recovery_keys (wallet_id, key_hash, key_salt, hint, created_at)
            VALUES (?, ?, ?, ?, ?)
        `).run(walletId, hash, salt, hint || null, new Date().toISOString());
    }

    /**
     * Verify recovery key
     */
    verifyRecoveryKey(walletId, recoveryKey) {
        const row = this.db.db.prepare(
            'SELECT * FROM recovery_keys WHERE wallet_id = ?'
        ).get(walletId);

        if (!row) throw new Error('No recovery key set');

        const hash = this._hashAnswer(recoveryKey, row.key_salt);
        return hash === row.key_hash;
    }

    hasRecoveryKey(walletId) {
        const row = this.db.db.prepare(
            'SELECT COUNT(*) as count FROM recovery_keys WHERE wallet_id = ?'
        ).get(walletId);
        return row.count > 0;
    }

    getRecoveryKeyHint(walletId) {
        const row = this.db.db.prepare(
            'SELECT hint FROM recovery_keys WHERE wallet_id = ?'
        ).get(walletId);
        return row ? row.hint : null;
    }

    // ─── Identity Anchors (Layer 2) ────────────────────────

    /**
     * Record an identity anchor (device fingerprint, usage pattern, etc.)
     */
    addAnchor(walletId, type, data) {
        const salt = crypto.randomBytes(16).toString('hex');
        const hash = this._hashAnswer(JSON.stringify(data), salt);

        this.db.db.prepare(`
            INSERT INTO identity_anchors (wallet_id, anchor_type, anchor_hash, anchor_salt, metadata, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        `).run(walletId, type, hash, salt, JSON.stringify({ type }), new Date().toISOString());
    }

    /**
     * Record device fingerprint as anchor
     */
    recordDeviceAnchor(walletId, deviceInfo) {
        this.addAnchor(walletId, 'device', deviceInfo);
    }

    getAnchors(walletId) {
        return this.db.db.prepare(
            'SELECT anchor_type, metadata, created_at FROM identity_anchors WHERE wallet_id = ? ORDER BY created_at DESC'
        ).all(walletId);
    }

    // ─── Recovery Flow ──────────────────────────────────────

    /**
     * Get identity status for a wallet - what layers are configured
     */
    getIdentityStatus(walletId) {
        const hasQuestions = this.hasSecurityQuestions(walletId);
        const hasRecKey = this.hasRecoveryKey(walletId);
        const anchorCount = this.db.db.prepare(
            'SELECT COUNT(*) as count FROM identity_anchors WHERE wallet_id = ?'
        ).get(walletId).count;

        let securityLevel = 0;
        if (hasQuestions) securityLevel++;
        if (hasRecKey) securityLevel++;
        if (anchorCount > 0) securityLevel++;

        const levelNames = ['', 'basic', 'standard', 'strong'];
        const levelDescs = {
            0: { en: 'No identity protection', th: 'ยังไม่มีการป้องกันตัวตน' },
            1: { en: 'Basic protection', th: 'การป้องกันพื้นฐาน' },
            2: { en: 'Standard protection', th: 'การป้องกันมาตรฐาน' },
            3: { en: 'Strong protection', th: 'การป้องกันแข็งแกร่ง' },
        };

        return {
            hasQuestions,
            hasRecKey,
            anchorCount,
            securityLevel,
            securityLevelName: levelNames[securityLevel] || 'none',
            description: levelDescs[securityLevel] || levelDescs[0],
            questionCount: hasQuestions ? this.db.db.prepare(
                'SELECT COUNT(*) as count FROM security_questions WHERE wallet_id = ?'
            ).get(walletId).count : 0,
        };
    }

    /**
     * Attempt recovery - verify multiple layers
     * @returns {{ success: boolean, layersPassed: string[], message: string }}
     */
    attemptRecovery(walletId, { answers, recoveryKey }) {
        const layersPassed = [];
        const results = {};

        // Layer 1a: Security Questions
        if (answers && answers.length > 0) {
            try {
                const result = this.verifySecurityAnswers(walletId, answers);
                results.questions = result;
                if (result.passed) layersPassed.push('questions');
            } catch (e) {
                results.questions = { error: e.message };
            }
        }

        // Layer 1b: Recovery Key
        if (recoveryKey) {
            try {
                const valid = this.verifyRecoveryKey(walletId, recoveryKey);
                results.recoveryKey = { valid };
                if (valid) layersPassed.push('recoveryKey');
            } catch (e) {
                results.recoveryKey = { error: e.message };
            }
        }

        // Determine if recovery is allowed
        const identityStatus = this.getIdentityStatus(walletId);
        let requiredLayers = 1;
        if (identityStatus.securityLevel >= 2) requiredLayers = 2;

        const success = layersPassed.length >= requiredLayers;

        return {
            success,
            layersPassed,
            results,
            requiredLayers,
            message: success
                ? 'Recovery verification passed'
                : `Need ${requiredLayers} layer(s), only ${layersPassed.length} passed`,
        };
    }

    // ─── Internal ───────────────────────────────────────────

    _hashAnswer(answer, salt) {
        // Normalize: lowercase, trim, remove extra spaces
        const normalized = String(answer).toLowerCase().trim().replace(/\s+/g, ' ');
        return crypto.pbkdf2Sync(normalized, 'tpix-identity:' + salt, 50000, 32, 'sha256').toString('hex');
    }
}

module.exports = IdentityManager;
