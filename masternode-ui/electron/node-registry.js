/**
 * TPIX Master Node — NodeRegistryV2 client
 *
 * ต่อกับสัญญา staking จริงบนเชน แทนการเขียนตัวเลขลง SQLite เอง
 * เดินทางเดียวกับที่เว็บ tpix.online ใช้ (MasterNode/Index.vue) เพื่อให้
 * ยอด stake และรางวัลของแอปกับเว็บเป็นก้อนเดียวกัน ไม่ใช่คนละชุดข้อมูล
 *
 * ถ้ายังไม่ได้ตั้งแอดเดรสสัญญา โมดูลนี้จะรายงานว่า "ยังไม่พร้อม" และ
 * แอปจะกลับไปใช้โหมดประมาณการในเครื่องซึ่งติดป้ายไว้ชัดแล้วว่าไม่ใช่เงินจริง
 *
 * Developed by Xman Studio
 */

const { rpcCall } = require('./rpc-client');

const CHAIN_ID = 4289;

// gas limit ต่อฟังก์ชัน — เชนนี้ gas = 0 แต่ยังต้องใส่ให้พอ ไม่งั้น out of gas
const GAS = {
    registerNode: 400000,
    deregisterNode: 300000,
    claimRewards: 250000,
    fundRewardPool: 100000,
};

// ลำดับ tier ในสัญญา — Guardian=0 เพื่อความเข้ากันได้กับ V1 (อย่าสลับ)
const TIER_INDEX = { guardian: 0, sentinel: 1, light: 2, validator: 3 };
const TIER_NAME = ['guardian', 'sentinel', 'light', 'validator'];
const STATUS_NAME = ['inactive', 'active', 'slashed', 'exited', 'slashed_withdrawable'];

const ABI = [
    'function registerNode(uint8 _tier, string _endpoint) payable',
    'function deregisterNode()',
    'function claimRewards()',
    'function withdrawSlashedStake()',
    'function fundRewardPool() payable',
    'function pendingReward(address _operator) view returns (uint256)',
    'function claimableNow(address _operator) view returns (uint256)',
    'function availableRewardFunds() view returns (uint256)',
    'function totalStaked() view returns (uint256)',
    'function rewardPoolStatus() view returns (uint256 fundedBalance, uint256 totalFunded, uint256 distributed, uint256 scheduleCap)',
    'function getNetworkStats() view returns (uint256 totalStaked, uint256 totalActiveNodes, uint256 totalRewardsDistributed, uint256 remainingRewards, uint256 currentRewardPerSecond, uint256 currentYear)',
    'function getNodeInfo(address _operator) view returns (tuple(address operator, uint8 tier, uint8 status, uint256 stakedAmount, uint256 registeredAt, uint256 unlockAt, uint256 lastRewardAt, uint256 totalRewards, uint256 uptime, bytes32 nodeId, string endpoint, uint256 rewardDebt, uint256 pendingUnclaimed))',
    'function getTierInfo(uint8 _tier) view returns (tuple(uint256 minStake, uint256 maxNodes, uint256 activeNodes, uint256 lockDays, uint256 slashPercent, uint256 rewardShare))',
    'function activeValidatorCount() view returns (uint256)',
    'function isValidator(address _operator) view returns (bool)',
];

class NodeRegistryClient {
    /**
     * @param {object} database  TpixDatabase — ใช้บันทึก tx ที่ส่งออกไป
     */
    constructor(database) {
        this.db = database;
        this.address = '';
        this._iface = null;
    }

    /**
     * ตั้งแอดเดรสสัญญา ('' = ยังไม่ deploy → แอปกลับไปโหมดประมาณการ)
     */
    setAddress(addr) {
        const { ethers } = require('ethers');
        if (!addr) {
            this.address = '';
            return { configured: false };
        }
        if (!ethers.isAddress(addr)) {
            throw new Error('แอดเดรสสัญญาไม่ถูกต้อง');
        }
        this.address = ethers.getAddress(addr);
        return { configured: true, address: this.address };
    }

    isConfigured() {
        return !!this.address;
    }

    _interface() {
        if (!this._iface) {
            const { ethers } = require('ethers');
            this._iface = new ethers.Interface(ABI);
        }
        return this._iface;
    }

    _requireConfigured() {
        if (!this.isConfigured()) {
            const e = new Error('ยังไม่ได้ตั้งแอดเดรสสัญญา NodeRegistry');
            e.code = 'REGISTRY_NOT_CONFIGURED';
            throw e;
        }
    }

    /**
     * ตรวจว่าแอดเดรสที่ตั้งไว้มีโค้ดอยู่บนเชนจริง — อย่าเชื่อแค่ค่าใน config
     * เพราะ regenesis ครั้งก่อนทำให้แอดเดรสที่เคยใช้ได้กลายเป็นที่ว่าง
     */
    async verifyDeployed() {
        if (!this.isConfigured()) return { deployed: false, reason: 'not_configured' };
        try {
            const code = await rpcCall('eth_getCode', [this.address, 'latest']);
            if (!code || code === '0x') {
                return { deployed: false, reason: 'no_code', address: this.address };
            }
            return { deployed: true, address: this.address, codeSize: (code.length - 2) / 2 };
        } catch (err) {
            return { deployed: false, reason: 'rpc_error', error: err.message };
        }
    }

