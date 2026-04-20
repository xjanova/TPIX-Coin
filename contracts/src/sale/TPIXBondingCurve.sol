// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title TPIX Bonding Curve Sale
 * @author Xman Studio
 * @notice Fair-launch token sale ที่ราคาขึ้นเรื่อยๆ ตาม supply ที่ขายได้ (linear curve)
 *         Team ไม่ต้อง provide liquidity ก่อน — user ที่ bridge USDT มาเป็นคน fund pool
 *
 * Design:
 *   - Linear price curve: price(x) = startPrice + (endPrice - startPrice) × (sold / saleSupply)
 *   - Buy: user ส่ง USDT → contract คำนวณ TPIX ตาม curve → ส่ง TPIX กลับ
 *   - Sell: user ส่ง TPIX กลับ → contract คำนวณ USDT (- exit fee) → ส่ง USDT
 *   - Migration: เมื่อยอดขาย TPIX หรือ USDT ระดมได้ ถึง threshold → owner trigger
 *     migrate() ส่ง USDT + TPIX ไป Liquidity wallet เพื่อสร้าง DEX pool
 *
 * Tokenomics (ตาม WHITEPAPER.md):
 *   - Sale supply: 700M TPIX (10% ของ total) — fund จาก Token Sale wallet
 *   - Starting price: $0.10 (ตาม Public Sale phase)
 *   - End price: $1.00 (10x จาก start)
 *   - Migration threshold: $5M raised หรือ 350M TPIX sold (อันแรกถึง trigger)
 *
 * Trust signals:
 *   - All parameters set at deploy + fewer ที่เปลี่ยนได้ (price curve immutable)
 *   - Owner สามารถ migrate ได้แต่ส่งไป preset wallet เท่านั้น (admin ปรับไม่ได้กลางทาง)
 *   - Pausable เผื่อ emergency
 *   - Reentrancy guarded
 */
