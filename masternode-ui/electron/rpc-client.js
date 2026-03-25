/**
 * TPIX Master Node — Shared RPC Client
 * Centralised JSON-RPC helper used by WalletManager and TransactionManager.
 * Developed by Xman Studio
 */

const https = require('https');
const http = require('http');

const TPIX_RPC = 'https://rpc.tpix.online';

/**
 * Send a JSON-RPC call to the TPIX Chain.
 * @param {string} method  — e.g. 'eth_getBalance'
 * @param {Array}  params  — RPC params
 * @param {number} [timeout=15000] — ms
 * @returns {Promise<any>}
 */
function rpcCall(method, params = [], timeout = 15000) {
    return new Promise((resolve, reject) => {
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
                        json.error
                            ? reject(new Error(json.error.message))
                            : resolve(json.result);
                    } catch {
                        reject(new Error('Invalid RPC response'));
                    }
                });
            },
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

module.exports = { rpcCall, TPIX_RPC };