    // ─── อ่านจากสัญญา ───────────────────────────────

    async _call(fnName, args = []) {
        this._requireConfigured();
        const iface = this._interface();
        const data = iface.encodeFunctionData(fnName, args);
        const raw = await rpcCall('eth_call', [{ to: this.address, data }, 'latest']);
        if (!raw || raw === '0x') {
            throw new Error(`สัญญาไม่ตอบสำหรับ ${fnName} — ตรวจว่าแอดเดรสถูกเชนถูกหรือไม่`);
        }
        return iface.decodeFunctionResult(fnName, raw);
    }

    /**
     * ข้อมูลโหนดของ operator — คืน null ถ้ายังไม่เคยลงทะเบียน
     */
    async getNodeInfo(operator) {
        const [n] = await this._call('getNodeInfo', [operator]);
        if (!n || n.operator === '0x0000000000000000000000000000000000000000') return null;
        return {
            operator: n.operator,
            tier: TIER_NAME[Number(n.tier)] || String(n.tier),
            tierIndex: Number(n.tier),
            status: STATUS_NAME[Number(n.status)] || String(n.status),
            stakedAmount: n.stakedAmount.toString(),
            registeredAt: Number(n.registeredAt),
            unlockAt: Number(n.unlockAt),
            lastRewardAt: Number(n.lastRewardAt),
            totalRewards: n.totalRewards.toString(),
            uptime: Number(n.uptime),
            nodeId: n.nodeId,
            endpoint: n.endpoint,
            pendingUnclaimed: n.pendingUnclaimed.toString(),
        };
    }

    /**
     * รางวัลที่หาได้แล้วทั้งหมด (wei) กับส่วนที่เบิกได้จริงตอนนี้
     * ทั้งสองค่าต่างกันเมื่อ reward pool ยังเติมไม่พอ
     */
    async getRewards(operator) {
        const [[earned], [claimable]] = await Promise.all([
            this._call('pendingReward', [operator]),
            this._call('claimableNow', [operator]),
        ]);
        return {
            earnedWei: earned.toString(),
            claimableWei: claimable.toString(),
            fullyFunded: earned.toString() === claimable.toString(),
        };
    }

    async getRewardPoolStatus() {
        const r = await this._call('rewardPoolStatus');
        return {
            fundedBalanceWei: r[0].toString(),
            totalFundedWei: r[1].toString(),
            distributedWei: r[2].toString(),
            scheduleCapWei: r[3].toString(),
        };
    }

    async getNetworkStats() {
        const r = await this._call('getNetworkStats');
        return {
            totalStakedWei: r[0].toString(),
            totalActiveNodes: Number(r[1]),
            totalRewardsDistributedWei: r[2].toString(),
            remainingRewardsWei: r[3].toString(),
            rewardPerSecondWei: r[4].toString(),
            currentYear: Number(r[5]),
        };
    }

    async getTierInfo(tierName) {
        const idx = TIER_INDEX[tierName];
        if (idx === undefined) throw new Error(`tier ไม่รู้จัก: ${tierName}`);
        const [t] = await this._call('getTierInfo', [idx]);
        return {
            tier: tierName,
            minStakeWei: t.minStake.toString(),
            maxNodes: Number(t.maxNodes),
            activeNodes: Number(t.activeNodes),
            lockDays: Number(t.lockDays),
            slashPercent: Number(t.slashPercent),
            rewardShare: Number(t.rewardShare),
        };
    }

    // ─── เขียนลงเชน ─────────────────────────────────

    /**
     * เซ็นและส่ง tx ไปที่สัญญา
     * @param {string} privateKey  คีย์ที่ถอดรหัสแล้ว — ห้าม log ห้ามเก็บ
     */
    async _send(privateKey, fromAddress, fnName, args, { valueWei = 0n, gasLimit, walletId } = {}) {
        this._requireConfigured();
        const { ethers } = require('ethers');
        const iface = this._interface();
        const data = iface.encodeFunctionData(fnName, args);

        const [nonceHex, gasPriceHex] = await Promise.all([
            rpcCall('eth_getTransactionCount', [fromAddress, 'pending']),
            rpcCall('eth_gasPrice'),
        ]);

        const tx = {
            to: this.address,
            data,
            value: valueWei,
            gasLimit: gasLimit || GAS[fnName] || 300000,
            gasPrice: BigInt(gasPriceHex),
            nonce: parseInt(nonceHex, 16),
            chainId: CHAIN_ID,
        };

        const wallet = new ethers.Wallet(privateKey);
        const signed = await wallet.signTransaction(tx);
        const txHash = await rpcCall('eth_sendRawTransaction', [signed]);

        if (this.db && walletId) {
            try {
                this.db.insertTransaction({
                    walletId,
                    txHash,
                    fromAddress: fromAddress.toLowerCase(),
                    toAddress: this.address.toLowerCase(),
                    value: valueWei.toString(),
                    gasUsed: null,
                    gasPrice: tx.gasPrice.toString(),
                    blockNumber: null,
                    blockTimestamp: null,
                    status: 'pending',
                    direction: 'sent',
                    nonce: tx.nonce,
                });
            } catch { /* บันทึกไม่ได้ไม่ควรทำให้ tx ที่ส่งไปแล้วล้ม */ }
        }

        return { txHash, method: fnName };
    }

