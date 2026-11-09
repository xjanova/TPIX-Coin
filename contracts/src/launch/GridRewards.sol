// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title GridRewards — จ่ายรางวัลแนะนำเพื่อน IDTC Grid เป็นรอบ ด้วย Merkle root
 * @author Xman Studio
 * @notice เว็บ idtc.online คำนวณรางวัลจากยอดซื้อบนเชน (ถือครบระยะแล้ว) สร้างรายชื่อของรอบ
 *         แล้วเจ้าของประกาศเฉพาะ root ของรายชื่อขึ้นสัญญานี้ — สมาชิกกดรับเองด้วย proof
 *
 * ความปลอดภัย:
 *  - ประกาศรอบได้เมื่อสัญญามีเหรียญพอจ่าย "ทุกรอบที่ยังค้าง" รวมรอบใหม่แล้วเท่านั้น (outstanding)
 *  - leaf = keccak256(bytes.concat(keccak256(abi.encode(address(this), round, account, amount))))
 *    ผูกที่อยู่สัญญา + เลขรอบ → proof ใช้ข้ามรอบ/ข้ามสัญญาไม่ได้ · hash สองชั้นกัน second-preimage
 *  - addRound ระบุเลขรอบที่คาดไว้ (ต้องเท่ากับจำนวนรอบปัจจุบัน) → ธุรกรรมที่สร้างจากรายชื่อเก่าจะ revert
 *  - ใครก็กด claim แทนเจ้าของรางวัลได้ แต่เหรียญเข้ากระเป๋าในรายชื่อเท่านั้น · รับซ้ำไม่ได้
 *  - เจ้าของถอนได้เฉพาะส่วนเกินจากยอดค้างจ่าย · ยกเลิกรอบที่ประกาศผิดได้ (ส่วนที่ยังไม่รับคืนเป็นส่วนเกิน)
 *  - หยุดรับชั่วคราวได้ (pause) เมื่อพบรายชื่อผิด ระหว่างตรวจ
 */
