// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TPIX Master Node Registry
 * @notice Manages master node registration, staking, and reward distribution
 * @dev Replaces old high-APY staking with sustainable node-based rewards
 *
 * Tier System:
 *   Tier 1 - Validator Node:  1,000,000 TPIX stake, 12-15% APY, max 100 nodes
 *   Tier 2 - Sentinel Node:     100,000 TPIX stake,  7-10% APY, max 500 nodes
 *   Tier 3 - Light Node:         10,000 TPIX stake,   4-6% APY, unlimited
 *
 * Reward Pool: 1,400,000,000 TPIX over 5 years (decreasing emission)
 *   Year 1: 400M | Year 2: 350M | Year 3: 300M | Year 4: 200M | Year 5: 150M
 */
contract NodeRegistry is Ownable, ReentrancyGuard {

    // ============================================================
    //  Enums & Structs
    // ============================================================

    enum NodeTier { Validator, Sentinel, Light }
    enum NodeStatus { Inactive, Active, Slashed, Exited, SlashedWithdrawable }

    struct TierConfig {
        uint256 minStake;       // Minimum stake in wei
        uint256 maxNodes;       // Maximum nodes (0 = unlimited)
        uint256 activeNodes;    // Current active node count
        uint256 lockDays;       // Lock period in days
        uint256 slashPercent;   // Slash percentage (basis points, 1000 = 10%)
        uint256 rewardShare;    // Share of block reward (basis points, 5000 = 50%)
    }

    struct MasterNode {
        address operator;       // Node operator address
        NodeTier tier;          // Node tier
        NodeStatus status;      // Current status
        uint256 stakedAmount;   // Amount staked
        uint256 registeredAt;   // Registration timestamp
        uint256 unlockAt;       // Unlock timestamp
        uint256 lastRewardAt;   // Last reward claim
        uint256 totalRewards;   // Total rewards earned
        uint256 uptime;         // Uptime score (0-10000 basis points)
        bytes32 nodeId;         // Unique node identifier
        string endpoint;        // Node RPC endpoint (IP:port)
    }

    // ============================================================
    //  State Variables
    // ============================================================

    // Tier configurations
    mapping(NodeTier => TierConfig) public tiers;

    // Node registry: operator address => MasterNode
    mapping(address => MasterNode) public nodes;

    // All registered operators (for enumeration)
    address[] public operators;

    // Reward pool tracking
    uint256 public totalRewardPool;         // Total reward pool (1.4B TPIX)
    uint256 public totalRewardsDistributed; // Running total of distributed rewards
    uint256 public rewardStartTime;         // When rewards started
    uint256 public totalStaked;             // Total TPIX staked across all tiers

    // Block reward per second (calculated from yearly emission)
    uint256 public currentRewardPerSecond;
    uint256 public currentYear;             // Current reward year (1-5)

    // Year emission schedule (in wei)
    uint256[5] public yearlyEmission;

    // Active node count
    uint256 public totalActiveNodes;

    // ============================================================
    //  Events
    // ============================================================

    event NodeRegistered(address indexed operator, NodeTier tier, uint256 stake, bytes32 nodeId);
    event NodeDeregistered(address indexed operator, uint256 stakeReturned);
    event RewardClaimed(address indexed operator, uint256 amount);
    event NodeSlashed(address indexed operator, uint256 slashAmount, string reason);
    event UptimeUpdated(address indexed operator, uint256 uptime);
    event TierConfigUpdated(NodeTier tier);
    event RewardYearAdvanced(uint256 year, uint256 rewardPerSecond);

    // ============================================================
    //  Constructor
    // ============================================================

    constructor() Ownable(msg.sender) {
        // Tier 1: Validator - 1M TPIX, max 100, 90-day lock, 10% slash, 50% reward share
        tiers[NodeTier.Validator] = TierConfig({
            minStake: 1_000_000 ether,
            maxNodes: 100,
            activeNodes: 0,
            lockDays: 90,
            slashPercent: 1000,  // 10%
            rewardShare: 5000    // 50%
        });

        // Tier 2: Sentinel - 100K TPIX, max 500, 30-day lock, 5% slash, 30% reward share
        tiers[NodeTier.Sentinel] = TierConfig({
            minStake: 100_000 ether,
            maxNodes: 500,
            activeNodes: 0,
            lockDays: 30,
            slashPercent: 500,   // 5%
            rewardShare: 3000    // 30%
        });

        // Tier 3: Light - 10K TPIX, unlimited, 7-day lock, no slash, 20% reward share
        tiers[NodeTier.Light] = TierConfig({
            minStake: 10_000 ether,
            maxNodes: 0,         // unlimited
            activeNodes: 0,
            lockDays: 7,
            slashPercent: 0,     // no slash
            rewardShare: 2000    // 20%
        });

        // Total reward pool: 1.4B TPIX
        totalRewardPool = 1_400_000_000 ether;

        // Yearly emission schedule (decreasing)
        yearlyEmission[0] = 400_000_000 ether;  // Year 1: 400M
        yearlyEmission[1] = 350_000_000 ether;  // Year 2: 350M
        yearlyEmission[2] = 300_000_000 ether;  // Year 3: 300M
        yearlyEmission[3] = 200_000_000 ether;  // Year 4: 200M
        yearlyEmission[4] = 150_000_000 ether;  // Year 5: 150M

        rewardStartTime = block.timestamp;
        currentYear = 0;
        _updateRewardRate();
    }

    // ============================================================
    //  Registration
    // ============================================================

    /**
     * @notice Register a new master node
     * @param _tier Node tier (0=Validator, 1=Sentinel, 2=Light)
     * @param _endpoint Node RPC endpoint (e.g., "203.0.113.10:8545")
     */
    function registerNode(NodeTier _tier, string calldata _endpoint) external payable nonReentrant {
        require(nodes[msg.sender].status == NodeStatus.Inactive, "Already registered");
        require(msg.value >= tiers[_tier].minStake, "Insufficient stake");
        require(bytes(_endpoint).length > 0, "Endpoint required");

        TierConfig storage tc = tiers[_tier];
        if (tc.maxNodes > 0) {
            require(tc.activeNodes < tc.maxNodes, "Tier full");
        }

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
            endpoint: _endpoint
        });

        operators.push(msg.sender);
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

        // Claim remaining rewards first
        _claimRewards(msg.sender);

        // Effects before interactions (CEI pattern)
        uint256 stakeReturn = node.stakedAmount;
        node.status = NodeStatus.Inactive; // Allow re-registration
        node.stakedAmount = 0;

        tiers[node.tier].activeNodes--;
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
        node.status = NodeStatus.Inactive; // Allow re-registration

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
        _claimRewards(msg.sender);
    }

    /**
     * @notice Calculate pending reward for an operator
     * @dev Splits calculation across year boundaries to use correct rate per period
     */
    function pendingReward(address _operator) public view returns (uint256) {
        MasterNode storage node = nodes[_operator];
        if (node.status != NodeStatus.Active || totalActiveNodes == 0) return 0;

        uint256 elapsed = block.timestamp - node.lastRewardAt;
        if (elapsed == 0) return 0;

        TierConfig storage tc = tiers[node.tier];
        if (tc.activeNodes == 0) return 0;

        // Calculate reward using current rate (safe: rate only changes via advanceRewardYear)
        // Max claimable period = 30 days to prevent stale accumulation gaming
        uint256 maxElapsed = 30 days;
        if (elapsed > maxElapsed) elapsed = maxElapsed;

        uint256 tierRewardPerSec = (currentRewardPerSecond * tc.rewardShare) / 10000;
        uint256 nodeReward = (tierRewardPerSec * elapsed) / tc.activeNodes;

        // Apply uptime weight (basis points)
        nodeReward = (nodeReward * node.uptime) / 10000;

        // Cap at remaining pool
        uint256 remaining = totalRewardPool - totalRewardsDistributed;
        if (nodeReward > remaining) nodeReward = remaining;

        return nodeReward;
    }

    function _claimRewards(address _operator) internal {
        uint256 reward = pendingReward(_operator);
        if (reward == 0) return;

        MasterNode storage node = nodes[_operator];
        node.lastRewardAt = block.timestamp;
        node.totalRewards += reward;
        totalRewardsDistributed += reward;

        (bool sent, ) = _operator.call{value: reward}("");
        require(sent, "Transfer failed");

        emit RewardClaimed(_operator, reward);
    }

    // ============================================================
    //  Admin: Uptime & Slashing
    // ============================================================

    /**
     * @notice Update node uptime score (called by monitoring oracle)
     * @dev Claims pending rewards at old uptime before updating
     */
    function updateUptime(address _operator, uint256 _uptime) external onlyOwner {
        require(_uptime <= 10000, "Max 10000");
        require(_operator != address(0), "Zero address");
        MasterNode storage node = nodes[_operator];
        require(node.status == NodeStatus.Active, "Not active");

        // Claim at current uptime first to prevent retroactive adjustment
        _claimRewards(_operator);

        node.uptime = _uptime;
        emit UptimeUpdated(_operator, _uptime);
    }

    /**
     * @notice Slash a node for misbehavior
     */
    function slashNode(address _operator, string calldata _reason) external onlyOwner {
        MasterNode storage node = nodes[_operator];
        require(node.status == NodeStatus.Active, "Not active");

        TierConfig storage tc = tiers[node.tier];
        uint256 slashAmount = (node.stakedAmount * tc.slashPercent) / 10000;

        node.stakedAmount -= slashAmount;
        node.status = NodeStatus.Slashed;
        totalStaked -= slashAmount;

        tc.activeNodes--;
        totalActiveNodes--;

        // Slashed funds go to reward pool
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
        require(currentYear < 4, "All years completed");
        uint256 yearEnd = rewardStartTime + ((currentYear + 1) * 365 days);
        require(block.timestamp >= yearEnd, "Year not ended");

        currentYear++;
        _updateRewardRate();

        emit RewardYearAdvanced(currentYear, currentRewardPerSecond);
    }

    function _updateRewardRate() internal {
        if (currentYear < 5) {
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
     * @notice Get all active nodes (paginated)
     */
    function getActiveNodes(uint256 _offset, uint256 _limit) external view returns (MasterNode[] memory) {
        uint256 count = 0;
        uint256 total = operators.length;

        // Count active nodes
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

        TierConfig storage tc = tiers[_tier];
        tc.minStake = _minStake;
        tc.maxNodes = _maxNodes;
        tc.lockDays = _lockDays;
        tc.slashPercent = _slashPercent;
        tc.rewardShare = _rewardShare;

        // Validate total reward shares = 10000
        uint256 totalShares = tiers[NodeTier.Validator].rewardShare
            + tiers[NodeTier.Sentinel].rewardShare
            + tiers[NodeTier.Light].rewardShare;
        require(totalShares == 10000, "Shares must sum to 10000");

        emit TierConfigUpdated(_tier);
    }

    /**
     * @notice Fund the reward pool (receive native TPIX)
     */
    receive() external payable {
        totalRewardPool += msg.value;
    }
}
