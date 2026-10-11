// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @dev ส่วนของ USDT_TPIX ที่ตัวนี้ต้องใช้ — ประกาศ interface เองแทนการ import ตัวสัญญา
 *      เพราะ USDT_TPIX ถูกคอมไพล์และตรวจไปแล้วบน 0.8.20 ถ้า import เข้ามา hardhat
 *      จะพยายามคอมไพล์มันใหม่ในงานเดียวกันด้วยคอมไพเลอร์ของไฟล์นี้ (0.8.24)
 */
interface IUSDT_TPIX_Bridge {
    function bridgeMint(address to, uint256 amount, bytes32 sourceTxHash) external;

    function processedTxHashes(bytes32 sourceTxHash) external view returns (bool);
}

/**
 * @title TPIXBridgeMinter — ด่านจำกัดอัตราการ mint ของสะพาน USDT → TPIX Chain
 * @author Xman Studio
 * @notice ตัวนี้ต้องเป็น "ที่อยู่เดียว" ที่ USDT_TPIX.bridges[...] = true
 *         relayer (คีย์บนเซิร์ฟเวอร์) mint ผ่านตัวนี้เท่านั้น ไม่มีสิทธิ์ mint ที่ตัวเหรียญตรง ๆ
 *
 * ทำไมต้องมีชั้นนี้ (แทนที่จะ setBridge(relayer) ตรง ๆ):
 *   USDT_TPIX ไม่มีเพดาน supply — ถ้าคีย์ relayer หลุด คนร้าย mint ได้ไม่จำกัด
 *   แล้วเทขายใส่พูล TPIX/USDT ดูดสภาพคล่องจริงออกไปหมดภายในไม่กี่บล็อก
 *   ชั้นนี้ทำให้ความเสียหายสูงสุดต่อวันถูกจำกัดไว้ที่ dailyCap และ guardian
 *   (ตัวกระทบยอดบนเซิร์ฟเวอร์) สั่งหยุดได้ทันทีที่ supply เกินเงินหนุนจริง
 *
 * บทบาท:
 *   owner     — คีย์เย็นของเจ้าของ (Ownable2Step) ตั้งเพดาน/relayer/guardian และเป็นคนเดียวที่ unpause ได้
 *   relayer   — คีย์บนเซิร์ฟเวอร์ mint ได้ภายใต้ maxPerTx + dailyCap
 *   guardian  — สั่ง pause ได้อย่างเดียว (ปลด pause ไม่ได้) — คีย์หลุดก็ทำได้แค่หยุดสะพาน ไม่ทำให้เงินหาย
 *
 * วงเงินรายวันนับเป็นช่วงวันตาม UTC (block.timestamp / 1 days) — ไม่ใช่หน้าต่างเลื่อน 24 ชม.
 *   แลกความเรียบง่ายกับกรณีขอบ: ข้ามเที่ยงคืน UTC mint ได้สูงสุด 2 × dailyCap ในเวลาสั้น ๆ
 *   ซึ่งยังเป็นเพดานที่รู้ล่วงหน้า และตัวกระทบยอดทุก 5 นาทีจะจับส่วนที่ไม่มีเงินหนุนได้อยู่ดี
 *
 * การกัน mint ซ้ำอยู่ที่ USDT_TPIX.processedTxHashes (depositId ซ้ำ = revert ทั้งธุรกรรม
 * ตัวนับวงเงินของที่นี่จึงย้อนกลับไปด้วย ไม่มีการกินโควตาฟรี)
 */