    /**
     * ลงทะเบียนโหนด + ล็อกเงิน stake จริง
     * @param {string} tierName  guardian | sentinel | light | validator
     * @param {string} stakeWei  จำนวนที่จะ stake (wei, string)
     */
    async registerNode(privateKey, fromAddress, tierName, endpoint, stakeWei, walletId) {
        const idx = TIER_INDEX[tierName];
        if (idx === undefined) throw new Error(`tier ไม่รู้จัก: ${tierName}`);

        const ep = String(endpoint || '').trim();
        if (!ep) throw new Error('ต้องระบุ endpoint ของโหนด');
        if (ep.length > 100) throw new Error('endpoint ยาวเกิน 100 ตัวอักษร');

        const value = BigInt(stakeWei);
        if (value <= 0n) throw new Error('จำนวน stake ต้องมากกว่า 0');

        // ตรวจกับสัญญาก่อนส่ง เพื่อให้ผู้ใช้เห็นเหตุผลชัด แทน revert เปล่า ๆ
        const tier = await this.getTierInfo(tierName);
        if (value < BigInt(tier.minStakeWei)) {
            throw new Error(
                `ระดับ ${tierName} ต้อง stake อย่างน้อย ${BigInt(tier.minStakeWei) / 10n ** 18n} TPIX`
            );
        }
        if (tier.maxNodes > 0 && tier.activeNodes >= tier.maxNodes) {
            throw new Error(`ระดับ ${tierName} เต็มแล้ว (${tier.activeNodes}/${tier.maxNodes})`);
        }

        const existing = await this.getNodeInfo(fromAddress);
        if (existing && existing.status === 'active') {
            throw new Error('กระเป๋านี้ลงทะเบียนโหนดไว้แล้ว');
        }

        return this._send(privateKey, fromAddress, 'registerNode', [idx, ep], {
            valueWei: value,
            walletId,
        });
    }

    /**
     * เวลาปัจจุบันตามเชน ไม่ใช่ตามนาฬิกาเครื่อง
     * สัญญาเทียบ unlockAt กับ block.timestamp ถ้าเอานาฬิกาเครื่องมาเทียบ
     * เครื่องที่ตั้งเวลาเพี้ยนจะโดนห้ามถอนทั้งที่ถอนได้ หรือถูกปล่อยให้ส่ง tx
     * ที่จะ revert แน่ ๆ
     */
    async getChainTime() {
        const block = await rpcCall('eth_getBlockByNumber', ['latest', false]);
        if (!block || !block.timestamp) throw new Error('อ่านเวลาจากเชนไม่ได้');
        return parseInt(block.timestamp, 16);
    }

    /**
     * ถอนโหนดออกและรับเงินต้นคืน (ต้องพ้นช่วงล็อกก่อน)
     */
    async deregisterNode(privateKey, fromAddress, walletId) {
        const node = await this.getNodeInfo(fromAddress);
        if (!node || node.status !== 'active') {
            throw new Error('ไม่มีโหนดที่ทำงานอยู่สำหรับกระเป๋านี้');
        }
        const now = await this.getChainTime();
        if (now < node.unlockAt) {
            const days = Math.ceil((node.unlockAt - now) / 86400);
            throw new Error(`ยังอยู่ในช่วงล็อก เหลืออีก ${days} วัน`);
        }
        return this._send(privateKey, fromAddress, 'deregisterNode', [], { walletId });
    }

    /**
     * เบิกรางวัล — เบิกได้เท่าที่ reward pool มีเงินจริงเท่านั้น
     */
    async claimRewards(privateKey, fromAddress, walletId) {
        const r = await this.getRewards(fromAddress);
        if (BigInt(r.claimableWei) === 0n) {
            if (BigInt(r.earnedWei) > 0n) {
                throw new Error('มีรางวัลค้างอยู่แต่ reward pool ยังเติมไม่พอ — ยอดไม่หาย เบิกได้เมื่อพูลมีเงิน');
            }
            throw new Error('ยังไม่มีรางวัลให้เบิก');
        }
        return this._send(privateKey, fromAddress, 'claimRewards', [], { walletId });
    }

    /**
     * เติมเงินเข้า reward pool (ใครก็เติมได้)
     */
    async fundRewardPool(privateKey, fromAddress, amountWei, walletId) {
        const value = BigInt(amountWei);
        if (value <= 0n) throw new Error('จำนวนต้องมากกว่า 0');
        return this._send(privateKey, fromAddress, 'fundRewardPool', [], {
            valueWei: value,
            walletId,
        });
    }
}

module.exports = { NodeRegistryClient, TIER_INDEX, TIER_NAME, ABI };
