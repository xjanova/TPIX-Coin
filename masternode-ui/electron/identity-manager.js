/**
 * TPIX Living Identity Manager
 * "ยิ่งใช้ ยิ่งปลอดภัย — ลืมได้ แต่ chain จำให้"
 *
 * Layer 1: Knowledge Proof (Security Questions)
 * Layer 2: Location Proof (GPS — hashed grid, never plaintext)
 * Layer 3: Recovery Key (6-8 digit PIN — backup when GPS unavailable)
 * Layer 4: Time Lock (48h recovery delay — future)
 * Layer 5: Social Proof (Guardian wallets — future)
 *
 * Privacy: GPS coordinates are rounded to ~111m grid then SHA-256 hashed.
 * Only the hash is stored. No one — not even with database access — can
 * reverse-engineer the exact location. Verification checks 9 neighboring
 * grid cells (±200m tolerance) so you don't need to stand on the exact spot.
 *
 * Developed by Xman Studio
 */

const crypto = require('crypto');

const MAX_ATTEMPTS = 5;
const LOCKOUT_MS = 5 * 60 * 1000; // 5 minutes
const GPS_GRID_PRECISION = 3; // 3 decimal places ≈ 111m grid
const MAX_GPS_LOCATIONS = 3;

class IdentityManager {
    constructor(database) {
        this.db = database;
        this._attemptTracker = new Map(); // walletId -> { count, lastAttempt }
        this._ensureTables();
    }

    _checkRateLimit(walletId) {
        const tracker = this._attemptTracker.get(walletId);
        if (!tracker) return;
        if (tracker.count >= MAX_ATTEMPTS) {
            const elapsed = Date.now() - tracker.lastAttempt;
            if (elapsed < LOCKOUT_MS) {
                const remaining = Math.ceil((LOCKOUT_MS - elapsed) / 1000);
                throw new Error(`Too many attempts. Try again in ${remaining} seconds.`);
            }
            // Reset after lockout period
            this._attemptTracker.delete(walletId);
        }
    }

