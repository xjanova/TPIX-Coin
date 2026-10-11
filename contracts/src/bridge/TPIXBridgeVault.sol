// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TPIXBridgeVault — คลังล็อก TPIX บน TPIX Chain (4289) ของสะพาน TPIX ↔ wTPIX (BSC)
 * @author Xman Studio
 * @notice TPIX → BSC: ผู้ใช้ส่ง TPIX เข้าสัญญานี้ (lock() หรือโอนตรงเข้าที่อยู่นี้) → event Locked
 *                     → เซิร์ฟเวอร์ mint wTPIX ให้ที่อยู่เดียวกันบน BSC ผ่าน WTPIXBridgeMinter
 *         BSC → TPIX: ผู้ใช้เผา wTPIX บน BSC → เซิร์ฟเวอร์เรียก release() ปล่อย TPIX จากคลังนี้
 *
 * ทำไมเป็นสัญญา ไม่ใช่กระเป๋าธรรมดาอย่างเดิม:
 *   เดิม TPIX ที่ล็อกทั้งหมดอยู่ในกระเป๋าที่คีย์อยู่บนเซิร์ฟเวอร์ — เซิร์ฟเวอร์โดนเจาะ = คลังหายทั้งก้อน
 *   และการส่งซ้ำ (retry หลัง timeout) จ่ายเงินซ้ำได้จริงเพราะไม่มีอะไรจำว่าจ่ายไปแล้ว
 *   ตอนนี้ relayer ปล่อยได้ไม่เกิน maxPerTx / dailyCap และ depositId เดียวปล่อยได้ครั้งเดียว
 *
 * ไม่มีทางให้เจ้าของถอนเงินออก — TPIX ออกจากคลังได้ทางเดียวคือ release() ที่มี depositId
 *   ถ้าต้องย้ายคลังในอนาคต ให้ relayer ปล่อยเข้าคลังใหม่ทีละวันภายใต้เพดานเดิม
 *   (ช้า แต่ไม่มีปุ่มไหนที่คนถือคีย์กดแล้วดูดคลังได้ในครั้งเดียว)
 *
 * ค่าธรรมเนียมสะพานไม่ถูกโอนออก — เซิร์ฟเวอร์ mint/release ยอดหลังหักค่าธรรมเนียม
 *   ส่วนต่างจึงค้างอยู่ในคลังเป็นส่วนเกิน: address(this).balance ≥ wTPIX.totalSupply() เสมอ
 *
 * ⚠️ คอมไพล์ด้วย evmVersion london เท่านั้น (เชน TPIX รัน PUSH0 ไม่ได้ — ดู hardhat.config.js)
 * ⚠️ โอนตรงเข้าที่อยู่นี้ต้องให้แก๊สเกิน 21000 (receive() เขียน storage + ยิง event)
 *    กระเป๋าที่ฟิกซ์แก๊ส 21000 จะ revert — เหรียญไม่หาย แต่ธุรกรรมไม่ผ่าน
 */
