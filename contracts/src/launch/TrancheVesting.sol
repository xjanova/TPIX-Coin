// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TrancheVesting — ล็อกเหรียญเป็นก้อน แล้วปลดเป็นงวดเท่า ๆ กันหลังครบล็อก
 * @author Xman Studio
 * @notice ใช้กับเหรียญจาก TPIX Token Factory (ตัวแรก: IDTC ล็อก 70%) — ไม่มีเจ้าของ ไม่มีปุ่มถอนก่อนกำหนด
 *         ตารางล็อกฝังตั้งแต่ deploy แล้วแก้ไม่ได้อีก ใครก็กด release() ได้ แต่เหรียญไปที่ beneficiary เท่านั้น
 *
 * แต่ละก้อน (tranche):  [start ──── ล็อก cliffPeriods งวด ────][ ปลด releasePeriods งวด ]
 *   ปลดงวดแรกเมื่อครบ cliff + 1 งวด และครบทั้งก้อนเมื่อครบ cliff + releasePeriods งวด
 *   ตัวอย่าง IDTC (period = 1 เดือนเฉลี่ย):  ก้อน "ล็อก 1 ปี" = cliff 12 · ปลด 12 → ทยอยเดือน 13–24
 *
 * ทำไมไม่ปลดทีเดียวทั้งก้อน: ปลด 20% ของ supply ในวันเดียว = เหรียญหมุนเวียนพุ่งทันที
 * ทยอยรายงวดทำให้แรงขายจากการปลดล็อกกระจายตัว ไม่มี "วันปลดก้อนใหญ่"
 */
