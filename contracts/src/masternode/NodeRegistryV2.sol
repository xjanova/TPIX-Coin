// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TPIX Master Node Registry V2
 * @notice Manages master node registration, staking, and reward distribution
 * @dev Restructured tier system separating real IBFT2 Validators from staking nodes
 *
 * Tier System (4 tiers):
 *   Tier 0 - Guardian Node:   1,000,000 TPIX stake, 10-12% APY, max 100 nodes  (was "Validator" in V1)
 *   Tier 1 - Sentinel Node:     100,000 TPIX stake,  7-9%  APY, max 500 nodes
 *   Tier 2 - Light Node:         10,000 TPIX stake,  4-6%  APY, unlimited
 *   Tier 3 - Validator Node: 10,000,000 TPIX stake, 15-20% APY, max 21 nodes  (real IBFT2 sealers)
 *
 * IMPORTANT: Guardian=0 preserves backward compatibility with V1 enum where Validator=0.
 *
 * Reward Pool: 1,400,000,000 TPIX over 3 years (ending 2028)
 *   Year 1: 600M | Year 2: 500M | Year 3: 300M
 *
 * Reward Shares: Validator 20%, Guardian 35%, Sentinel 30%, Light 15%
 *
 * ─────────────────────────────────────────────────────────────────────────
 *  REWARD ACCOUNTING — read this before changing anything below
 * ─────────────────────────────────────────────────────────────────────────
 *  The contract holds TWO kinds of native TPIX in one balance:
 *    1. user stake principal  — tracked by `totalStaked`, MUST always be returnable
 *    2. reward pool           — everything above `totalStaked`
 *
 *  Rewards are therefore paid only out of `address(this).balance - totalStaked`.
 *  `totalRewardPool` is the EMISSION SCHEDULE CAP (1.4B), not a claim on funds —
 *  an unfunded contract pays nothing rather than paying out of someone's stake.
 *
 *  Earnings use a per-tier accumulator (`accRewardPerNode`) so a node that joins
 *  later cannot retroactively dilute what earlier nodes already earned. Every
 *  place that changes a tier's active-node count, the emission rate, or a tier's
 *  reward share MUST settle the accumulator first — see `_syncTier` callers.
 * ─────────────────────────────────────────────────────────────────────────
 */
