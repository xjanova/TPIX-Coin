/**
 * TPIX Master Node — Transaction Manager
 * Builds, signs, broadcasts transactions, and polls for confirmations.
 * Developed by Xman Studio
 */

const https = require('https');
const http = require('http');

const TPIX_RPC = 'https://rpc.tpix.online';
const CHAIN_ID = 4289;
const DEFAULT_GAS_LIMIT = 21000;
const CONFIRM_POLL_MS = 5000;
const CONFIRM_TIMEOUT_MS = 120000;

class TransactionManager {
    constructor(database) {
        this.db = database;
        this._pollingTxs = new Map(); // txHash -> interval
    }

    /**
     * Estimate gas fee for a transfer.
     */
    async estimateGas(toAddress, amountEther) {
        const { ethers } = require('ethers');

        const gasPrice = await this._getGasPrice();
        const gasPriceBn = BigInt(gasPrice);
        const gasLimit = BigInt(DEFAULT_GAS_LIMIT);
        const fee = gasPriceBn * gasLimit;

        return {
            gasLimit: gasLimit.toString(),
            gasPrice: gasPrice,
            gasPriceGwei: ethers.formatUnits(gasPrice, 'gwei'),
            fee: ethers.formatEther(fee),
            feeWei: fee.toString(),
        };
    }

    /**
     * Send TPIX from a wallet.
     * @param {string} privateKey - Decrypted private key
     * @param {string} toAddress - Recipient address
     * @param {string} amountEther - Amount in TPIX (ether units)
     * @param {number} walletId - DB wallet ID for history
     * @returns {{ txHash: string }}
     */
    async sendTransaction(privateKey, fromAddress, toAddress, amountEther, walletId) {
        const { ethers } = require('ethers');

        // Validate
        if (!ethers.isAddress(toAddress)) {
            throw new Error('Invalid recipient address');
        }
        const amount = parseFloat(amountEther);
        if (isNaN(amount) || amount <= 0) {
            throw new Error('Invalid amount');
        }

        // Get nonce and gas price
        const [nonceHex, gasPriceHex] = await Promise.all([
            this._rpcCall('eth_getTransactionCount', [fromAddress, 'pending']),
            this._rpcCall('eth_gasPrice'),
        ]);

        const nonce = parseInt(nonceHex, 16);
        const gasPrice = BigInt(gasPriceHex);
        const value = ethers.parseEther(amountEther);

        // Build and sign transaction
        const wallet = new ethers.Wallet(privateKey);
        const tx = {
            to: toAddress,
            value: value,
            gasLimit: DEFAULT_GAS_LIMIT,
            gasPrice: gasPrice,
            nonce: nonce,
            chainId: CHAIN_ID,
        };

        const signedTx = await wallet.signTransaction(tx);

        // Broadcast
        const txHash = await this._rpcCall('eth_sendRawTransaction', [signedTx]);

        // Save to database
        this.db.insertTransaction({
            walletId,
            txHash,
            fromAddress: fromAddress.toLowerCase(),
            toAddress: toAddress.toLowerCase(),
            value: value.toString(),
            gasUsed: null,
            gasPrice: gasPrice.toString(),
            blockNumber: null,
            blockTimestamp: null,
            status: 'pending',
            direction: 'sent',
            nonce,
        });

        // Start polling for confirmation
        this._pollConfirmation(txHash);

        return { txHash };
    }

    /**
     * Poll for transaction confirmation.
     */
    _pollConfirmation(txHash) {
        const startTime = Date.now();

        const interval = setInterval(async () => {
            try {
                const receipt = await this._rpcCall('eth_getTransactionReceipt', [txHash]);

                if (receipt) {
                    clearInterval(interval);
                    this._pollingTxs.delete(txHash);

                    const status = receipt.status === '0x1' ? 'confirmed' : 'failed';
                    const blockNumber = parseInt(receipt.blockNumber, 16);
                    const gasUsed = parseInt(receipt.gasUsed, 16).toString();

                    // Get block timestamp
                    let blockTimestamp = null;
                    try {
                        const block = await this._rpcCall('eth_getBlockByNumber', [receipt.blockNumber, false]);
                        if (block) blockTimestamp = parseInt(block.timestamp, 16);
                    } catch {}

                    this.db.updateTransactionStatus(txHash, status, blockNumber, blockTimestamp, gasUsed);
                    return;
                }

                // Timeout
                if (Date.now() - startTime > CONFIRM_TIMEOUT_MS) {
                    clearInterval(interval);
                    this._pollingTxs.delete(txHash);
                }
            } catch {
                // RPC error — keep polling
            }
        }, CONFIRM_POLL_MS);

        this._pollingTxs.set(txHash, interval);
    }