contract TrancheVesting is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Tranche {
        uint256 amount;         // จำนวนเหรียญของก้อน (หน่วยเล็กสุดของเหรียญ)
        uint32 cliffPeriods;    // ล็อกเต็มกี่งวดนับจาก start
        uint32 releasePeriods;  // ปลดเท่า ๆ กันกี่งวดหลังครบล็อก (อย่างน้อย 1)
    }

    uint256 public constant MAX_TRANCHES = 12;
    uint32 public constant MAX_PERIODS = 240;

    IERC20 public immutable token;
    uint64 public immutable start;
    uint64 public immutable period;
    uint256 public immutable totalAllocation;
    string public label;

    address public beneficiary;
    address public pendingBeneficiary;
    uint256 public released;

    Tranche[] private _tranches;

    event Released(address indexed to, uint256 amount);
    event BeneficiaryTransferStarted(address indexed from, address indexed to);
    event BeneficiaryTransferred(address indexed from, address indexed to);
    event ExcessSwept(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error BadSchedule();
    error NothingToRelease();
    error NotBeneficiary();
    error NotPendingBeneficiary();
    error NoExcess();

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert NotBeneficiary();
        _;
    }

    /**
     * @param token_        เหรียญที่ล็อก
     * @param beneficiary_  ผู้รับเมื่อปลด (เปลี่ยนได้โดย beneficiary เองแบบสองขั้น เช่น ย้ายไป multisig)
     * @param start_        เวลาเริ่มนับ (unix) — ใช้วันเปิดตลาด
     * @param period_       ความยาวงวด (วินาที) เช่น 2,629,800 = เดือนเฉลี่ย (365.25 วัน / 12)
     * @param tranches_     ตารางก้อน
     * @param label_        ชื่อแสดงผล เช่น "IDTC — ล็อก 70%"
     */
    constructor(
        IERC20 token_,
        address beneficiary_,
        uint64 start_,
        uint64 period_,
        Tranche[] memory tranches_,
        string memory label_
    ) {
        if (address(token_) == address(0) || beneficiary_ == address(0)) revert ZeroAddress();
        if (period_ == 0 || tranches_.length == 0 || tranches_.length > MAX_TRANCHES) revert BadSchedule();

        uint256 total;
        for (uint256 i = 0; i < tranches_.length; i++) {
            Tranche memory t = tranches_[i];
            if (t.amount == 0 || t.releasePeriods == 0 || t.releasePeriods > MAX_PERIODS || t.cliffPeriods > MAX_PERIODS) {
                revert BadSchedule();
            }
            total += t.amount;
            _tranches.push(t);
        }

        token = token_;
        beneficiary = beneficiary_;
        start = start_;
        period = period_;
        totalAllocation = total;
        label = label_;
    }

    // ─────────────────────────────── views ───────────────────────────────

    function trancheCount() external view returns (uint256) {
        return _tranches.length;
    }

    function tranche(uint256 index) external view returns (Tranche memory) {
        return _tranches[index];
    }

    /// @notice ยอดที่ปลดแล้วทั้งหมด (รวมที่ release ไปแล้ว) ณ เวลา timestamp
    function vestedAmount(uint64 timestamp) public view returns (uint256 total) {
        for (uint256 i = 0; i < _tranches.length; i++) {
            Tranche memory t = _tranches[i];
            uint256 cliffEnd = uint256(start) + uint256(t.cliffPeriods) * period;
            if (timestamp <= cliffEnd) continue;
            uint256 elapsed = (uint256(timestamp) - cliffEnd) / period;
            total += elapsed >= t.releasePeriods ? t.amount : (t.amount * elapsed) / t.releasePeriods;
        }
    }

    /// @notice ยอดที่กด release() ได้ตอนนี้
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice ยอดที่ยังล็อกอยู่ (ยังไม่ถึงเวลาปลด)
    function lockedAmount() external view returns (uint256) {
        return totalAllocation - vestedAmount(uint64(block.timestamp));
    }

    /// @notice เหรียญในสัญญาพอจ่ายตามตารางที่เหลือไหม — หน้าเว็บใช้แสดง "ล็อกครบจริง"
    function isFunded() public view returns (bool) {
        return token.balanceOf(address(this)) >= totalAllocation - released;
    }

    /// @notice งวดถัดไปที่จะปลด: เวลา + จำนวนรวมทุกก้อนที่ปลดพร้อมกันในเวลานั้น (0,0 = ปลดครบแล้ว)
    function nextUnlock() external view returns (uint64 at, uint256 amount) {
        uint256 best = type(uint256).max;
        for (uint256 i = 0; i < _tranches.length; i++) {
            uint256 t = _nextInstantOf(_tranches[i]);
            if (t != 0 && t < best) best = t;
        }
        if (best == type(uint256).max) return (0, 0);
        // จำนวนที่ปลด ณ เวลานั้น = vested(best) − vested(best − 1)
        amount = vestedAmount(uint64(best)) - vestedAmount(uint64(best - 1));
        at = uint64(best);
    }

    function _nextInstantOf(Tranche memory t) private view returns (uint256) {
        uint256 cliffEnd = uint256(start) + uint256(t.cliffPeriods) * period;
        uint256 lastInstant = cliffEnd + uint256(t.releasePeriods) * period;
        if (block.timestamp >= lastInstant) return 0;
        if (block.timestamp < cliffEnd + period) return cliffEnd + period;
        uint256 elapsed = (block.timestamp - cliffEnd) / period;
        return cliffEnd + (elapsed + 1) * period;
    }

    // ─────────────────────────────── actions ───────────────────────────────

    /// @notice ปลดยอดที่ถึงเวลาแล้วไปที่ beneficiary — ใครเรียกก็ได้
    function release() external nonReentrant {
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();
        released += amount;
        address to = beneficiary;
        token.safeTransfer(to, amount);
        emit Released(to, amount);
    }

    function transferBeneficiary(address newBeneficiary) external onlyBeneficiary {
        if (newBeneficiary == address(0)) revert ZeroAddress();
        pendingBeneficiary = newBeneficiary;
        emit BeneficiaryTransferStarted(beneficiary, newBeneficiary);
    }

    function acceptBeneficiary() external {
        if (msg.sender != pendingBeneficiary) revert NotPendingBeneficiary();
        emit BeneficiaryTransferred(beneficiary, msg.sender);
        beneficiary = msg.sender;
        pendingBeneficiary = address(0);
    }

    /**
     * @notice คืนเหรียญที่ส่งเข้ามาเกินตาราง หรือเหรียญอื่นที่ส่งผิดเข้ามา — ไม่แตะยอดที่ต้องล็อกเด็ดขาด
     */
    function sweepExcess(IERC20 other) external onlyBeneficiary nonReentrant {
        uint256 amount;
        if (address(other) == address(token)) {
            uint256 obligation = totalAllocation - released;
            uint256 bal = token.balanceOf(address(this));
            if (bal <= obligation) revert NoExcess();
            amount = bal - obligation;
        } else {
            amount = other.balanceOf(address(this));
            if (amount == 0) revert NoExcess();
        }
        other.safeTransfer(beneficiary, amount);
        emit ExcessSwept(address(other), beneficiary, amount);
    }
}
