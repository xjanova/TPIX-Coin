// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title RewardToken — ERC-20 with Reflection/Dividend + Vesting
 * @author Xman Studio
 * @notice Phase 2 — Reward token ที่แจก reward ให้ holders อัตโนมัติ
 *
 * Reward Types:
 *   0 = reflection  — แจกจาก fee ให้ holders ตามสัดส่วน (SafeMoon-style)
 *   1 = dividend     — เก็บ fee เข้า pool, holders claim เอง
 *   2 = staking      — เก็บ fee เข้า pool, ต้อง stake ก่อนถึง claim ได้
 *
 * Vesting: cliff + linear release สำหรับ lock tokens
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract RewardToken is ERC20, Ownable, Pausable {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    uint8 private immutable _decimals;
    bool public immutable isPausable;
    bool public immutable isBlacklistEnabled;
    bool public immutable isMintable;
    bool public immutable isBurnable;

    /// @notice Reward type: 0=reflection, 1=dividend, 2=staking
    uint8 public immutable rewardType;

    /// @notice Reward rate per transfer (basis points)
    uint16 public immutable rewardRateBps;

    /// @notice Minimum hold amount to receive rewards
    uint256 public immutable minHoldForReward;

    /// @notice Vesting cliff duration (seconds, 0 = no vesting)
    uint256 public immutable vestingCliff;

    /// @notice Vesting total duration (seconds, 0 = no vesting)
    uint256 public immutable vestingDuration;

    // ═══════════════════════════════════════════
    //  REFLECTION STATE (rOwned/tOwned dual accounting)
    // ═══════════════════════════════════════════

    uint256 private constant MAX = type(uint256).max;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    mapping(address => uint256) private _rOwned;
    mapping(address => bool) public isExcludedFromReward;
    address[] private _excludedFromReward;

    // ═══════════════════════════════════════════
    //  DIVIDEND STATE
    // ═══════════════════════════════════════════

    /// @notice Total dividends accumulated
    uint256 public totalDividends;

    /// @notice Magnitude for precision
    uint256 private constant MAGNITUDE = 2**128;

    /// @notice Dividend per share (scaled by MAGNITUDE)
    uint256 public dividendPerShare;

    /// @notice Dividend correction per address
    mapping(address => int256) private dividendCorrection;

    /// @notice Withdrawn dividends per address
    mapping(address => uint256) public withdrawnDividends;

    // ═══════════════════════════════════════════
    //  COMMON STATE
    // ═══════════════════════════════════════════

    mapping(address => bool) public blacklisted;
    mapping(address => bool) public isExcludedFromFee;

    // Vesting
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 released;
        uint256 startTime;
    }
    mapping(address => VestingSchedule) public vestingSchedules;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event RewardDistributed(uint256 amount);
    event DividendClaimed(address indexed account, uint256 amount);
    event VestingCreated(address indexed beneficiary, uint256 amount, uint256 startTime);
    event VestingReleased(address indexed beneficiary, uint256 amount);
    event Blacklisted(address indexed account, bool status);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        bool mintable_,
        bool burnable_,
        bool pausable_,
        bool blacklistEnabled_,
        uint8 rewardType_,
        uint16 rewardRateBps_,
        uint256 minHoldForReward_,
        uint256 vestingCliff_,
        uint256 vestingDuration_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(rewardType_ <= 2, "RT: invalid reward type");
        require(rewardRateBps_ <= 2500, "RT: reward rate > 25%");
        require(vestingDuration_ == 0 || vestingDuration_ >= vestingCliff_, "RT: duration < cliff");

        _decimals = decimals_;
        isMintable = mintable_;
        isBurnable = burnable_;
        isPausable = pausable_;
        isBlacklistEnabled = blacklistEnabled_;
        rewardType = rewardType_;
        rewardRateBps = rewardRateBps_;
        minHoldForReward = minHoldForReward_;
        vestingCliff = vestingCliff_;
        vestingDuration = vestingDuration_;

        // Exclude owner & contract from fees
        isExcludedFromFee[owner_] = true;
        isExcludedFromFee[address(this)] = true;

        if (totalSupply_ > 0) {
            if (rewardType_ == 0) {
                // Reflection: init rTotal
                _rTotal = (MAX - (MAX % totalSupply_));
                _rOwned[owner_] = _rTotal;
                // Exclude contract from reflection
                _excludeFromReward(address(this));
            }
            _mint(owner_, totalSupply_);
        }
    }

    // ═══════════════════════════════════════════
    //  ERC-20 OVERRIDES
    // ═══════════════════════════════════════════

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (rewardType == 0 && !isExcludedFromReward[account]) {
            // Reflection: balance from rOwned
            if (_rTotal == 0) return super.balanceOf(account);
            return _rOwned[account] / (_rTotal / totalSupply());
        }
        return super.balanceOf(account);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Mint/burn: skip all checks
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            // Update dividend tracking for dividend/staking
            if (rewardType >= 1) {
                _updateDividendTracking(from, to);
            }
            return;
        }

        // Pausable
        if (isPausable) _requireNotPaused();

        // Blacklist
        if (isBlacklistEnabled) {
            require(!blacklisted[from], "RT: sender blacklisted");
            require(!blacklisted[to], "RT: recipient blacklisted");
        }

        // Vesting check: ตรวจว่า sender มี locked tokens หรือไม่
        if (vestingDuration > 0 && vestingSchedules[from].totalAmount > 0) {
            uint256 locked = _lockedAmount(from);
            require(
                super.balanceOf(from) - locked >= value,
                "RT: exceeds unlocked balance"
            );
        }

        // Calculate reward fee
        uint256 feeAmount = 0;
        if (rewardRateBps > 0 && !isExcludedFromFee[from] && !isExcludedFromFee[to]) {
            feeAmount = (value * rewardRateBps) / 10000;
        }

        if (feeAmount > 0) {
            if (rewardType == 0) {
                // Reflection: deduct from rTotal
                uint256 rFee = feeAmount * (_rTotal / totalSupply());
                _rTotal -= rFee;
                _tFeeTotal += feeAmount;
                super._update(from, address(0), feeAmount); // burn for reflection
                emit RewardDistributed(feeAmount);
            } else {
                // Dividend/Staking: send to contract as reward pool
                super._update(from, address(this), feeAmount);
                _distributeDividends(feeAmount);
                emit RewardDistributed(feeAmount);
            }
        }

        super._update(from, to, value - feeAmount);

        // Update dividend tracking
        if (rewardType >= 1) {
            _updateDividendTracking(from, to);
        }
    }

    // ═══════════════════════════════════════════
    //  REFLECTION
    // ═══════════════════════════════════════════

    /// @notice Total reflection fees collected
    function totalReflectionFees() external view returns (uint256) {
        return _tFeeTotal;
    }

    function _excludeFromReward(address account) internal {
        if (!isExcludedFromReward[account]) {
            isExcludedFromReward[account] = true;
            _excludedFromReward.push(account);
        }
    }

    // ═══════════════════════════════════════════
    //  DIVIDEND
    // ═══════════════════════════════════════════

    function _distributeDividends(uint256 amount) internal {
        if (totalSupply() == 0) return;
        dividendPerShare += (amount * MAGNITUDE) / totalSupply();
        totalDividends += amount;
    }

    function _updateDividendTracking(address from, address to) internal {
        // Simple tracking update — ไม่ต้อง adjust เพราะใช้ running average
    }

    /// @notice Claim accumulated dividends
    function claimDividend() external {
        require(rewardType >= 1, "RT: not dividend mode");
        uint256 claimable = _withdrawableDividendOf(msg.sender);
        require(claimable > 0, "RT: no dividends");

        // Check minimum hold
        if (minHoldForReward > 0) {
            require(balanceOf(msg.sender) >= minHoldForReward, "RT: below min hold");
        }

        withdrawnDividends[msg.sender] += claimable;
        _transfer(address(this), msg.sender, claimable);
        emit DividendClaimed(msg.sender, claimable);
    }

    function _withdrawableDividendOf(address account) internal view returns (uint256) {
        if (balanceOf(account) == 0) return 0;
        uint256 accumulated = (balanceOf(account) * dividendPerShare) / MAGNITUDE;
        uint256 correction = uint256(
            dividendCorrection[account] >= 0
                ? uint256(dividendCorrection[account])
                : 0
        );
        uint256 total = accumulated + correction;
        return total > withdrawnDividends[account] ? total - withdrawnDividends[account] : 0;
    }

    /// @notice View claimable dividends
    function withdrawableDividendOf(address account) external view returns (uint256) {
        return _withdrawableDividendOf(account);
    }

    // ═══════════════════════════════════════════
    //  VESTING
    // ═══════════════════════════════════════════

    /// @notice Create vesting schedule for an address
    function createVesting(address beneficiary, uint256 amount) external onlyOwner {
        require(vestingDuration > 0, "RT: vesting disabled");
        require(vestingSchedules[beneficiary].totalAmount == 0, "RT: vesting exists");
        require(amount > 0, "RT: zero amount");

        // Transfer tokens to beneficiary (locked)
        _transfer(msg.sender, beneficiary, amount);

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            released: 0,
            startTime: block.timestamp
        });

        emit VestingCreated(beneficiary, amount, block.timestamp);
    }

    /// @notice Release vested tokens
    function releaseVested() external {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "RT: no vesting");

        uint256 releasable = _releasableAmount(msg.sender);
        require(releasable > 0, "RT: nothing to release");

        schedule.released += releasable;
        emit VestingReleased(msg.sender, releasable);
    }

    function _releasableAmount(address account) internal view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[account];
        if (schedule.totalAmount == 0) return 0;

        uint256 elapsed = block.timestamp - schedule.startTime;

        // ยังไม่ผ่าน cliff
        if (elapsed < vestingCliff) return 0;

        // ผ่าน vesting duration ทั้งหมด
        if (elapsed >= vestingDuration) {
            return schedule.totalAmount - schedule.released;
        }

        // Linear release หลัง cliff
        uint256 vested = (schedule.totalAmount * elapsed) / vestingDuration;
        return vested > schedule.released ? vested - schedule.released : 0;
    }

    function _lockedAmount(address account) internal view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[account];
        if (schedule.totalAmount == 0) return 0;

        uint256 releasable = _releasableAmount(account);
        uint256 totalUnlocked = schedule.released + releasable;
        return schedule.totalAmount > totalUnlocked
            ? schedule.totalAmount - totalUnlocked
            : 0;
    }

    /// @notice View locked amount
    function lockedAmountOf(address account) external view returns (uint256) {
        return _lockedAmount(account);
    }

    /// @notice View releasable amount
    function releasableAmountOf(address account) external view returns (uint256) {
        return _releasableAmount(account);
    }

    // ═══════════════════════════════════════════
    //  MINT / BURN
    // ═══════════════════════════════════════════

    function mint(address to, uint256 amount) external onlyOwner {
        require(isMintable, "RT: minting disabled");
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(isBurnable, "RT: burning disabled");
        _burn(msg.sender, amount);
    }

    // ═══════════════════════════════════════════
    //  OWNER FUNCTIONS
    // ═══════════════════════════════════════════

    function pause() external onlyOwner {
        require(isPausable, "RT: not pausable");
        _pause();
    }

    function unpause() external onlyOwner {
        require(isPausable, "RT: not pausable");
        _unpause();
    }

    function setBlacklist(address account, bool status) external onlyOwner {
        require(isBlacklistEnabled, "RT: blacklist disabled");
        require(account != owner(), "RT: cannot blacklist owner");
        blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }
}