    /**
     * Get transaction status by hash (from DB or RPC).
     */
    async getTxStatus(txHash) {
        // Check DB first
        const dbTx = this.db.getTransactionByHash(txHash);
        if (dbTx && dbTx.status !== 'pending') {
            return dbTx;
        }

        // Check RPC
        try {
            const receipt = await this._rpcCall('eth_getTransactionReceipt', [txHash]);
            if (receipt) {
                const status = receipt.status === '0x1' ? 'confirmed' : 'failed';
                return { status, blockNumber: parseInt(receipt.blockNumber, 16) };
            }
        } catch {}

        return { status: 'pending' };
    }

    /**
     * Scan recent blocks for incoming transactions to a wallet address.
     * Stores them in the transactions table.
     */
    async scanIncoming(walletId, address, blockCount = 100) {
        try {
            const latestHex = await this._rpcCall('eth_blockNumber');
            const latest = parseInt(latestHex, 16);
            const fromBlock = Math.max(0, latest - blockCount);
            const { ethers } = require('ethers');

            for (let i = latest; i >= fromBlock; i--) {
                const blockHex = '0x' + i.toString(16);
                const block = await this._rpcCall('eth_getBlockByNumber', [blockHex, true]);
                if (!block || !block.transactions) continue;

                for (const tx of block.transactions) {
                    if (tx.to && tx.to.toLowerCase() === address.toLowerCase()) {
                        // Incoming transaction
                        const existing = this.db.getTransactionByHash(tx.hash);
                        if (!existing) {
                            this.db.insertTransaction({
                                walletId,
                                txHash: tx.hash,
                                fromAddress: tx.from.toLowerCase(),
                                toAddress: tx.to.toLowerCase(),
                                value: BigInt(tx.value).toString(),
                                gasUsed: null,
                                gasPrice: BigInt(tx.gasPrice || '0x0').toString(),
                                blockNumber: i,
                                blockTimestamp: parseInt(block.timestamp, 16),
                                status: 'confirmed',
                                direction: 'received',
                                nonce: parseInt(tx.nonce, 16),
                            });
                        }
                    }
                    if (tx.from && tx.from.toLowerCase() === address.toLowerCase()) {
                        // Outgoing transaction (not yet recorded)
                        const existing = this.db.getTransactionByHash(tx.hash);
                        if (!existing) {
                            this.db.insertTransaction({
                                walletId,
                                txHash: tx.hash,
                                fromAddress: tx.from.toLowerCase(),
                                toAddress: (tx.to || '').toLowerCase(),
                                value: BigInt(tx.value).toString(),
                                gasUsed: null,
                                gasPrice: BigInt(tx.gasPrice || '0x0').toString(),
                                blockNumber: i,
                                blockTimestamp: parseInt(block.timestamp, 16),
                                status: 'confirmed',
                                direction: 'sent',
                                nonce: parseInt(tx.nonce, 16),
                            });
                        }
                    }
                }
            }
        } catch (err) {
            console.error('Scan incoming error:', err.message);
        }
    }

    /**
     * Stop all polling intervals.
     */
    stopAll() {
        for (const [, interval] of this._pollingTxs) {
            clearInterval(interval);
        }
        this._pollingTxs.clear();
    }

    // ─── RPC helpers ────────────────────────────────────────────

    async _getGasPrice() {
        return this._rpcCall('eth_gasPrice');
    }

    _rpcCall(method, params = []) {
        return new Promise((resolve, reject) => {
            const url = new URL(TPIX_RPC);
            const client = url.protocol === 'https:' ? https : http;
            const body = JSON.stringify({ jsonrpc: '2.0', method, params, id: Date.now() + Math.random() });

            const req = client.request({
                hostname: url.hostname,
                port: url.port || (url.protocol === 'https:' ? 443 : 80),
                path: url.pathname,
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
                timeout: 15000,
            }, (res) => {
                let data = '';
                res.on('data', (c) => (data += c));
                res.on('end', () => {
                    try {
                        const json = JSON.parse(data);
                        json.error ? reject(new Error(json.error.message)) : resolve(json.result);
                    } catch { reject(new Error('Invalid response')); }
                });
            });
            req.on('error', reject);
            req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
            req.write(body);
            req.end();
        });
    }
}

module.exports = TransactionManager;