contract NodeRegistryV2 is Ownable, ReentrancyGuard {

    // ============================================================
    //  Enums & Structs
    // ============================================================

    // Guardian=0 for backward compat with V1 (old Validator=0)
    enum NodeTier { Guardian, Sentinel, Light, Validator }
    enum NodeStatus { Inactive, Active, Slashed, Exited, SlashedWithdrawable }

    struct TierConfig {
        uint256 minStake;       // Minimum stake in wei
        uint256 maxNodes;       // Maximum nodes (0 = unlimited)
        uint256 activeNodes;    // Current active node count
        uint256 lockDays;       // Lock period in days
        uint256 slashPercent;   // Slash percentage (basis points, 1000 = 10%)
        uint256 rewardShare;    // Share of reward pool (basis points, 2000 = 20%)
    }

    struct MasterNode {
        address operator;        // Node operator address
        NodeTier tier;           // Node tier
        NodeStatus status;       // Current status
        uint256 stakedAmount;    // Amount staked
        uint256 registeredAt;    // Registration timestamp
        uint256 unlockAt;        // Unlock timestamp
        uint256 lastRewardAt;    // Last time this node was settled
        uint256 totalRewards;    // Total rewards actually paid out
        uint256 uptime;          // Uptime score (0-10000 basis points)
        bytes32 nodeId;          // Unique node identifier
        string endpoint;         // Node RPC endpoint (IP:port)
        uint256 rewardDebt;      // accRewardPerNode snapshot at last settle
        uint256 pendingUnclaimed;// Earned but not yet paid (survives an unfunded pool)
    }

    // ============================================================
    //  State Variables
    // ============================================================

    uint256 private constant ACC_PRECISION = 1e18;
    uint256 private constant MAX_ENDPOINT_LEN = 100;

    // Tier configurations
    mapping(NodeTier => TierConfig) public tiers;

    // Node registry: operator address => MasterNode
    mapping(address => MasterNode) public nodes;

    // All registered operators (for enumeration) — deduplicated
    address[] public operators;
    mapping(address => bool) private _knownOperator;

    // Per-tier reward accumulator: reward owed to ONE node of this tier, scaled 1e18
    mapping(NodeTier => uint256) public accRewardPerNode;
    mapping(NodeTier => uint256) public tierLastUpdate;

    // Reward pool tracking
    uint256 public totalRewardPool;         // Emission schedule cap (1.4B TPIX)
    uint256 public totalRewardsDistributed; // Running total actually paid out
    uint256 public totalRewardFunded;       // Running total deposited for rewards (stats)
    uint256 public rewardStartTime;         // When rewards started
    uint256 public totalStaked;             // Total TPIX staked across all tiers

    // Block reward per second (calculated from yearly emission)
    uint256 public currentRewardPerSecond;
    uint256 public currentYear;             // Current reward year (0-2, 3 = ended)

    // Year emission schedule (in wei) — 3 years
    uint256[3] public yearlyEmission;

    // Active node count
    uint256 public totalActiveNodes;

    // Validator KYC contract reference (optional, set by admin)
    address public kycContract;

    // ============================================================
    //  Events
    // ============================================================

    event NodeRegistered(address indexed operator, NodeTier tier, uint256 stake, bytes32 nodeId);
    event NodeDeregistered(address indexed operator, uint256 stakeReturned);
    event RewardClaimed(address indexed operator, uint256 amount);
    event RewardAccrued(address indexed operator, uint256 amount);
    event RewardPoolFunded(address indexed from, uint256 amount, uint256 poolBalance);
    event NodeSlashed(address indexed operator, uint256 slashAmount, string reason);
    event UptimeUpdated(address indexed operator, uint256 uptime);
    event TierConfigUpdated(NodeTier tier);
    event RewardYearAdvanced(uint256 year, uint256 rewardPerSecond);
    event KYCContractUpdated(address indexed kycContract);

    // ============================================================
    //  Constructor
    // ============================================================

    constructor() Ownable(msg.sender) {
        // Tier 0: Guardian — 1M TPIX, max 100, 90-day lock, 10% slash, 35% reward
        tiers[NodeTier.Guardian] = TierConfig({
            minStake: 1_000_000 ether,
            maxNodes: 100,
            activeNodes: 0,
            lockDays: 90,
            slashPercent: 1000,
            rewardShare: 3500
        });

        // Tier 1: Sentinel — 100K TPIX, max 500, 30-day lock, 5% slash, 30% reward
        tiers[NodeTier.Sentinel] = TierConfig({
            minStake: 100_000 ether,
            maxNodes: 500,
            activeNodes: 0,
            lockDays: 30,
            slashPercent: 500,
            rewardShare: 3000
        });

        // Tier 2: Light — 10K TPIX, unlimited, 7-day lock, no slash, 15% reward
        tiers[NodeTier.Light] = TierConfig({
            minStake: 10_000 ether,
            maxNodes: 0,
            activeNodes: 0,
            lockDays: 7,
            slashPercent: 0,
            rewardShare: 1500
        });

        // Tier 3: Validator — 10M TPIX, max 21, 180-day lock, 15% slash, 20% reward
        tiers[NodeTier.Validator] = TierConfig({
            minStake: 10_000_000 ether,
            maxNodes: 21,
            activeNodes: 0,
            lockDays: 180,
            slashPercent: 1500,
            rewardShare: 2000
        });

        // Emission schedule cap — NOT a balance. Funds arrive via fundRewardPool().
        totalRewardPool = 1_400_000_000 ether;
        yearlyEmission[0] = 600_000_000 ether;
        yearlyEmission[1] = 500_000_000 ether;
        yearlyEmission[2] = 300_000_000 ether;

        rewardStartTime = block.timestamp;
        currentYear = 0;
        _updateRewardRate();

        tierLastUpdate[NodeTier.Guardian] = block.timestamp;
        tierLastUpdate[NodeTier.Sentinel] = block.timestamp;
        tierLastUpdate[NodeTier.Light] = block.timestamp;
        tierLastUpdate[NodeTier.Validator] = block.timestamp;
    }

    // ============================================================
    //  Reward accounting internals
    // ============================================================

    /**
     * @dev Accrue a tier's accumulator up to now at the CURRENT rate and node count.
     *      Must be called before anything that changes activeNodes, the emission
     *      rate, or the tier's reward share — otherwise past time is paid at
     *      tomorrow's terms.
     */
    function _syncTier(NodeTier _tier) internal {
        uint256 last = tierLastUpdate[_tier];
        if (block.timestamp <= last) return;

        TierConfig storage tc = tiers[_tier];
        // With no active nodes there is nobody to credit — that slice of the
        // emission is simply not distributed.
        if (tc.activeNodes > 0 && currentRewardPerSecond > 0 && tc.rewardShare > 0) {
            uint256 tierPerSec = (currentRewardPerSecond * tc.rewardShare) / 10000;
            uint256 elapsed = block.timestamp - last;
            accRewardPerNode[_tier] += (tierPerSec * elapsed * ACC_PRECISION) / tc.activeNodes;
        }
        tierLastUpdate[_tier] = block.timestamp;
    }

    function _syncAllTiers() internal {
        _syncTier(NodeTier.Guardian);
        _syncTier(NodeTier.Sentinel);
        _syncTier(NodeTier.Light);
        _syncTier(NodeTier.Validator);
    }

    /**
     * @dev Move everything this node has earned so far into pendingUnclaimed.
     *      Uptime is applied at settle time, so a later uptime change cannot
     *      retroactively rewrite what was already earned.
     */
    function _settle(address _operator) internal {
        MasterNode storage node = nodes[_operator];
        if (node.status != NodeStatus.Active) return;

        _syncTier(node.tier);

        uint256 acc = accRewardPerNode[node.tier];
        if (acc > node.rewardDebt) {
            uint256 gross = (acc - node.rewardDebt) / ACC_PRECISION;
            uint256 earned = (gross * node.uptime) / 10000;
            if (earned > 0) {
                node.pendingUnclaimed += earned;
                emit RewardAccrued(_operator, earned);
            }
        }
        node.rewardDebt = acc;
        node.lastRewardAt = block.timestamp;
    }

    /**
     * @notice TPIX available to pay rewards right now.
     * @dev Stake principal is never spendable, and the emission schedule caps the rest.
     */
    function availableRewardFunds() public view returns (uint256) {
        uint256 bal = address(this).balance;
        if (bal <= totalStaked) return 0;
        uint256 free = bal - totalStaked;

        uint256 scheduleLeft = totalRewardPool > totalRewardsDistributed
            ? totalRewardPool - totalRewardsDistributed
            : 0;

        return free < scheduleLeft ? free : scheduleLeft;
    }

    /**
     * @dev Pay out what we can. Anything the pool cannot cover stays in
     *      pendingUnclaimed and is claimable once the pool is funded.
     */
    function _payout(address _operator) internal {
        MasterNode storage node = nodes[_operator];
        uint256 owed = node.pendingUnclaimed;
        if (owed == 0) return;

        uint256 avail = availableRewardFunds();
        uint256 amount = owed < avail ? owed : avail;
        if (amount == 0) return;

        node.pendingUnclaimed = owed - amount;
        node.totalRewards += amount;
        totalRewardsDistributed += amount;

        (bool sent, ) = _operator.call{value: amount}("");
        require(sent, "Transfer failed");

        // Invariant: every staker must still be able to withdraw their principal.
        assert(address(this).balance >= totalStaked);

        emit RewardClaimed(_operator, amount);
    }

    // ============================================================
    //  Registration
    // ============================================================

    /**
     * @notice Register a new master node
     * @param _tier Node tier (0=Guardian, 1=Sentinel, 2=Light, 3=Validator)
     * @param _endpoint Node RPC endpoint (e.g., "203.0.113.10:8545")
     * @dev Validator tier requires approved KYC — checked via kycContract if set
     */
    function registerNode(NodeTier _tier, string calldata _endpoint) external payable nonReentrant {
        require(nodes[msg.sender].status == NodeStatus.Inactive, "Already registered");
        require(nodes[msg.sender].pendingUnclaimed == 0, "Claim pending rewards first");
        require(msg.value >= tiers[_tier].minStake, "Insufficient stake");
        uint256 epLen = bytes(_endpoint).length;
        require(epLen > 0, "Endpoint required");
        require(epLen <= MAX_ENDPOINT_LEN, "Endpoint too long");

        TierConfig storage tc = tiers[_tier];
        if (tc.maxNodes > 0) {
            require(tc.activeNodes < tc.maxNodes, "Tier full");
        }

        // Validator tier requires KYC approval
        if (_tier == NodeTier.Validator) {
            require(kycContract != address(0), "KYC contract not configured");
            (bool success, bytes memory data) = kycContract.staticcall(
                abi.encodeWithSignature("isApproved(address)", msg.sender)
            );
            require(success && data.length == 32 && abi.decode(data, (bool)), "KYC not approved");
        }

        // Credit existing members of this tier before the node count changes
        _syncTier(_tier);

        bytes32 nodeId = keccak256(abi.encodePacked(msg.sender, block.timestamp, _tier));

        nodes[msg.sender] = MasterNode({
            operator: msg.sender,
            tier: _tier,
            status: NodeStatus.Active,
            stakedAmount: msg.value,
            registeredAt: block.timestamp,
            unlockAt: block.timestamp + (tc.lockDays * 1 days),
            lastRewardAt: block.timestamp,
            totalRewards: 0,
            uptime: 10000,  // Start at 100%
            nodeId: nodeId,
            endpoint: _endpoint,
            rewardDebt: accRewardPerNode[_tier],  // starts earning from now, not retroactively
            pendingUnclaimed: 0
        });

        // Only ever list an operator once — re-registering must not duplicate them
        if (!_knownOperator[msg.sender]) {
            operators.push(msg.sender);
            _knownOperator[msg.sender] = true;
        }

        tc.activeNodes++;
        totalActiveNodes++;
        totalStaked += msg.value;

        emit NodeRegistered(msg.sender, _tier, msg.value, nodeId);
    }

    /**
     * @notice Deregister and unstake (after lock period)
     */
    function deregisterNode() external nonReentrant {
        MasterNode storage node = nodes[msg.sender];
        require(node.status == NodeStatus.Active, "Not active");
        require(block.timestamp >= node.unlockAt, "Still locked");

        // Settle earnings while still counted as active, then pay what we can
        _settle(msg.sender);
        _payout(msg.sender);

        NodeTier tier = node.tier;

        // Effects before interactions (CEI pattern)
        uint256 stakeReturn = node.stakedAmount;
        node.status = NodeStatus.Inactive;
        node.stakedAmount = 0;

        // Credit remaining tier members for the period that just ended
        _syncTier(tier);
        tiers[tier].activeNodes--;
        totalActiveNodes--;
        totalStaked -= stakeReturn;

        // Interaction
        (bool sent, ) = msg.sender.call{value: stakeReturn}("");
        require(sent, "Transfer failed");

        emit NodeDeregistered(msg.sender, stakeReturn);
    }

    /**
     * @notice Withdraw remaining stake after slashing
     */
    function withdrawSlashedStake() external nonReentrant {
        MasterNode storage node = nodes[msg.sender];
        require(node.status == NodeStatus.Slashed, "Not slashed");
        require(node.stakedAmount > 0, "Nothing to withdraw");

        uint256 stakeReturn = node.stakedAmount;
        node.stakedAmount = 0;
        node.status = NodeStatus.Inactive;
        totalStaked -= stakeReturn;

        (bool sent, ) = msg.sender.call{value: stakeReturn}("");
        require(sent, "Transfer failed");

        emit NodeDeregistered(msg.sender, stakeReturn);
    }

    // ============================================================
    //  Rewards
    // ============================================================

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external nonReentrant {
        _settle(msg.sender);
        _payout(msg.sender);
    }

    /**
     * @notice Reward this operator has earned but not yet been paid.
     * @dev Includes both already-settled and not-yet-settled earnings. What is
     *      actually payable right now is min(this, availableRewardFunds()).
     */
    function pendingReward(address _operator) public view returns (uint256) {
        MasterNode storage node = nodes[_operator];
        uint256 owed = node.pendingUnclaimed;
        if (node.status != NodeStatus.Active) return owed;

        TierConfig storage tc = tiers[node.tier];
        uint256 acc = accRewardPerNode[node.tier];

        // Mirror _syncTier without writing state
        uint256 last = tierLastUpdate[node.tier];
        if (block.timestamp > last && tc.activeNodes > 0 && currentRewardPerSecond > 0 && tc.rewardShare > 0) {
            uint256 tierPerSec = (currentRewardPerSecond * tc.rewardShare) / 10000;
            acc += (tierPerSec * (block.timestamp - last) * ACC_PRECISION) / tc.activeNodes;
        }

        if (acc > node.rewardDebt) {
            uint256 gross = (acc - node.rewardDebt) / ACC_PRECISION;
            owed += (gross * node.uptime) / 10000;
        }
        return owed;
    }

    /**
     * @notice What `claimRewards()` would actually pay right now.
     */
    function claimableNow(address _operator) external view returns (uint256) {
        uint256 owed = pendingReward(_operator);
        uint256 avail = availableRewardFunds();
        return owed < avail ? owed : avail;
    }

    /**
     * @notice Fund the reward pool. Anyone may top it up.
     */
    function fundRewardPool() external payable {
        require(msg.value > 0, "Nothing sent");
        totalRewardFunded += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value, address(this).balance - totalStaked);
    }

    // ============================================================
    //  Admin: Uptime & Slashing
    // ============================================================

    /**
     * @notice Update node uptime score (called by monitoring oracle)
     */
    function updateUptime(address _operator, uint256 _uptime) external onlyOwner nonReentrant {
        require(_uptime <= 10000, "Max 10000");
        require(_operator != address(0), "Zero address");
        MasterNode storage node = nodes[_operator];
        require(node.status == NodeStatus.Active, "Not active");

        // Lock in earnings at the OLD uptime before changing it
        _settle(_operator);
        node.uptime = _uptime;
        emit UptimeUpdated(_operator, _uptime);
    }

    /**
     * @notice Slash a node for misbehavior
     */
    function slashNode(address _operator, string calldata _reason) external onlyOwner nonReentrant {
        MasterNode storage node = nodes[_operator];
        require(node.status == NodeStatus.Active, "Not active");

        // Settle before the node leaves the active set — it keeps what it earned
        _settle(_operator);

        NodeTier tier = node.tier;
        TierConfig storage tc = tiers[tier];
        uint256 slashAmount = (node.stakedAmount * tc.slashPercent) / 10000;

        node.stakedAmount -= slashAmount;
        node.status = NodeStatus.Slashed;
        totalStaked -= slashAmount;

        _syncTier(tier);
        tc.activeNodes--;
        totalActiveNodes--;

        // Slashed stake stays in the contract and now sits above totalStaked,
        // so it becomes spendable reward budget. Raise the schedule cap to match.
        totalRewardPool += slashAmount;

        emit NodeSlashed(_operator, slashAmount, _reason);
    }

    // ============================================================
    //  Reward Year Management
    // ============================================================

    /**
     * @notice Advance to next reward year (callable by anyone after 365 days)
     */
    function advanceRewardYear() external {
        require(currentYear < 3, "All years completed");
        uint256 yearEnd = rewardStartTime + ((currentYear + 1) * 365 days);
        require(block.timestamp >= yearEnd, "Year not ended");

        // Settle every tier at the OLD rate before it changes
        _syncAllTiers();

        currentYear++;
        _updateRewardRate();

        emit RewardYearAdvanced(currentYear, currentRewardPerSecond);
    }

    function _updateRewardRate() internal {
        if (currentYear < 3) {
            currentRewardPerSecond = yearlyEmission[currentYear] / 365 days;
        } else {
            currentRewardPerSecond = 0;
        }
    }

    // ============================================================
    //  View Functions
    // ============================================================

    function getOperatorCount() external view returns (uint256) {
        return operators.length;
    }

    function getNodeInfo(address _operator) external view returns (MasterNode memory) {
        return nodes[_operator];
    }

    function getTierInfo(NodeTier _tier) external view returns (TierConfig memory) {
        return tiers[_tier];
    }

    function getNetworkStats() external view returns (
        uint256 _totalStaked,
        uint256 _totalActiveNodes,
        uint256 _totalRewardsDistributed,
        uint256 _remainingRewards,
        uint256 _currentRewardPerSecond,
        uint256 _currentYear
    ) {
        return (
            totalStaked,
            totalActiveNodes,
            totalRewardsDistributed,
            totalRewardPool - totalRewardsDistributed,
            currentRewardPerSecond,
            currentYear
        );
    }

    /**
     * @notice Reward pool funding status — lets a UI show real money, not a schedule.
     */
    function rewardPoolStatus() external view returns (
        uint256 _fundedBalance,
        uint256 _totalFunded,
        uint256 _distributed,
        uint256 _scheduleCap
    ) {
        uint256 bal = address(this).balance;
        return (
            bal > totalStaked ? bal - totalStaked : 0,
            totalRewardFunded,
            totalRewardsDistributed,
            totalRewardPool
        );
    }

    /**
     * @notice Get all active nodes (paginated)
     */
    function getActiveNodes(uint256 _offset, uint256 _limit) external view returns (MasterNode[] memory) {
        uint256 count = 0;
        uint256 total = operators.length;

        for (uint256 i = 0; i < total; i++) {
            if (nodes[operators[i]].status == NodeStatus.Active) count++;
        }

        if (_offset >= count) return new MasterNode[](0);
        uint256 end = _offset + _limit;
        if (end > count) end = count;
        uint256 size = end - _offset;

        MasterNode[] memory result = new MasterNode[](size);
        uint256 idx = 0;
        uint256 found = 0;

        for (uint256 i = 0; i < total && idx < size; i++) {
            if (nodes[operators[i]].status == NodeStatus.Active) {
                if (found >= _offset) {
                    result[idx] = nodes[operators[i]];
                    idx++;
                }
                found++;
            }
        }

        return result;
    }

    /**
     * @notice Check if an address is a Validator-tier node (real IBFT2 sealer)
     */
    function isValidator(address _operator) external view returns (bool) {
        MasterNode storage node = nodes[_operator];
        return node.status == NodeStatus.Active && node.tier == NodeTier.Validator;
    }

    /**
     * @notice Get count of active validators (IBFT2 sealers)
     */
    function activeValidatorCount() external view returns (uint256) {
        return tiers[NodeTier.Validator].activeNodes;
    }

    // ============================================================
    //  Admin Configuration
    // ============================================================

    function updateTierConfig(
        NodeTier _tier,
        uint256 _minStake,
        uint256 _maxNodes,
        uint256 _lockDays,
        uint256 _slashPercent,
        uint256 _rewardShare
    ) external onlyOwner {
        require(_slashPercent <= 5000, "Max 50% slash");
        require(_minStake > 0, "Min stake must be > 0");

        // Reward shares are about to change — settle every tier at the old split
        _syncAllTiers();

        TierConfig storage tc = tiers[_tier];
        tc.minStake = _minStake;
        tc.maxNodes = _maxNodes;
        tc.lockDays = _lockDays;
        tc.slashPercent = _slashPercent;
        tc.rewardShare = _rewardShare;

        // Validate total reward shares = 10000
        uint256 totalShares = tiers[NodeTier.Guardian].rewardShare
            + tiers[NodeTier.Sentinel].rewardShare
            + tiers[NodeTier.Light].rewardShare
            + tiers[NodeTier.Validator].rewardShare;
        require(totalShares == 10000, "Shares must sum to 10000");

        emit TierConfigUpdated(_tier);
    }

    /**
     * @notice Set the KYC contract address (required for Validator tier registration)
     */
    function setKYCContract(address _kycContract) external onlyOwner {
        kycContract = _kycContract;
        emit KYCContractUpdated(_kycContract);
    }

    /**
     * @notice Fund the reward pool by plain transfer.
     */
    receive() external payable {
        totalRewardFunded += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value, address(this).balance - totalStaked);
    }
}
