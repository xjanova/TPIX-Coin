// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @dev ส่วนของ wTPIX (WTPIX_BEP20.sol) ที่ตัวนี้ต้องใช้ — ประกาศ interface เองแทนการ import
 *      ด้วยเหตุผลเดียวกับ TPIXBridgeMinter: ไม่ให้ hardhat ลากตัวเหรียญมาคอมไพล์ใหม่ในงานเดียวกัน
 */
interface IWTPIX_BEP20 {
    function mint(address to, uint256 amount) external;
}

/**
 * @title WTPIXBridgeMinter — ด่านจำกัดอัตราการ mint wTPIX บน BSC (สะพาน TPIX Chain → BSC)
 * @author Xman Studio
 * @notice ตัวนี้ต้องเป็น "ที่อยู่เดียว" ที่ wTPIX.minters[...] = true
 *         relayer (คีย์บนเซิร์ฟเวอร์) mint ผ่านตัวนี้เท่านั้น ไม่มีสิทธิ์ mint ที่ตัวเหรียญตรง ๆ
 *
 * ทำไมต้องมีชั้นนี้ (แทนที่จะ setMinter(relayer) ตรง ๆ):
 *   wTPIX มีเพดานแค่ MAX_SUPPLY 700M — ถ้าคีย์ relayer หลุด คนร้าย mint ได้ถึง 700M ในบล็อกเดียว
 *   แล้วเทขายใส่พูล PancakeSwap ดูดสภาพคล่องจริงออกไปหมด
 *   ชั้นนี้ทำให้ความเสียหายสูงสุดต่อวันถูกจำกัดไว้ที่ dailyCap และ guardian สั่งหยุดได้ทันที
 *
 * ต่างจาก TPIXBridgeMinter (ฝั่ง USDT) ตรงที่ wTPIX ไม่มีตัวกันซ้ำในตัวเหรียญ
 *   → เก็บ depositId ที่ mint ไปแล้วไว้ที่นี่เอง (processed) — relayer ลองซ้ำกี่รอบก็ mint ได้ครั้งเดียว
 *   นี่คือสิ่งที่ทำให้เซิร์ฟเวอร์ "ลองใหม่ได้อย่างปลอดภัย" เมื่อไม่รู้ว่ารอบก่อนส่งออกไปแล้วหรือยัง
 *
 * บทบาท:
 *   owner     — คีย์เย็นของเจ้าของ (Ownable2Step) ตั้งเพดาน/relayer/guardian และเป็นคนเดียวที่ unpause ได้
 *   relayer   — คีย์บนเซิร์ฟเวอร์ mint ได้ภายใต้ maxPerTx + dailyCap
 *   guardian  — สั่ง pause ได้อย่างเดียว (ปลด pause ไม่ได้) — คีย์หลุดก็ทำได้แค่หยุดสะพาน ไม่ทำให้เงินหาย
 *
 * วงเงินรายวันนับเป็นช่วงวันตาม UTC (block.timestamp / 1 days) — ไม่ใช่หน้าต่างเลื่อน 24 ชม.
 *   ข้ามเที่ยงคืน UTC mint ได้สูงสุด 2 × dailyCap ในเวลาสั้น ๆ ซึ่งยังเป็นเพดานที่รู้ล่วงหน้า
 *
 * depositId = keccak256(abi.encode(chainIdต้นทาง, txHash, logIndex)) ของ event Locked ใน TPIXBridgeVault
 */