contract TPIXBridgeMinter is Ownable2Step, Pausable {
    /// @notice USDT_TPIX ที่ตัวนี้ mint ให้ — ตั้งครั้งเดียวตอน deploy
    IUSDT_TPIX_Bridge public immutable token;

    /// @notice ที่อยู่ที่ mint ได้ (คีย์ relayer บนเซิร์ฟเวอร์)
    mapping(address => bool) public relayers;

    /// @notice ที่อยู่ที่สั่ง pause ได้ (ตัวเฝ้ากระทบยอดบนเซิร์ฟเวอร์ / ทีมงาน)
    mapping(address => bool) public guardians;

    /// @notice เพดานต่อครั้ง (หน่วยเล็กสุดของ USDT_TPIX = 6 ทศนิยม)
    uint256 public maxPerTx;

    /// @notice เพดานต่อวัน UTC (6 ทศนิยม)
    uint256 public dailyCap;

    /// @notice ยอดที่ mint ไปแล้วในแต่ละวัน — คีย์ = block.timestamp / 1 days
    mapping(uint256 => uint256) public mintedPerDay;

    /// @notice ยอด mint สะสมผ่านตัวนี้ทั้งหมด (ไว้ตรวจกับ USDT_TPIX.totalEverMinted)
    uint256 public totalMinted;

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
    error InvalidCaps(uint256 maxPerTx, uint256 dailyCap);
    error ExceedsMaxPerTx(uint256 amount, uint256 maxPerTx);
    error ExceedsDailyCap(uint256 amount, uint256 remaining);
    error RenounceDisabled();

    /**
     * @param token_     ที่อยู่ USDT_TPIX (ต้องมีโค้ดอยู่จริง)
     * @param maxPerTx_  เพดานต่อครั้ง (6 ทศนิยม) เช่น 1_000e6
     * @param dailyCap_  เพดานต่อวัน (6 ทศนิยม) เช่น 5_000e6 — ต้องไม่น้อยกว่า maxPerTx_
     */
    constructor(address token_, uint256 maxPerTx_, uint256 dailyCap_) Ownable(msg.sender) {
        if (token_ == address(0)) revert ZeroAddress();
        // กันพิมพ์ที่อยู่ผิดเป็นกระเป๋าธรรมดา — deploy แล้วแก้ไม่ได้เพราะ token เป็น immutable
        require(token_.code.length > 0, "TPIXBridgeMinter: token has no code");
        _checkCaps(maxPerTx_, dailyCap_);

        token = IUSDT_TPIX_Bridge(token_);
        maxPerTx = maxPerTx_;
        dailyCap = dailyCap_;

        emit MaxPerTxUpdated(0, maxPerTx_);
        emit DailyCapUpdated(0, dailyCap_);
    }

    // =========================================================================
    // Mint (relayer)
    // =========================================================================

    /**
     * @notice mint USDT_TPIX ให้ผู้ฝาก — เรียกหลังเซิร์ฟเวอร์ยืนยัน deposit บนเชนต้นทางที่ finalized แล้ว
     * @param to         ผู้รับบน TPIX Chain (= ที่อยู่ผู้โอนบนเชนต้นทาง)
     * @param amount     จำนวน (6 ทศนิยม)
     * @param depositId  keccak256(abi.encode(chainId, txHash, logIndex)) ของ deposit — กัน mint ซ้ำที่ตัวเหรียญ
     */
    function mint(address to, uint256 amount, bytes32 depositId) external whenNotPaused {
        if (!relayers[msg.sender]) revert NotRelayer(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (depositId == bytes32(0)) revert EmptyDepositId();
        if (amount > maxPerTx) revert ExceedsMaxPerTx(amount, maxPerTx);

        uint256 day = block.timestamp / 1 days;
        uint256 used = mintedPerDay[day];
        // ลดเพดานต่ำกว่ายอดที่ใช้ไปแล้วได้ (เช่นตอนเกิดเหตุ) — เหลือศูนย์ ไม่ใช่ underflow
        uint256 remaining = used >= dailyCap ? 0 : dailyCap - used;
        if (amount > remaining) revert ExceedsDailyCap(amount, remaining);

        // CEI: อัปเดตตัวนับก่อนเรียกออกไปข้างนอก
        mintedPerDay[day] = used + amount;
        totalMinted += amount;

        // depositId ซ้ำ → USDT_TPIX revert "txhash replayed" → ตัวนับข้างบนย้อนกลับตาม
        token.bridgeMint(to, amount, depositId);

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

    /// @notice depositId นี้ถูก mint ไปแล้วหรือยัง (อ่านจากตัวเหรียญซึ่งเป็นแหล่งความจริงเดียว)
    function isProcessed(bytes32 depositId) external view returns (bool) {
        return token.processedTxHashes(depositId);
    }

    // =========================================================================
    // Pause (guardian หรือ owner) / Unpause (owner เท่านั้น)
    // =========================================================================

    /**
     * @notice หยุด mint ทันที — guardian ใช้เมื่อกระทบยอดแล้วพบ supply เกินเงินหนุน
     * @dev pause ซ้ำตอนหยุดอยู่แล้วจะ revert (EnforcedPause) ตามพฤติกรรมของ OZ
     *      ผู้เรียกฝั่งเซิร์ฟเวอร์ต้องอ่าน paused() ก่อน
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
     *         สะพานจะค้างถาวร (ย้ายเจ้าของใช้ transferOwnership + acceptOwnership แทน)
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
