/**
 * TPIX Master Node — Shared RPC Client
 * Centralised JSON-RPC helper used by WalletManager and TransactionManager.
 * Includes rate limiting and circuit breaker for resilience.
 * Developed by Xman Studio
 */

const https = require('https');
const http = require('http');

const TPIX_RPC = 'https://rpc.tpix.online';

// ─── Rate Limiter ──────────────────────────────────────────────
const RATE_LIMIT = 20;          // max requests per window
const RATE_WINDOW_MS = 1000;    // 1 second window
let requestTimestamps = [];

function isRateLimited() {
    const now = Date.now();
    requestTimestamps = requestTimestamps.filter(t => now - t < RATE_WINDOW_MS);
    if (requestTimestamps.length >= RATE_LIMIT) return true;
    requestTimestamps.push(now);
    return false;
}

// ─── Circuit Breaker ───────────────────────────────────────────
const CB_THRESHOLD = 5;         // failures before opening circuit
const CB_RESET_MS = 30000;      // 30s before half-open retry
let cbFailures = 0;
let cbState = 'closed';        // closed | open | half-open
let cbOpenedAt = 0;

function checkCircuitBreaker() {
    if (cbState === 'closed') return true;
    if (cbState === 'open') {
        if (Date.now() - cbOpenedAt > CB_RESET_MS) {
            cbState = 'half-open';
            return true; // allow one request
        }
        return false;
    }
    // half-open: allow
    return true;
}

function recordSuccess() {
    cbFailures = 0;
    cbState = 'closed';
}

function recordFailure() {
    cbFailures++;
    if (cbFailures >= CB_THRESHOLD) {
        cbState = 'open';
        cbOpenedAt = Date.now();
    }
}

// ─── RPC Call ──────────────────────────────────────────────────

/**
 * Send a JSON-RPC call to the TPIX Chain.
 * @param {string} method  — e.g. 'eth_getBalance'
 * @param {Array}  params  — RPC params
 * @param {number} [timeout=15000] — ms
 * @returns {Promise<any>}
 */
function rpcCall(method, params = [], timeout = 15000) {
    return new Promise((resolve, reject) => {
        // Rate limiting check
        if (isRateLimited()) {
            return reject(new Error('RPC rate limit exceeded, try again shortly'));
        }

        // Circuit breaker check
        if (!checkCircuitBreaker()) {
            return reject(new Error('RPC circuit breaker open — service temporarily unavailable'));
        }

        const url = new URL(TPIX_RPC);
        const client = url.protocol === 'https:' ? https : http;
        const body = JSON.stringify({
            jsonrpc: '2.0',
            method,
            params,
            id: Date.now() + Math.random(),
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
                timeout,
            },
            (res) => {
                let data = '';
                res.on('data', (c) => (data += c));
                res.on('end', () => {
                    try {
                        const json = JSON.parse(data);
                        if (json.error) {
                            recordFailure();
                            reject(new Error(json.error.message));
                        } else {
                            recordSuccess();
                            resolve(json.result);
                        }
                    } catch {
                        recordFailure();
                        reject(new Error('Invalid RPC response'));
                    }
                });
            },
        );
        req.on('error', (err) => {
            recordFailure();
            reject(err);
        });
        req.on('timeout', () => {
            req.destroy();
            recordFailure();
            reject(new Error('RPC timeout'));
        });
        req.write(body);
        req.end();
    });
}

module.exports = { rpcCall, TPIX_RPC };