contract TPIXBridgeVault is Ownable2Step, Pausable, ReentrancyGuard {
    /// @notice ที่อยู่ที่ปล่อย TPIX ได้ (คีย์ relayer บนเซิร์ฟเวอร์)
    mapping(address => bool) public relayers;

    /// @notice ที่อยู่ที่สั่ง pause ได้
    mapping(address => bool) public guardians;

    /// @notice ยอดล็อกขั้นต่ำต่อครั้ง (wei) — ต่ำกว่านี้ค่าธรรมเนียมกินหมด กันเหรียญค้างในคลังโดยไม่มีใครได้อะไร
    uint256 public minLock;

    /// @notice ยอดล็อกสูงสุดต่อครั้ง (wei) — ต้องไม่เกิน maxPerTx ของ WTPIXBridgeMinter ฝั่ง BSC
    ///         ไม่งั้นล็อกได้แต่ mint ไม่ได้ เหรียญค้างจนกว่าเจ้าของจะขยายเพดานฝั่ง BSC
    uint256 public maxLock;

    /// @notice เพดานปล่อยต่อครั้ง (wei)
    uint256 public maxPerTx;

    /// @notice เพดานปล่อยต่อวัน UTC (wei)
    uint256 public dailyCap;

    /// @notice ยอดที่ปล่อยไปแล้วในแต่ละวัน — คีย์ = block.timestamp / 1 days
    mapping(uint256 => uint256) public releasedPerDay;

    /// @notice depositId ที่ปล่อยไปแล้ว — แหล่งความจริงเดียวของ "จ่ายไปแล้วหรือยัง"
    mapping(bytes32 => bool) public processed;

    /// @notice ลำดับการล็อก (เริ่มที่ 1) — ช่วยไล่ดู event ย้อนหลังได้ง่าย
    uint256 public lockNonce;

    /// @notice ยอดล็อกสะสมทั้งหมด / ยอดปล่อยสะสมทั้งหมด (ไว้กระทบยอดกับ wTPIX บน BSC)
    uint256 public totalLocked;
    uint256 public totalReleased;

    event Locked(address indexed from, uint256 amount, uint256 indexed nonce);
    event Released(
        address indexed relayer,
        address indexed to,
        uint256 amount,
        bytes32 indexed depositId,
        uint256 day,
        uint256 releasedThatDay
    );
    event RelayerSet(address indexed relayer, bool allowed);
    event GuardianSet(address indexed guardian, bool allowed);
    event LockLimitsUpdated(uint256 minLock, uint256 maxLock);
    event MaxPerTxUpdated(uint256 previous, uint256 current);
    event DailyCapUpdated(uint256 previous, uint256 current);

    error NotRelayer(address caller);
    error NotGuardian(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error EmptyDepositId();
    error AlreadyProcessed(bytes32 depositId);
    error BelowMinLock(uint256 amount, uint256 minLock);
    error AboveMaxLock(uint256 amount, uint256 maxLock);
    error InvalidLockLimits(uint256 minLock, uint256 maxLock);
    error InvalidCaps(uint256 maxPerTx, uint256 dailyCap);
    error ExceedsMaxPerTx(uint256 amount, uint256 maxPerTx);
    error ExceedsDailyCap(uint256 amount, uint256 remaining);
    error InsufficientVaultBalance(uint256 amount, uint256 balance);
    error TransferFailed(address to);
    error RenounceDisabled();

    /**
     * @param minLock_   ยอดล็อกขั้นต่ำ (wei) เช่น 10e18
     * @param maxLock_   ยอดล็อกสูงสุด (wei) เช่น 100_000e18 — ≤ maxPerTx ของตัว mint ฝั่ง BSC
     * @param maxPerTx_  เพดานปล่อยต่อครั้ง (wei) เช่น 100_000e18
     * @param dailyCap_  เพดานปล่อยต่อวัน (wei) เช่น 500_000e18
     */
    constructor(uint256 minLock_, uint256 maxLock_, uint256 maxPerTx_, uint256 dailyCap_) Ownable(msg.sender) {
        _checkLockLimits(minLock_, maxLock_);
        _checkCaps(maxPerTx_, dailyCap_);

        minLock = minLock_;
        maxLock = maxLock_;
        maxPerTx = maxPerTx_;
        dailyCap = dailyCap_;

        emit LockLimitsUpdated(minLock_, maxLock_);
        emit MaxPerTxUpdated(0, maxPerTx_);
        emit DailyCapUpdated(0, dailyCap_);
    }

    // =========================================================================
    // Lock (ผู้ใช้)
    // =========================================================================

    /// @notice โอน TPIX เข้าที่อยู่นี้ตรง ๆ = ล็อกให้ผู้โอน (แอปเดิมที่ส่งเข้า "treasury" ใช้ต่อได้)
    receive() external payable {
        _lock(msg.sender, msg.value);
    }

    /// @notice ล็อก TPIX เพื่อรับ wTPIX ที่ที่อยู่เดียวกันบน BSC
    function lock() external payable {
        _lock(msg.sender, msg.value);
    }

    function _lock(address from, uint256 amount) private {
        // หยุดอยู่ = ไม่รับเงินเข้าด้วย ไม่งั้นผู้ใช้ล็อกได้แต่ไม่มีใครมา mint ให้
        _requireNotPaused();
        if (amount < minLock) revert BelowMinLock(amount, minLock);
        if (amount > maxLock) revert AboveMaxLock(amount, maxLock);

        uint256 nonce = ++lockNonce;
        totalLocked += amount;

        emit Locked(from, amount, nonce);
    }

    // =========================================================================
    // Release (relayer)
    // =========================================================================

    /**
     * @notice ปล่อย TPIX ให้ผู้เผา wTPIX — เรียกหลังเซิร์ฟเวอร์ยืนยันการเผาบน BSC ที่ finalized แล้ว
     * @param to         ผู้รับบน TPIX Chain (= ที่อยู่ผู้เผาบน BSC)
     * @param amount     จำนวน (wei)
     * @param depositId  keccak256(abi.encode(56, txHash, logIndex)) ของ Transfer(to=0) ของ wTPIX
     */
    function release(address payable to, uint256 amount, bytes32 depositId) external whenNotPaused nonReentrant {
        if (!relayers[msg.sender]) revert NotRelayer(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (depositId == bytes32(0)) revert EmptyDepositId();
        if (processed[depositId]) revert AlreadyProcessed(depositId);
        if (amount > maxPerTx) revert ExceedsMaxPerTx(amount, maxPerTx);

        uint256 day = block.timestamp / 1 days;
        uint256 used = releasedPerDay[day];
        uint256 remaining = used >= dailyCap ? 0 : dailyCap - used;
        if (amount > remaining) revert ExceedsDailyCap(amount, remaining);

        uint256 balance = address(this).balance;
        if (amount > balance) revert InsufficientVaultBalance(amount, balance);

        // CEI: บันทึกทุกอย่างก่อนส่งเงินออก
        processed[depositId] = true;
        releasedPerDay[day] = used + amount;
        totalReleased += amount;

        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed(to);

        emit Released(msg.sender, to, amount, depositId, day, used + amount);
    }

    // =========================================================================
    // Views
    // =========================================================================

    function currentDay() external view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function remainingToday() external view returns (uint256) {
        uint256 used = releasedPerDay[block.timestamp / 1 days];
        return used >= dailyCap ? 0 : dailyCap - used;
    }

    // =========================================================================
    // Pause (guardian หรือ owner) / Unpause (owner เท่านั้น)
    // =========================================================================

    /// @notice หยุดทั้งรับล็อกและปล่อยเงินทันที
    function pause() external {
        if (!guardians[msg.sender] && msg.sender != owner()) revert NotGuardian(msg.sender);
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    // Admin (owner)
    // =========================================================================

    function setRelayer(address relayer, bool allowed) external onlyOwner {
        if (relayer == address(0)) revert ZeroAddress();
        relayers[relayer] = allowed;
        emit RelayerSet(relayer, allowed);
    }

    function setGuardian(address guardian, bool allowed) external onlyOwner {
        if (guardian == address(0)) revert ZeroAddress();
        guardians[guardian] = allowed;
        emit GuardianSet(guardian, allowed);
    }

    function setLockLimits(uint256 newMinLock, uint256 newMaxLock) external onlyOwner {
        _checkLockLimits(newMinLock, newMaxLock);
        minLock = newMinLock;
        maxLock = newMaxLock;
        emit LockLimitsUpdated(newMinLock, newMaxLock);
    }

    function setMaxPerTx(uint256 newMaxPerTx) external onlyOwner {
        _checkCaps(newMaxPerTx, dailyCap);
        emit MaxPerTxUpdated(maxPerTx, newMaxPerTx);
        maxPerTx = newMaxPerTx;
    }

    function setDailyCap(uint256 newDailyCap) external onlyOwner {
        _checkCaps(maxPerTx, newDailyCap);
        emit DailyCapUpdated(dailyCap, newDailyCap);
        dailyCap = newDailyCap;
    }

    /// @notice ปิดการสละความเป็นเจ้าของ — ไม่งั้นไม่มีใคร unpause หรือแก้เพดานได้อีก
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    function _checkLockLimits(uint256 minLock_, uint256 maxLock_) private pure {
        if (minLock_ == 0 || maxLock_ < minLock_) revert InvalidLockLimits(minLock_, maxLock_);
    }

    function _checkCaps(uint256 maxPerTx_, uint256 dailyCap_) private pure {
        if (maxPerTx_ == 0 || dailyCap_ == 0 || maxPerTx_ > dailyCap_) {
            revert InvalidCaps(maxPerTx_, dailyCap_);
        }
    }
}