contract GridRewards is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Round {
        bytes32 root;
        uint128 total;      // ยอดรวมของรอบ (หน่วยเล็กสุดของเหรียญ)
        uint128 claimed;    // รับไปแล้ว
        uint64 unlockAt;    // รับได้ตั้งแต่เวลานี้ (unix)
        uint64 addedAt;
        bool revoked;
    }

    IERC20 public immutable token;

    Round[] private _rounds;

    /// round => account => รับแล้ว
    mapping(uint256 => mapping(address => bool)) public claimed;

    /// ยอดที่ยังต้องจ่ายของทุกรอบที่ไม่ถูกยกเลิก
    uint256 public outstanding;

    event RoundAdded(uint256 indexed round, bytes32 root, uint256 total, uint64 unlockAt);
    event RoundRevoked(uint256 indexed round, uint256 unclaimed);
    event Claimed(uint256 indexed round, address indexed account, uint256 amount);
    event ExcessWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error WrongRoundId(uint256 expected, uint256 given);
    error EmptyRound();
    error AmountTooLarge();
    error Underfunded(uint256 balance, uint256 needed);
    error UnknownRound(uint256 round);
    error RoundRevokedError(uint256 round);
    error NotUnlocked(uint256 round, uint64 unlockAt);
    error AlreadyClaimed(uint256 round, address account);
    error InvalidProof();
    error LengthMismatch();
    error ExceedsExcess(uint256 excess, uint256 amount);

    constructor(IERC20 token_, address owner_) Ownable(owner_) {
        if (address(token_) == address(0)) revert ZeroAddress();
        token = token_;
    }

    // ───────────── อ่าน ─────────────

    function roundCount() external view returns (uint256) {
        return _rounds.length;
    }

    function rounds(uint256 id) external view returns (Round memory) {
        if (id >= _rounds.length) revert UnknownRound(id);
        return _rounds[id];
    }

    /// เหรียญในสัญญาที่เกินยอดค้างจ่าย (ถอนได้)
    function excess() public view returns (uint256) {
        uint256 bal = token.balanceOf(address(this));
        return bal > outstanding ? bal - outstanding : 0;
    }

    function leaf(uint256 round, address account, uint256 amount) public view returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(address(this), round, account, amount))));
    }

    function verify(uint256 round, address account, uint256 amount, bytes32[] calldata proof) external view returns (bool) {
        if (round >= _rounds.length) return false;
        return MerkleProof.verifyCalldata(proof, _rounds[round].root, leaf(round, account, amount));
    }

    // ───────────── เจ้าของ ─────────────

    /**
     * @param id        เลขรอบที่คาดไว้ = roundCount() ตอนสร้างรายชื่อ (กันส่งรายชื่อเก่าซ้ำ/สลับลำดับ)
     * @param unlockAt  รับได้ตั้งแต่เวลานี้ — 0 หรืออดีต = รับได้ทันที
     */
    function addRound(uint256 id, bytes32 root, uint256 total, uint64 unlockAt) external onlyOwner {
        if (id != _rounds.length) revert WrongRoundId(_rounds.length, id);
        if (root == bytes32(0) || total == 0) revert EmptyRound();
        if (total > type(uint128).max) revert AmountTooLarge();
        uint256 needed = outstanding + total;
        uint256 bal = token.balanceOf(address(this));
        if (bal < needed) revert Underfunded(bal, needed);

        outstanding = needed;
        _rounds.push(Round({
            root: root,
            total: uint128(total),
            claimed: 0,
            unlockAt: unlockAt,
            addedAt: uint64(block.timestamp),
            revoked: false
        }));
        emit RoundAdded(id, root, total, unlockAt);
    }

    /// ยกเลิกรอบที่ประกาศผิด — รับต่อไม่ได้ ส่วนที่ยังไม่มีใครรับกลายเป็นส่วนเกิน (ถอนได้)
    function revokeRound(uint256 id) external onlyOwner {
        if (id >= _rounds.length) revert UnknownRound(id);
        Round storage r = _rounds[id];
        if (r.revoked) revert RoundRevokedError(id);
        r.revoked = true;
        uint256 unclaimed = uint256(r.total) - uint256(r.claimed);
        outstanding -= unclaimed;
        emit RoundRevoked(id, unclaimed);
    }

    function withdrawExcess(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 ex = excess();
        if (amount > ex) revert ExceedsExcess(ex, amount);
        token.safeTransfer(to, amount);
        emit ExcessWithdrawn(to, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ───────────── รับรางวัล ─────────────

    function claim(uint256 round, address account, uint256 amount, bytes32[] calldata proof) external whenNotPaused nonReentrant {
        _claim(round, account, amount, proof);
    }

    /// รับหลายรอบในธุรกรรมเดียว (ของกระเป๋าเดียวกัน)
    function claimMany(uint256[] calldata roundIds, address account, uint256[] calldata amounts, bytes32[][] calldata proofs)
        external
        whenNotPaused
        nonReentrant
    {
        if (roundIds.length != amounts.length || roundIds.length != proofs.length) revert LengthMismatch();
        for (uint256 i = 0; i < roundIds.length; i++) {
            _claim(roundIds[i], account, amounts[i], proofs[i]);
        }
    }

    function _claim(uint256 id, address account, uint256 amount, bytes32[] calldata proof) private {
        if (id >= _rounds.length) revert UnknownRound(id);
        Round storage r = _rounds[id];
        if (r.revoked) revert RoundRevokedError(id);
        if (block.timestamp < r.unlockAt) revert NotUnlocked(id, r.unlockAt);
        if (claimed[id][account]) revert AlreadyClaimed(id, account);
        if (!MerkleProof.verifyCalldata(proof, r.root, leaf(id, account, amount))) revert InvalidProof();

        // รายชื่อผิด (รวมเกินยอดรอบ) ต้องไม่ดึงเหรียญของรอบอื่น — ตรวจก่อนแปลงเป็น uint128
        if (amount > uint256(r.total) - uint256(r.claimed)) revert AmountTooLarge();

        claimed[id][account] = true;
        r.claimed += uint128(amount);
        outstanding -= amount;
        token.safeTransfer(account, amount);
        emit Claimed(id, account, amount);
    }
}