contract WTPIXBridgeMinter is Ownable2Step, Pausable {
    /// @notice wTPIX ที่ตัวนี้ mint ให้ — ตั้งครั้งเดียวตอน deploy
    IWTPIX_BEP20 public immutable token;

    /// @notice ที่อยู่ที่ mint ได้ (คีย์ relayer บนเซิร์ฟเวอร์)
    mapping(address => bool) public relayers;

    /// @notice ที่อยู่ที่สั่ง pause ได้ (ตัวเฝ้ากระทบยอดบนเซิร์ฟเวอร์ / ทีมงาน)
    mapping(address => bool) public guardians;

    /// @notice เพดานต่อครั้ง (wei, 18 ทศนิยม)
    uint256 public maxPerTx;

    /// @notice เพดานต่อวัน UTC (wei, 18 ทศนิยม)
    uint256 public dailyCap;

    /// @notice ยอดที่ mint ไปแล้วในแต่ละวัน — คีย์ = block.timestamp / 1 days
    mapping(uint256 => uint256) public mintedPerDay;

    /// @notice ยอด mint สะสมผ่านตัวนี้ทั้งหมด (ไว้กระทบยอดกับ TPIXBridgeVault.totalLocked)
    uint256 public totalMinted;

    /// @notice depositId ที่ mint ไปแล้ว — แหล่งความจริงเดียวของ "ทำไปแล้วหรือยัง"
    mapping(bytes32 => bool) public processed;

    event RelayerSet(address indexed relayer, bool allowed);
    event GuardianSet(address indexed guardian, bool allowed);
    event MaxPerTxUpdated(uint256 previous, uint256 current);
    event DailyCapUpdated(uint256 previous, uint256 current);
    event BridgeMinted(
        address indexed relayer,
        address indexed to,
        uint256 amount,
        bytes32 indexed depositId,
        uint256 day,
        uint256 mintedThatDay
    );

    error NotRelayer(address caller);
    error NotGuardian(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error EmptyDepositId();
    error AlreadyProcessed(bytes32 depositId);
    error InvalidCaps(uint256 maxPerTx, uint256 dailyCap);
    error ExceedsMaxPerTx(uint256 amount, uint256 maxPerTx);
    error ExceedsDailyCap(uint256 amount, uint256 remaining);
    error RenounceDisabled();

    /**
     * @param token_     ที่อยู่ wTPIX (ต้องมีโค้ดอยู่จริง)
     * @param maxPerTx_  เพดานต่อครั้ง (wei) เช่น 100_000e18
     * @param dailyCap_  เพดานต่อวัน (wei) เช่น 500_000e18 — ต้องไม่น้อยกว่า maxPerTx_
     */
    constructor(address token_, uint256 maxPerTx_, uint256 dailyCap_) Ownable(msg.sender) {
        if (token_ == address(0)) revert ZeroAddress();
        // กันพิมพ์ที่อยู่ผิดเป็นกระเป๋าธรรมดา — deploy แล้วแก้ไม่ได้เพราะ token เป็น immutable
        require(token_.code.length > 0, "WTPIXBridgeMinter: token has no code");
        _checkCaps(maxPerTx_, dailyCap_);

        token = IWTPIX_BEP20(token_);
        maxPerTx = maxPerTx_;
        dailyCap = dailyCap_;

        emit MaxPerTxUpdated(0, maxPerTx_);
        emit DailyCapUpdated(0, dailyCap_);
    }

    // =========================================================================
    // Mint (relayer)
    // =========================================================================

    /**
     * @notice mint wTPIX ให้ผู้ล็อก TPIX — เรียกหลังเซิร์ฟเวอร์ยืนยัน event Locked บน TPIX Chain แล้ว
     * @param to         ผู้รับบน BSC (= ที่อยู่ผู้ล็อกบน TPIX Chain)
     * @param amount     จำนวน (wei)
     * @param depositId  keccak256(abi.encode(4289, txHash, logIndex)) ของ event Locked
     */
    function mint(address to, uint256 amount, bytes32 depositId) external whenNotPaused {
        if (!relayers[msg.sender]) revert NotRelayer(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (depositId == bytes32(0)) revert EmptyDepositId();
        if (processed[depositId]) revert AlreadyProcessed(depositId);
        if (amount > maxPerTx) revert ExceedsMaxPerTx(amount, maxPerTx);

        uint256 day = block.timestamp / 1 days;
        uint256 used = mintedPerDay[day];
        // ลดเพดานต่ำกว่ายอดที่ใช้ไปแล้วได้ (เช่นตอนเกิดเหตุ) — เหลือศูนย์ ไม่ใช่ underflow
        uint256 remaining = used >= dailyCap ? 0 : dailyCap - used;
        if (amount > remaining) revert ExceedsDailyCap(amount, remaining);

        // CEI: บันทึกทุกอย่างก่อนเรียกออกไปข้างนอก
        processed[depositId] = true;
        mintedPerDay[day] = used + amount;
        totalMinted += amount;

        token.mint(to, amount);

        emit BridgeMinted(msg.sender, to, amount, depositId, day, used + amount);
    }

    // =========================================================================
    // Views
    // =========================================================================

    /// @notice เลขวัน UTC ปัจจุบัน (คีย์ของ mintedPerDay)
    function currentDay() external view returns (uint256) {
        return block.timestamp / 1 days;
    }

    /// @notice โควตาที่เหลือของวันนี้ — เซิร์ฟเวอร์ถามก่อนเซ็นจะได้ไม่ส่งธุรกรรมที่รู้อยู่แล้วว่าจะ revert
    function remainingToday() external view returns (uint256) {
        uint256 used = mintedPerDay[block.timestamp / 1 days];
        return used >= dailyCap ? 0 : dailyCap - used;
    }

    // =========================================================================
    // Pause (guardian หรือ owner) / Unpause (owner เท่านั้น)
    // =========================================================================

    /**
     * @notice หยุด mint ทันที — guardian ใช้เมื่อกระทบยอดแล้วพบ wTPIX เกิน TPIX ที่ล็อกจริง
     * @dev pause ซ้ำตอนหยุดอยู่แล้วจะ revert (EnforcedPause) ตามพฤติกรรมของ OZ
     */
    function pause() external {
        if (!guardians[msg.sender] && msg.sender != owner()) revert NotGuardian(msg.sender);
        _pause();
    }

    /// @notice เปิดใหม่ได้เฉพาะเจ้าของ — guardian ที่คีย์หลุดจะได้ปลดล็อกเองไม่ได้
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

    /**
     * @notice ปิดการสละความเป็นเจ้าของ — ถ้าเผลอเรียกแล้วไม่มีใคร unpause หรือแก้เพดานได้อีกเลย
     *         (ย้ายเจ้าของใช้ transferOwnership + acceptOwnership แทน)
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    function _checkCaps(uint256 maxPerTx_, uint256 dailyCap_) private pure {
        if (maxPerTx_ == 0 || dailyCap_ == 0 || maxPerTx_ > dailyCap_) {
            revert InvalidCaps(maxPerTx_, dailyCap_);
        }
    }
}