contract TPIXBondingCurve is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Immutable params
    // =========================================================================

    /// @notice ERC-20 ของ TPIX (wrapped) ที่ขาย — set at deploy
    IERC20 public immutable tpix;

    /// @notice USDT_TPIX ที่ใช้ pay — set at deploy
    IERC20 public immutable usdt;

    /// @notice ที่อยู่ Liquidity wallet (จาก WP) — รับ token+USDT หลัง migrate
    address public immutable liquidityWallet;

    /// @notice Sale supply (700M TPIX × 10^18)
    uint256 public immutable saleSupply;

    /// @notice Starting price ($0.10 = 100_000 ใน 6-decimal USDT)
    /// @dev USDT 6 decimals — $0.10 = 0.10 × 10^6 = 100_000
    uint256 public immutable startPrice;

    /// @notice End price ($1.00 = 1_000_000 ใน 6-decimal USDT)
    uint256 public immutable endPrice;

    /// @notice Migration threshold ใน USDT raised (default 5M = 5_000_000 × 10^6)
    uint256 public immutable migrationUsdtThreshold;

    /// @notice Migration threshold ใน TPIX sold (default 350M × 10^18)
    uint256 public immutable migrationTpixThreshold;

    /// @notice Exit fee เมื่อ sell back (basis points, max 1000 = 10%)
    /// @dev ป้องกัน price manipulation + ทำให้ buyers ระยะยาวได้ผลดี
    uint256 public constant EXIT_FEE_BPS = 500; // 5%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // =========================================================================
    // Mutable state
    // =========================================================================

    /// @notice TPIX ที่ขายไปแล้ว (track by buy - sell)
    uint256 public totalSold;

    /// @notice USDT ระดมได้ทั้งหมด (track by buy)
    uint256 public totalRaised;

    /// @notice Migration เกิดขึ้นแล้วหรือยัง — true = sale ปิด, รอ DEX pool
    bool public migrated;

    /// @notice Buyer history สำหรับ analytics + airdrop ในอนาคต
    mapping(address => uint256) public bought;

    // =========================================================================
    // Events
    // =========================================================================

    event Bought(address indexed buyer, uint256 usdtIn, uint256 tpixOut, uint256 newPrice);
    event Sold(address indexed seller, uint256 tpixIn, uint256 usdtOut, uint256 fee, uint256 newPrice);
    event Migrated(uint256 usdtToLiquidity, uint256 tpixToLiquidity, uint256 tpixUnsold);
    event ThresholdReached(string reason, uint256 raised, uint256 sold);

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @param _tpix ERC-20 TPIX wrapped (จะ deposit หลัง deploy)
     * @param _usdt USDT_TPIX address
     * @param _liquidityWallet wallet ที่จะรับ asset หลัง migrate (จาก WHITEPAPER.md)
     * @param _saleSupply 700_000_000 × 10^18
     * @param _startPrice 100_000 ($0.10 ใน 6-decimal USDT)
     * @param _endPrice 1_000_000 ($1.00)
     * @param _migrationUsdtThreshold 5_000_000_000_000 ($5M)
     * @param _migrationTpixThreshold 350_000_000 × 10^18
     */
    constructor(
        address _tpix,
        address _usdt,
        address _liquidityWallet,
        uint256 _saleSupply,
        uint256 _startPrice,
        uint256 _endPrice,
        uint256 _migrationUsdtThreshold,
        uint256 _migrationTpixThreshold
    ) Ownable(msg.sender) {
        require(_tpix != address(0) && _usdt != address(0) && _liquidityWallet != address(0), "BC: zero addr");
        require(_endPrice > _startPrice, "BC: end <= start");
        require(_saleSupply > 0, "BC: zero supply");
        require(_migrationUsdtThreshold > 0 && _migrationTpixThreshold > 0, "BC: zero threshold");
        require(_migrationTpixThreshold <= _saleSupply, "BC: threshold > supply");

        tpix = IERC20(_tpix);
        usdt = IERC20(_usdt);
        liquidityWallet = _liquidityWallet;
        saleSupply = _saleSupply;
        startPrice = _startPrice;
        endPrice = _endPrice;
        migrationUsdtThreshold = _migrationUsdtThreshold;
        migrationTpixThreshold = _migrationTpixThreshold;
    }

    // =========================================================================
    // Price calculation (linear bonding curve)
    // =========================================================================

    /**
     * @notice ราคาปัจจุบัน (USDT ต่อ 1 TPIX, 6 decimals) ที่ supply ปัจจุบัน
     */
    function currentPrice() public view returns (uint256) {
        return _priceAt(totalSold);
    }

    /**
     * @notice คำนวณราคาที่จุด supply ใดๆ (linear interpolation)
     * @dev price = start + (end - start) × sold / saleSupply
     */
    function _priceAt(uint256 sold) internal view returns (uint256) {
        if (sold >= saleSupply) return endPrice;
        uint256 priceRange = endPrice - startPrice;
        return startPrice + (priceRange * sold) / saleSupply;
    }

    /**
     * @notice คำนวณ TPIX ที่จะได้รับเมื่อจ่าย USDT จำนวนหนึ่ง
     * @dev ใช้ integral ของ linear curve เพื่อความแม่นยำ
     *      cost(x) = ∫startPrice + slope·s ds จาก totalSold ถึง totalSold+x
     *             = startPrice·x + slope·(2·totalSold·x + x²)/2 / saleSupply
     *
     *      ต้อง solve quadratic — ใช้ approximation: avg price method
     *      ราคาเฉลี่ยช่วง = (price_at(start) + price_at(start+x)) / 2
     *      cost = avg_price · x
     */
    function quoteBuy(uint256 usdtIn) public view returns (uint256 tpixOut) {
        require(!migrated, "BC: migrated");
        require(usdtIn > 0, "BC: zero in");

        uint256 remaining = saleSupply - totalSold;
        if (remaining == 0) return 0;

        // Quadratic solver — solve for x where cost(x) = usdtIn
        // cost(x) = (startPrice + slope·totalSold/saleSupply)·x + slope·x²/(2·saleSupply)
        // a·x² + b·x - usdtIn = 0
        //   a = slope / (2 · saleSupply)
        //   b = startPrice + slope · totalSold / saleSupply  (= currentPrice scaled)
        // x = (-b + √(b² + 4·a·usdtIn)) / (2a)

        // ใช้ approximation simpler — average price ของ chunk
        // เริ่มจาก guess ผ่าน currentPrice แล้ว iterate 1 ครั้งเพื่อ refine
        uint256 priceNow = _priceAt(totalSold);
        // First guess: assume constant price
        uint256 guess = (usdtIn * 1e18) / priceNow;
        if (guess > remaining) guess = remaining;

        // Refine: ใช้ราคาเฉลี่ย (priceNow + priceAt(totalSold + guess)) / 2
        uint256 priceEnd = _priceAt(totalSold + guess);
        uint256 avgPrice = (priceNow + priceEnd) / 2;
        tpixOut = (usdtIn * 1e18) / avgPrice;
        if (tpixOut > remaining) tpixOut = remaining;
    }

    /**
     * @notice คำนวณ USDT ที่จะได้รับเมื่อ sell TPIX (ก่อน exit fee)
     */
    function quoteSell(uint256 tpixIn) public view returns (uint256 usdtOut, uint256 fee) {
        require(!migrated, "BC: migrated");
        require(tpixIn > 0, "BC: zero in");
        require(tpixIn <= totalSold, "BC: > total sold");

        uint256 priceNow = _priceAt(totalSold);
        uint256 priceEnd = _priceAt(totalSold - tpixIn);
        uint256 avgPrice = (priceNow + priceEnd) / 2;
        uint256 grossUsdt = (tpixIn * avgPrice) / 1e18;

        fee = (grossUsdt * EXIT_FEE_BPS) / BPS_DENOMINATOR;
        usdtOut = grossUsdt - fee;
    }

    // =========================================================================
    // Buy / Sell
    // =========================================================================

    /**
     * @notice ซื้อ TPIX ด้วย USDT — user ต้อง approve usdt amount ก่อนเรียก
     * @param usdtIn จำนวน USDT ที่จ่าย (6 decimals)
     * @param minTpixOut slippage protection — TPIX ขั้นต่ำที่ยอมรับ
     */
    function buy(uint256 usdtIn, uint256 minTpixOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 tpixOut)
    {
        require(!migrated, "BC: migrated");
        require(usdtIn > 0, "BC: zero in");

        tpixOut = quoteBuy(usdtIn);
        require(tpixOut >= minTpixOut, "BC: slippage");
        require(tpixOut > 0, "BC: zero out");

        // Transfer USDT from buyer
        usdt.safeTransferFrom(msg.sender, address(this), usdtIn);

        // Transfer TPIX to buyer
        tpix.safeTransfer(msg.sender, tpixOut);

        totalSold += tpixOut;
        totalRaised += usdtIn;
        bought[msg.sender] += tpixOut;

        emit Bought(msg.sender, usdtIn, tpixOut, _priceAt(totalSold));

        // Auto-flag threshold (owner can call migrate() after)
        if (totalRaised >= migrationUsdtThreshold) {
            emit ThresholdReached("usdt", totalRaised, totalSold);
        } else if (totalSold >= migrationTpixThreshold) {
            emit ThresholdReached("tpix", totalRaised, totalSold);
        }
    }

    /**
     * @notice ขาย TPIX กลับเป็น USDT (- 5% exit fee)
     * @param tpixIn จำนวน TPIX ที่จะ sell
     * @param minUsdtOut slippage protection
     */
    function sell(uint256 tpixIn, uint256 minUsdtOut)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 usdtOut)
    {
        require(!migrated, "BC: migrated");
        require(tpixIn > 0 && tpixIn <= totalSold, "BC: invalid in");

        uint256 fee;
        (usdtOut, fee) = quoteSell(tpixIn);
        require(usdtOut >= minUsdtOut, "BC: slippage");

        // Transfer TPIX from seller back to contract
        tpix.safeTransferFrom(msg.sender, address(this), tpixIn);

        // Transfer USDT to seller
        usdt.safeTransfer(msg.sender, usdtOut);

        totalSold -= tpixIn;
        // totalRaised stays — fee accumulates as protocol revenue

        emit Sold(msg.sender, tpixIn, usdtOut, fee, _priceAt(totalSold));
    }

    // =========================================================================
    // Migration to DEX
    // =========================================================================

    /**
     * @notice เช็คว่าถึง threshold หรือยัง
     */
    function isMigrationReady() public view returns (bool) {
        return !migrated &&
            (totalRaised >= migrationUsdtThreshold || totalSold >= migrationTpixThreshold);
    }

    /**
     * @notice Trigger migration — โอน USDT + TPIX ที่เหลือ ไป Liquidity wallet
     * @dev เรียกได้เมื่อ threshold ถึง — owner อย่างเดียว
     *      Liquidity wallet จะเป็นคน addLiquidity() ใน DEX (off-chain process)
     *
     *      ทำไมไม่ auto-call DEX router? — เพื่อให้มีเวลา set DEX address + ตัดสินใจ
     *      ratio ก่อน lock liquidity (อาจอยากแบ่ง 80% ไป DEX, 20% ไว้ buyback)
     */
    function migrate() external onlyOwner nonReentrant {
        require(isMigrationReady(), "BC: not ready");
        require(!migrated, "BC: already migrated");

        migrated = true;

        uint256 usdtBalance = usdt.balanceOf(address(this));
        uint256 tpixBalance = tpix.balanceOf(address(this));

        if (usdtBalance > 0) usdt.safeTransfer(liquidityWallet, usdtBalance);
        if (tpixBalance > 0) tpix.safeTransfer(liquidityWallet, tpixBalance);

        emit Migrated(usdtBalance, tpixBalance, tpixBalance);
    }

    // =========================================================================
    // Admin
    // =========================================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Recover unrelated tokens ที่ส่งมาผิด — กู้คืนได้ (ไม่กระทบ TPIX/USDT)
     */
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(tpix) && token != address(usdt), "BC: protected");
        IERC20(token).safeTransfer(owner(), amount);
    }
}
