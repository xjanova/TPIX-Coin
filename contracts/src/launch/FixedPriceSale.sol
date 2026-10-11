// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FixedPriceSale — ขายเหรียญราคาคงที่ รับชำระด้วยเหรียญอีกตัว (เช่น USDT บนเชน TPIX)
 * @author Xman Studio
 * @notice presale ของเหรียญจาก TPIX Token Factory (ตัวแรก: IDTC ที่ $0.0000015 ต่อเหรียญ)
 *
 *   ราคา: tokensOut = payAmount × rateNumerator ÷ rateDenominator (ปัดลง)
 *         ฝังตั้งแต่ deploy เปลี่ยนไม่ได้ — เจ้าของขึ้นราคากลางรอบไม่ได้
 *   ส่งของทันที: ผู้ซื้อได้เหรียญใน tx เดียวกับที่จ่าย ไม่มีขั้น "รอเคลม" ให้ค้าง
 *   ไม่ถือเงิน: ค่าซื้อโอนตรงเข้า treasury ใน tx เดียวกัน สัญญาไม่มีเงินให้ใครขโมย
 *   เพดานรวมฝังตั้งแต่ deploy · เพดานต่อกระเป๋า/ขั้นต่ำปรับได้ · หยุดชั่วคราวได้
 *
 * เหรียญที่ขายต้องฝากเข้าสัญญาก่อนเปิดขาย (โอนตรงเข้า address นี้) — ขายเกินที่ฝากไม่ได้
 * รองรับเฉพาะเหรียญที่ไม่หักค่าตอนโอน (ทั้งเหรียญที่ขายและเหรียญที่รับ)
 */
contract FixedPriceSale is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable saleToken;
    IERC20 public immutable payToken;
    uint256 public immutable rateNumerator;
    uint256 public immutable rateDenominator;
    uint256 public immutable saleCap;

    address public treasury;
    uint64 public startTime;
    uint64 public endTime;
    uint256 public minPurchase;     // หน่วยของ payToken (0 = ไม่กำหนด)
    uint256 public maxPerWallet;    // หน่วยของ saleToken (0 = ไม่จำกัด)

    uint256 public sold;
    uint256 public raised;
    mapping(address => uint256) public purchased;

    event Purchased(address indexed buyer, uint256 payAmount, uint256 tokensOut);
    event TreasuryUpdated(address indexed treasury);
    event WindowUpdated(uint64 startTime, uint64 endTime);
    event LimitsUpdated(uint256 minPurchase, uint256 maxPerWallet);
    event UnsoldWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error BadConfig();
    error NotActive();
    error BelowMinimum();
    error ZeroOutput();
    error CapExceeded();
    error WalletLimitExceeded();
    error SaleNotOver();

    constructor(
        IERC20 saleToken_,
        IERC20 payToken_,
        uint256 rateNumerator_,
        uint256 rateDenominator_,
        uint256 saleCap_,
        address treasury_,
        uint64 startTime_,
        uint64 endTime_,
        address owner_
    ) Ownable(owner_) {
        if (address(saleToken_) == address(0) || address(payToken_) == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        if (address(saleToken_) == address(payToken_) || rateNumerator_ == 0 || rateDenominator_ == 0 || saleCap_ == 0) {
            revert BadConfig();
        }
        if (endTime_ <= startTime_) revert BadConfig();
        saleToken = saleToken_;
        payToken = payToken_;
        rateNumerator = rateNumerator_;
        rateDenominator = rateDenominator_;
        saleCap = saleCap_;
        treasury = treasury_;
        startTime = startTime_;
        endTime = endTime_;
    }

    // ─────────────────────────────── views ───────────────────────────────

    function quote(uint256 payAmount) public view returns (uint256) {
        return (payAmount * rateNumerator) / rateDenominator;
    }

    function isActive() public view returns (bool) {
        return !paused() && block.timestamp >= startTime && block.timestamp < endTime && sold < saleCap;
    }

    function remaining() external view returns (uint256) {
        return saleCap - sold;
    }

    // ─────────────────────────────── buy ───────────────────────────────

    function buy(uint256 payAmount) external nonReentrant whenNotPaused returns (uint256 tokensOut) {
        if (block.timestamp < startTime || block.timestamp >= endTime) revert NotActive();
        if (payAmount < minPurchase) revert BelowMinimum();
        tokensOut = quote(payAmount);
        if (tokensOut == 0) revert ZeroOutput();
        if (sold + tokensOut > saleCap) revert CapExceeded();
        uint256 bought = purchased[msg.sender] + tokensOut;
        if (maxPerWallet != 0 && bought > maxPerWallet) revert WalletLimitExceeded();

        // effects ก่อนแตะสัญญาภายนอก
        sold += tokensOut;
        raised += payAmount;
        purchased[msg.sender] = bought;

        payToken.safeTransferFrom(msg.sender, treasury, payAmount);
        saleToken.safeTransfer(msg.sender, tokensOut);
        emit Purchased(msg.sender, payAmount, tokensOut);
    }

    // ─────────────────────────────── owner ───────────────────────────────

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setWindow(uint64 startTime_, uint64 endTime_) external onlyOwner {
        if (endTime_ <= startTime_) revert BadConfig();
        startTime = startTime_;
        endTime = endTime_;
        emit WindowUpdated(startTime_, endTime_);
    }

    function setLimits(uint256 minPurchase_, uint256 maxPerWallet_) external onlyOwner {
        minPurchase = minPurchase_;
        maxPerWallet = maxPerWallet_;
        emit LimitsUpdated(minPurchase_, maxPerWallet_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice ถอนเหรียญที่ขายไม่หมด — ได้เฉพาะหลังปิดรอบหรือขณะหยุดชั่วคราว (ไม่กระทบผู้ซื้อ เพราะได้ของไปแล้ว)
    function withdrawUnsold(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (block.timestamp < endTime && !paused()) revert SaleNotOver();
        uint256 amount = saleToken.balanceOf(address(this));
        saleToken.safeTransfer(to, amount);
        emit UnsoldWithdrawn(to, amount);
    }
}
