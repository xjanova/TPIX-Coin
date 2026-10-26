// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
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
 * Reward Pool: 1,400,000,000 TPIX over 3 years from deployment
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
 *  place that changes a tier's active-node count, the emission rate, a tier's
 *  reward share, min stake or APR cap MUST settle the accumulator first — see
 *  `_syncTier` callers.
 *
 *  APR CAP (2026-10 audit) — per-node accrual is
 *      min( tierEmissionPerSec / activeNodes , minStake * tierAprCapBps / 365 days )
 *  Without the cap the emission is split only among whoever is staked, so the
 *  first lone Light node (10K stake) would earn 15% of 600M/yr = 90M TPIX/yr
 *  (~900,000% APR) and drain the funded pool. The emission schedule is now a
 *  ceiling; the advertised APR is the normal case.
 *
 *  EXACT STAKE — rewards are equal per node inside a tier, so registerNode
 *  requires msg.value == minStake; over-staking would only lock money for nothing.
 *  For the same reason a tier's minStake can only change while it has no active
 *  nodes: the APR cap is computed from the tier's minStake, not each node's own
 *  stake (and a huge minStake would overflow the cap math and freeze the tier).
 *
 *  OWNER POWERS — the owner can NOT withdraw stake or reward funds (no such
 *  function exists). It can: pause NEW registrations (exits/claims never pause),
 *  set uptime (multiplier on future rewards), slash a node (capped at the slash %
 *  in force when that node registered; slashed TPIX stays in the contract as
 *  reward budget), change tier terms for future registrations (min stake only
 *  while the tier has no active nodes; lock <= MAX_LOCK_DAYS, slash <= MAX_SLASH_BPS),
 *  set APR caps (<= 50%), the KYC contract and the uptime oracle.
 *  Ownership moves in two steps (Ownable2Step): the new owner must accept.
 *
 *  REGISTRATION TERMS — the signer supplies the maximum lock and slash they
 *  accepted and a deadline. An owner changing terms before inclusion cannot
 *  exceed those limits. The old unprotected registration selector is absent.
 *  REWARD CLOCK — accrual integrates each scheduled year and stops after year 3,
 *  even if nobody calls advanceRewardYear. Views use the same clock and math.
 *
 *  UPTIME ORACLE — a hot key the server can hold to report whether nodes really
 *  run. It can only set uptime (a multiplier on FUTURE rewards; never principal,
 *  never what is already earned). While an oracle is set, new nodes start at 0%
 *  uptime and earn nothing until the oracle reports them running; with no oracle
 *  they start at 100% (plain staking).
 * ─────────────────────────────────────────────────────────────────────────
 */