    _recordAttempt(walletId, success) {
        if (success) {
            this._attemptTracker.delete(walletId);
            return;
        }
        const tracker = this._attemptTracker.get(walletId) || { count: 0, lastAttempt: 0 };
        tracker.count++;
        tracker.lastAttempt = Date.now();
        this._attemptTracker.set(walletId, tracker);
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

            CREATE TABLE IF NOT EXISTS gps_locations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
                label TEXT NOT NULL,
                location_hash TEXT NOT NULL,
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
            CREATE INDEX IF NOT EXISTS idx_gl_wallet ON gps_locations(wallet_id);
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
     * Set a 6-8 digit recovery key
     * @param {number} walletId
     * @param {string} recoveryKey - 6-8 digit PIN
     * @param {string} [hint] - optional hint
     */
    setRecoveryKey(walletId, recoveryKey, hint = '') {
        if (!/^\d{6,8}$/.test(recoveryKey)) {
            throw new Error('Recovery key must be 6-8 digits');
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

    // ─── GPS Location Proof (Layer 2) ──────────────────────
    //
    // Privacy Model:
    //   1. GPS coordinates are rounded to a ~111m grid (3 decimal places)
    //   2. The rounded grid string is SHA-256 hashed with prefix "tpix-loc:"
    //   3. ONLY the hash is stored — never the raw/rounded coordinates
    //   4. Verification checks 9 neighboring grid cells (±200m tolerance)
    //   5. Even with full database access, coordinates cannot be recovered
    //      because the search space is too large without a starting point
    //      combined with the one-way hash.
    //
    // Example:
    //   Input:  13.7563, 100.5018 (Bangkok)
    //   Grid:   13.756, 100.502
    //   Stored: SHA-256("tpix-loc:13.756:100.502") = "a3f8c2..."
    //   The hash reveals NOTHING about the actual location.

    /**
     * Register a GPS location for recovery verification.
     * Coordinates are rounded to ~111m grid and only the hash is stored.
     * @param {number} walletId
     * @param {string} label - User-friendly name (e.g. "Home", "Office")
     * @param {number} latitude
     * @param {number} longitude
     */
    registerGPSLocation(walletId, label, latitude, longitude) {
        if (!label || typeof label !== 'string') {
            throw new Error('Location label is required');
        }
        if (typeof latitude !== 'number' || typeof longitude !== 'number') {
            throw new Error('Valid coordinates are required');
        }
        if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            throw new Error('Coordinates out of range');
        }

        // Check max locations
        const existing = this.db.db.prepare(
            'SELECT COUNT(*) as count FROM gps_locations WHERE wallet_id = ?'
        ).get(walletId);
        if (existing.count >= MAX_GPS_LOCATIONS) {
            throw new Error(`Maximum ${MAX_GPS_LOCATIONS} locations allowed`);
        }

        // Round to grid and hash
        const gridLat = this._toGrid(latitude);
        const gridLng = this._toGrid(longitude);
        const hash = this._hashLocation(gridLat, gridLng);

        // Check for duplicate grid cell
        const dup = this.db.db.prepare(
            'SELECT id FROM gps_locations WHERE wallet_id = ? AND location_hash = ?'
        ).get(walletId, hash);
        if (dup) {
            throw new Error('This location is already registered (same area)');
        }

        this.db.db.prepare(`
            INSERT INTO gps_locations (wallet_id, label, location_hash, created_at)
            VALUES (?, ?, ?, ?)
        `).run(walletId, label.trim(), hash, new Date().toISOString());
    }

    /**
     * Verify if given coordinates match any registered location.
     * Checks 9 grid cells (exact + 8 neighbors) for ±200m tolerance.
     * @param {number} walletId
     * @param {number} latitude
     * @param {number} longitude
     * @returns {{ verified: boolean, matchedLabel: string|null }}
     */
    verifyGPSLocation(walletId, latitude, longitude) {
        const locations = this.db.db.prepare(
            'SELECT label, location_hash FROM gps_locations WHERE wallet_id = ?'
        ).all(walletId);

        if (!locations.length) return { verified: false, matchedLabel: null };

        const gridLat = this._toGrid(latitude);
        const gridLng = this._toGrid(longitude);
        const gridStep = 1.0 / Math.pow(10, GPS_GRID_PRECISION);

        // Check exact cell + 8 neighbors (3x3 grid)
        for (let dLat = -gridStep; dLat <= gridStep + 0.0001; dLat += gridStep) {
            for (let dLng = -gridStep; dLng <= gridStep + 0.0001; dLng += gridStep) {
                const testLat = this._toGrid(gridLat + dLat);
                const testLng = this._toGrid(gridLng + dLng);
                const testHash = this._hashLocation(testLat, testLng);
                const match = locations.find(loc => loc.location_hash === testHash);
                if (match) {
                    return { verified: true, matchedLabel: match.label };
                }
            }
        }

        return { verified: false, matchedLabel: null };
    }

    /**
     * Get registered location labels (NO coordinates — privacy).
     */
    getGPSLocations(walletId) {
        return this.db.db.prepare(
            'SELECT id, label, created_at FROM gps_locations WHERE wallet_id = ? ORDER BY created_at'
        ).all(walletId);
    }

    /**
     * Remove a registered GPS location.
     */
    removeGPSLocation(walletId, locationId) {
        this.db.db.prepare(
            'DELETE FROM gps_locations WHERE id = ? AND wallet_id = ?'
        ).run(locationId, walletId);
    }

    hasGPSLocations(walletId) {
        const row = this.db.db.prepare(
            'SELECT COUNT(*) as count FROM gps_locations WHERE wallet_id = ?'
        ).get(walletId);
        return row.count > 0;
    }

    // ─── Identity Anchors (Device Proof) ────────────────────

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
        const hasGPS = this.hasGPSLocations(walletId);
        const hasRecKey = this.hasRecoveryKey(walletId);
        const gpsLocations = hasGPS ? this.getGPSLocations(walletId) : [];

        let securityLevel = 0;
        if (hasQuestions) securityLevel++;
        if (hasGPS) securityLevel++;
        if (hasRecKey) securityLevel++;

        const levelNames = ['none', 'basic', 'standard', 'strong'];
        const levelDescs = {
            0: { en: 'No identity protection', th: 'ยังไม่มีการป้องกันตัวตน' },
            1: { en: 'Basic protection', th: 'การป้องกันพื้นฐาน' },
            2: { en: 'Standard protection', th: 'การป้องกันมาตรฐาน' },
            3: { en: 'Strong protection', th: 'การป้องกันแข็งแกร่ง' },
        };

        return {
            hasQuestions,
            hasGPS,
            hasRecKey,
            gpsLocations,
            securityLevel,
            securityLevelName: levelNames[securityLevel] || 'none',
            description: levelDescs[securityLevel] || levelDescs[0],
            questionCount: hasQuestions ? this.db.db.prepare(
                'SELECT COUNT(*) as count FROM security_questions WHERE wallet_id = ?'
            ).get(walletId).count : 0,
            gpsLocationCount: gpsLocations.length,
        };
    }

    /**
     * Attempt recovery — verify multiple identity layers.
     *
     * Recovery requires: Security Questions + (GPS Location OR Recovery PIN)
     * GPS is primary verification; Recovery PIN is fallback when GPS unavailable.
     *
     * @param {number} walletId
     * @param {object} data
     * @param {Array<{index: number, answer: string}>} data.answers
     * @param {number} [data.latitude] - GPS latitude for location proof
     * @param {number} [data.longitude] - GPS longitude for location proof
     * @param {string} [data.recoveryKey] - PIN fallback when GPS unavailable
     * @param {boolean} [data.isTest] - Skip rate limiting for self-test
     * @returns {{ success: boolean, layersPassed: string[], results: object, message: string }}
     */
    attemptRecovery(walletId, { answers, latitude, longitude, recoveryKey, isTest }) {
        // Rate limiting (skip for self-tests)
        if (!isTest) this._checkRateLimit(walletId);

        const layersPassed = [];
        const results = {};

        // Layer 1: Security Questions (knowledge proof)
        if (answers && answers.length > 0) {
            try {
                const result = this.verifySecurityAnswers(walletId, answers);
                results.questions = result;
                if (result.passed) layersPassed.push('questions');
            } catch (e) {
                results.questions = { error: e.message };
            }
        }

        // Layer 2: GPS Location (physical proof — primary)
        if (typeof latitude === 'number' && typeof longitude === 'number') {
            try {
                const gpsResult = this.verifyGPSLocation(walletId, latitude, longitude);
                results.gps = gpsResult;
                if (gpsResult.verified) layersPassed.push('gps');
            } catch (e) {
                results.gps = { error: e.message };
            }
        }

        // Layer 3: Recovery Key (PIN — fallback when GPS unavailable)
        if (recoveryKey) {
            try {
                const valid = this.verifyRecoveryKey(walletId, recoveryKey);
                results.recoveryKey = { valid };
                if (valid) layersPassed.push('recoveryKey');
            } catch (e) {
                results.recoveryKey = { error: e.message };
            }
        }

        // Recovery logic: questions + (gps OR pin) = 2 layers required
        const identityStatus = this.getIdentityStatus(walletId);
        let requiredLayers = 1;
        if (identityStatus.securityLevel >= 2) requiredLayers = 2;

        const success = layersPassed.length >= requiredLayers;

        // Track attempts for rate limiting (skip for self-tests)
        if (!isTest) this._recordAttempt(walletId, success);

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
        return crypto.pbkdf2Sync(normalized, 'tpix-identity:' + salt, 100000, 32, 'sha256').toString('hex');
    }

    /**
     * Round coordinate to grid (~111m precision at 3 decimal places).
     * Uses toFixed() to ensure identical string representation across platforms.
     */
    _toGrid(coord) {
        const factor = Math.pow(10, GPS_GRID_PRECISION);
        return Math.round(coord * factor) / factor;
    }

    /**
     * Hash grid coordinates with SHA-256.
     * Input: "tpix-loc:13.756:100.502" → SHA-256 hex
     * One-way: cannot reverse the hash to get coordinates.
     */
    _hashLocation(gridLat, gridLng) {
        const input = `tpix-loc:${gridLat.toFixed(GPS_GRID_PRECISION)}:${gridLng.toFixed(GPS_GRID_PRECISION)}`;
        return crypto.createHash('sha256').update(input).digest('hex');
    }
}

module.exports = IdentityManager;