contract NodeRegistryV2 is Ownable2Step, ReentrancyGuard {

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
    uint256 private constant YEAR = 365 days;
    uint256 public constant MAX_APR_CAP_BPS = 5000;   // เพดานของเพดาน — ตั้ง APR เกิน 50% ไม่ได้
    // เพดานเงื่อนไขที่ owner แทรกก่อน tx สมัครได้ (ดูหัวไฟล์) = ค่าสูงสุดที่ใช้จริง (ชั้น Validator)
    uint256 public constant MAX_SLASH_BPS = 1500;
    uint256 public constant MAX_LOCK_DAYS = 180;
    // uptime ทีละชุด — 100 โหนดวัดจริงกรณีแพงสุดราว 4.6M จากเพดานบล็อก 10M
    uint256 public constant MAX_UPTIME_BATCH = 100;

    // Tier configurations
    mapping(NodeTier => TierConfig) public tiers;

    // Node registry: operator address => MasterNode
    mapping(address => MasterNode) internal nodes;

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
    uint256 private lastAnnouncedRewardYear; // Event checkpoint only; never drives accrual

    // Year emission schedule (in wei) — 3 years
    uint256[3] public yearlyEmission;

    // Active node count
    uint256 public totalActiveNodes;

    // Validator KYC contract reference (optional, set by admin)
    address public kycContract;

    // APR สูงสุดที่โหนด 1 ตัวของแต่ละชั้นได้ (basis points ของ minStake ชั้นนั้น)
    // ไม่มีตัวนี้ = โหนดแรกของชั้นกินส่วนแบ่ง emission ทั้งก้อนคนเดียว (ดูหัวไฟล์)
    mapping(NodeTier => uint256) public tierAprCapBps;

    // หยุดรับโหนดใหม่ชั่วคราว (เช่นเจอปัญหาหลัง deploy) — ไม่กระทบการถอน/เคลม
    // A fresh deployment must be configured and verified before accepting stake.
    bool public registrationPaused = true;

    // % slash ที่มีผลตอนโหนดนั้นสมัคร (basis points) — owner ขึ้น % ทีหลังแล้ว
    // ย้อนไปปรับคนที่สมัครไว้ก่อนแรงกว่าที่เขายอมรับไว้ไม่ได้
    mapping(address => uint256) public nodeSlashCapBps;

    // กุญแจที่ตั้งได้แค่ uptime — ให้เซิร์ฟเวอร์รายงานว่าโหนดรันจริงโดยไม่ต้องถือกุญแจ owner
    address public uptimeOracle;

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
    event RegistrationPaused(bool paused);
    event TierAprCapUpdated(NodeTier tier, uint256 aprBps);
    event UptimeOracleUpdated(address indexed oracle);

    modifier onlyOwnerOrUptimeOracle() {
        require(
            msg.sender == owner() || (uptimeOracle != address(0) && msg.sender == uptimeOracle),
            "Not owner or uptime oracle"
        );
        _;
    }

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

        // APR สูงสุดต่อโหนด = ขอบบนของช่วงที่หน้าเว็บ/แอปโฆษณาไว้
        // (Light 4-6%, Sentinel 7-9%, Guardian 10-12%, Validator 15-20%)
        tierAprCapBps[NodeTier.Guardian] = 1200;
        tierAprCapBps[NodeTier.Sentinel] = 900;
        tierAprCapBps[NodeTier.Light] = 600;
        tierAprCapBps[NodeTier.Validator] = 2000;

        // Emission schedule cap — NOT a balance. Funds arrive via fundRewardPool().
        totalRewardPool = 1_400_000_000 ether;
        yearlyEmission[0] = 600_000_000 ether;
        yearlyEmission[1] = 500_000_000 ether;
        yearlyEmission[2] = 300_000_000 ether;

        rewardStartTime = block.timestamp;

        tierLastUpdate[NodeTier.Guardian] = block.timestamp;
        tierLastUpdate[NodeTier.Sentinel] = block.timestamp;
        tierLastUpdate[NodeTier.Light] = block.timestamp;
        tierLastUpdate[NodeTier.Validator] = block.timestamp;
    }

    // ============================================================
    //  Reward accounting internals
    // ============================================================

    /**
     * @dev Accrue across scheduled reward years with the current tier terms and
     *      node count. Settle before changing those terms or membership so past
     *      time cannot be paid at tomorrow's terms.
     */
    function _syncTier(NodeTier _tier) internal {
        uint256 last = tierLastUpdate[_tier];
        if (block.timestamp <= last) return;

        accRewardPerNode[_tier] += _accruedPerNodeScaled(_tier, last, block.timestamp);
        tierLastUpdate[_tier] = block.timestamp;
    }

    // At most three intervals, regardless of how late the next transaction is.
    // Tier parameters and membership are constant since tierLastUpdate because
    // every setter/join/exit settles the accumulator before changing them.
    function _accruedPerNodeScaled(NodeTier _tier, uint256 from, uint256 to) internal view returns (uint256 accrued) {
        uint256 count = tiers[_tier].activeNodes;
        if (count == 0 || to <= from) return 0;
        for (uint256 year = 0; year < 3; year++) {
            uint256 start = rewardStartTime + year * YEAR;
            uint256 end = start + YEAR;
            uint256 left = from > start ? from : start;
            uint256 right = to < end ? to : end;
            if (right > left) {
                accrued += _perNodeRateAt(_tier, count, yearlyEmission[year] / YEAR) * (right - left);
            }
        }
    }

    /**
     * @dev Reward per second for ONE node of `_tier` when the tier has `_nodes`
     *      active nodes, scaled by ACC_PRECISION, before the uptime multiplier.
     *      = min(tier emission / nodes, minStake * APR cap / year)
     */
    function _perNodeRateScaled(NodeTier _tier, uint256 _nodes) internal view returns (uint256) {
        return _perNodeRateAt(_tier, _nodes, currentRewardPerSecond());
    }

    function _perNodeRateAt(NodeTier _tier, uint256 _nodes, uint256 rate) internal view returns (uint256) {
        if (_nodes == 0 || rate == 0) return 0;
        TierConfig storage tc = tiers[_tier];
        if (tc.rewardShare == 0) return 0;

        uint256 tierPerSec = (rate * tc.rewardShare) / 10000;
        uint256 share = (tierPerSec * ACC_PRECISION) / _nodes;
        uint256 cap = (tc.minStake * tierAprCapBps[_tier] * ACC_PRECISION) / (10000 * YEAR);
        return share < cap ? share : cap;
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
    function registerNode(
        NodeTier _tier, string calldata _endpoint,
        uint256 _maxLockDays, uint256 _maxSlashBps, uint256 _deadline
    ) external payable nonReentrant {
        require(block.timestamp <= _deadline, "Registration expired");
        require(tiers[_tier].lockDays <= _maxLockDays, "Lock terms changed");
        require(tiers[_tier].slashPercent <= _maxSlashBps, "Slash terms changed");
        require(!registrationPaused, "Registration paused");
        require(nodes[msg.sender].status == NodeStatus.Inactive, "Already registered");
        require(nodes[msg.sender].pendingUnclaimed == 0, "Claim pending rewards first");
        require(msg.value >= tiers[_tier].minStake, "Insufficient stake");
        // รางวัลหารเท่ากันต่อโหนด — ส่งเกินขั้นต่ำไม่ได้อะไรเพิ่ม มีแต่เงินถูกล็อกฟรี ๆ
        require(msg.value == tiers[_tier].minStake, "Stake must equal tier minimum");
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
            // มี oracle = ต้องพิสูจน์ว่ารันเครื่องจริงก่อนถึงได้รางวัล · ไม่มี = staking ล้วน 100%
            uptime: uptimeOracle == address(0) ? 10000 : 0,
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

        // จำ % slash ณ วันที่สมัคร — slashNode ใช้ค่าที่ต่ำกว่าระหว่างนี้กับค่าปัจจุบัน
        nodeSlashCapBps[msg.sender] = tc.slashPercent;

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

        uint256 acc = accRewardPerNode[node.tier];

        // Mirror _syncTier without writing state
        uint256 last = tierLastUpdate[node.tier];
        if (block.timestamp > last) {
            acc += _accruedPerNodeScaled(node.tier, last, block.timestamp);
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
     * @notice Update node uptime score (owner or the uptime oracle)
     */
    function updateUptime(address _operator, uint256 _uptime) external onlyOwnerOrUptimeOracle nonReentrant {
        require(_uptime <= 10000, "Max 10000");
        require(_operator != address(0), "Zero address");
        require(nodes[_operator].status == NodeStatus.Active, "Not active");
        _setUptime(_operator, _uptime);
    }

    /**
     * @notice Update many nodes in one tx. Nodes that are no longer active (exited or
     *         slashed since the oracle read the list) are skipped, not reverted on —
     *         one stale entry must not stop everyone else's update.
     */
    function updateUptimeBatch(address[] calldata _operators, uint256[] calldata _uptimes)
        external
        onlyOwnerOrUptimeOracle
        nonReentrant
    {
        require(_operators.length == _uptimes.length, "Length mismatch");
        require(_operators.length <= MAX_UPTIME_BATCH, "Batch too large");
        for (uint256 i = 0; i < _operators.length; i++) {
            require(_uptimes[i] <= 10000, "Max 10000");
            if (nodes[_operators[i]].status != NodeStatus.Active) continue;
            _setUptime(_operators[i], _uptimes[i]);
        }
    }

    function _setUptime(address _operator, uint256 _uptime) internal {
        // Lock in earnings at the OLD uptime before changing it
        _settle(_operator);
        nodes[_operator].uptime = _uptime;
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
        // ใช้ % ที่ต่ำกว่าระหว่าง "ตอนสมัคร" กับ "ตอนนี้" — owner ลดได้ แต่เพิ่มย้อนหลังไม่ได้
        uint256 cap = nodeSlashCapBps[_operator];
        uint256 pct = tc.slashPercent < cap ? tc.slashPercent : cap;
        uint256 slashAmount = (node.stakedAmount * pct) / 10000;

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
     * @notice Emit the current reward year and settle all tiers. Optional keeper
     *         checkpoint only: time-based rewards never depend on this call.
     */
    function advanceRewardYear() external {
        require(lastAnnouncedRewardYear < 3, "All years completed");
        uint256 year = currentYear();
        require(year > lastAnnouncedRewardYear, "Year not ended");
        _syncAllTiers();
        lastAnnouncedRewardYear = year;
        emit RewardYearAdvanced(year, currentRewardPerSecond());
    }

    function currentYear() public view returns (uint256) {
        uint256 year = (block.timestamp - rewardStartTime) / YEAR;
        return year < 3 ? year : 3;
    }

    function currentRewardPerSecond() public view returns (uint256) {
        uint256 year = currentYear();
        return year < 3 ? yearlyEmission[year] / YEAR : 0;
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
            currentRewardPerSecond(),
            currentYear()
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
     * @notice Active operator addresses (paginated) — read each with getNodeInfo().
     * @dev Returns addresses, not MasterNode structs: the struct-array ABI encoder
     *      alone pushed the deploy transaction past the 32KB request-body limit of
     *      the public RPC proxy (rpc1.tpix.online → nginx client_max_body_size 32k).
     */
    function getActiveOperators(uint256 _offset, uint256 _limit) external view returns (address[] memory result) {
        uint256 total = operators.length;
        uint256 count = 0;
        for (uint256 i = 0; i < total; i++) {
            if (nodes[operators[i]].status == NodeStatus.Active) count++;
        }
        if (_offset >= count) return new address[](0);
        uint256 end = _offset + _limit;
        if (end > count) end = count;

        result = new address[](end - _offset);
        uint256 idx = 0;
        uint256 found = 0;
        for (uint256 i = 0; i < total && idx < result.length; i++) {
            address op = operators[i];
            if (nodes[op].status == NodeStatus.Active) {
                if (found >= _offset) result[idx++] = op;
                found++;
            }
        }
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

    /**
     * @notice Wei per second accruing to ONE node of `_tier` at 100% uptime —
     *         right now, and if one more node joined (what a new staker gets).
     * @dev APR (bps) = rate * 365 days * 10000 / minStake. UIs use this instead
     *      of hardcoded APY ranges.
     */
    function nodeRewardRate(NodeTier _tier) external view returns (uint256 currentPerNode, uint256 ifOneMoreJoins) {
        uint256 active = tiers[_tier].activeNodes;
        currentPerNode = _perNodeRateScaled(_tier, active) / ACC_PRECISION;
        ifOneMoreJoins = _perNodeRateScaled(_tier, active + 1) / ACC_PRECISION;
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
        // Global ceilings supplement the tighter limits signed by each applicant.
        require(_slashPercent <= MAX_SLASH_BPS, "Max 15% slash");
        require(_minStake > 0, "Min stake must be > 0");
        require(_lockDays <= MAX_LOCK_DAYS, "Max 180-day lock");

        // Reward shares are about to change — settle every tier at the old split
        _syncAllTiers();

        TierConfig storage tc = tiers[_tier];
        // เพดาน APR คิดจาก minStake ของชั้น ไม่ใช่เงินต้นของแต่ละโหนด — เปลี่ยนตอนมีโหนดอยู่
        // = โหนดเดิมได้ APR ผิดจากเงินต้นจริง และค่ามหาศาลทำให้สูตรล้น → ถอน/เคลมค้างถาวร
        require(_minStake == tc.minStake || tc.activeNodes == 0, "Tier has active nodes");
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
     * @notice Rebalance the reward split between tiers in ONE call.
     * @dev updateTierConfig() checks the four shares sum to 10000 after changing
     *      a single tier, so moving share from one tier to another through it is
     *      impossible (the first call always breaks the sum). This is the only
     *      way to change the split.
     */
    function setRewardShares(
        uint256 _guardian,
        uint256 _sentinel,
        uint256 _light,
        uint256 _validator
    ) external onlyOwner {
        require(_guardian + _sentinel + _light + _validator == 10000, "Shares must sum to 10000");
        // เวลาที่ผ่านมาแล้วต้องคิดด้วยสัดส่วนเดิมทุกชั้น
        _syncAllTiers();
        tiers[NodeTier.Guardian].rewardShare = _guardian;
        tiers[NodeTier.Sentinel].rewardShare = _sentinel;
        tiers[NodeTier.Light].rewardShare = _light;
        tiers[NodeTier.Validator].rewardShare = _validator;
        emit TierConfigUpdated(NodeTier.Guardian);
        emit TierConfigUpdated(NodeTier.Sentinel);
        emit TierConfigUpdated(NodeTier.Light);
        emit TierConfigUpdated(NodeTier.Validator);
    }

    /**
     * @notice Max APR one node of `_tier` can earn (bps of the tier's minStake).
     */
    function setTierAprCap(NodeTier _tier, uint256 _aprBps) external onlyOwner {
        require(_aprBps > 0 && _aprBps <= MAX_APR_CAP_BPS, "APR cap out of range");
        // เวลาที่ผ่านมาแล้วต้องคิดด้วยเพดานเดิม
        _syncTier(_tier);
        tierAprCapBps[_tier] = _aprBps;
        emit TierAprCapUpdated(_tier, _aprBps);
    }

    /**
     * @notice Stop/allow NEW registrations. Deregister, claim and withdraw are
     *         never paused — stakers can always get their money out.
     */
    function setRegistrationPaused(bool _paused) external onlyOwner {
        registrationPaused = _paused;
        emit RegistrationPaused(_paused);
    }

    /**
     * @notice Set the KYC contract address (required for Validator tier registration)
     */
    function setKYCContract(address _kycContract) external onlyOwner {
        kycContract = _kycContract;
        emit KYCContractUpdated(_kycContract);
    }

    /**
     * @notice Set (or clear with address(0)) the key allowed to report uptime.
     */
    function setUptimeOracle(address _oracle) external onlyOwner {
        uptimeOracle = _oracle;
        emit UptimeOracleUpdated(_oracle);
    }

    /**
     * @notice Fund the reward pool by plain transfer.
     */
    receive() external payable {
        totalRewardFunded += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value, address(this).balance - totalStaked);
    }
}
