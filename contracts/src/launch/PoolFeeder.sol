// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFeederRouter {
    function factory() external view returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IFeederDexFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IFeederPair {
    function token0() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function skim(address to) external;
}

/// the parts of FixedPriceSale the feeder drives as its permanent owner
interface IFeederSale {
    function treasury() external view returns (address);

    function owner() external view returns (address);

    function pause() external;

    function unpause() external;

    function setWindow(uint64 startTime_, uint64 endTime_) external;

    function setLimits(uint256 minPurchase_, uint256 maxPerWallet_) external;

    function withdrawUnsold(address to) external;
}

/**
 * @title PoolFeeder — turns sale proceeds into locked DEX liquidity, automatically
 * @author Xman Studio
 * @notice Set as the `treasury` of a FixedPriceSale. Every purchase sends the pay token (USDT_TPIX) here;
 *         anyone may call feed() to split it: `poolShareBps` goes into the token/quote pool together with
 *         tokens from this contract's reserve, the rest goes to `projectTreasury`.
 *
 * Price safety: liquidity is added at the pool's own ratio, and only while that ratio is within
 * ±`bandBps` of the sale price (rateNumerator / rateDenominator tokens per quote unit). Pushing the pool
 * price to make the feeder add at a bad ratio therefore costs an attacker more than the band can pay back.
 * An empty pool is seeded at exactly the sale price (stray donations in the pair are skimmed first).
 * Outside the band only the owner can feed, against a reference price the owner states (feedWithReference).
 *
 * Lock: the LP tokens stay in this contract until `lpUnlockTime`. The unused token reserve can leave after
 * `reserveReleaseTime` (the end of the sale) once no proceeds wait for the pool; proceeds that never made
 * it into the pool can leave only after `lpUnlockTime`.
 *
 * Proceeds cannot be redirected: the feeder is the permanent owner of its FixedPriceSale (bound once by the
 * deployer) and exposes pause / window / limits / unsold — never setTreasury or an ownership transfer.
 * minFeed is fixed at deploy, so the owner cannot stall feeds by raising it.
 *
 * Supports only tokens without transfer fees (both the sold token and the quote token).
 */
contract PoolFeeder is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_BAND_BPS = 2000;
    uint256 private constant BPS = 10_000;
    /// router slippage allowance between our own ratio maths and the router's rounding (0.5%)
    uint256 private constant ROUTER_SLACK_BPS = 50;

    IERC20 public immutable token;
    IERC20 public immutable quote;
    IFeederRouter public immutable router;
    IFeederDexFactory public immutable dexFactory;
    uint256 public immutable rateNumerator;
    uint256 public immutable rateDenominator;
    uint16 public immutable poolShareBps;
    uint16 public immutable bandBps;
    uint64 public immutable lpUnlockTime;
    uint64 public immutable reserveReleaseTime;
    uint256 public immutable minFeed;
    address private immutable _binder;

    IFeederSale public sale;
    address public projectTreasury;
    /// quote already split off for the pool but not paired yet (band or reserve) — never re-split to the project
    uint256 public pendingPool;

    uint256 public totalQuoteToPool;
    uint256 public totalTokenToPool;
    uint256 public totalQuoteToProject;

    event Fed(uint256 quoteToPool, uint256 tokenToPool, uint256 liquidity, uint256 quoteToProject, bool ownerReference);
    event ProjectTreasuryUpdated(address indexed treasury);
    event SaleBound(address indexed sale);
    event LiquidityWithdrawn(address indexed to, uint256 amount);
    event ReserveWithdrawn(address indexed to, uint256 tokenAmount, uint256 quoteAmount);
    event TokenRecovered(address indexed token, address indexed to, uint256 amount);

    error ZeroAddress();
    error BadConfig();
    error NothingToFeed();
    error OutOfBand(uint256 poolTokenPerQuoteBps);
    error StillLocked();
    error ProtectedToken();
    error NotBinder();
    error AlreadyBound();
    error NotBound();
    error QuotePending(uint256 amount);

    struct Config {
        IERC20 token;
        IERC20 quote;
        IFeederRouter router;
        uint256 rateNumerator;
        uint256 rateDenominator;
        uint16 poolShareBps;
        uint16 bandBps;
        uint64 lpUnlockTime;
        uint64 reserveReleaseTime;
        address projectTreasury;
        uint256 minFeed;
    }

    constructor(Config memory c, address owner_) Ownable(owner_) {
        if (
            address(c.token) == address(0) || address(c.quote) == address(0) || address(c.router) == address(0)
                || c.projectTreasury == address(0)
        ) revert ZeroAddress();
        if (address(c.token) == address(c.quote)) revert BadConfig();
        // keep every price product far below 2^256 (reserves are uint112)
        if (c.rateNumerator == 0 || c.rateDenominator == 0 || c.rateNumerator >= 2 ** 96 || c.rateDenominator >= 2 ** 96) {
            revert BadConfig();
        }
        if (c.poolShareBps > BPS || c.bandBps == 0 || c.bandBps > MAX_BAND_BPS) revert BadConfig();
        if (c.lpUnlockTime < c.reserveReleaseTime || c.minFeed == 0) revert BadConfig();

        token = c.token;
        quote = c.quote;
        router = c.router;
        dexFactory = IFeederDexFactory(c.router.factory());
        rateNumerator = c.rateNumerator;
        rateDenominator = c.rateDenominator;
        poolShareBps = c.poolShareBps;
        bandBps = c.bandBps;
        lpUnlockTime = c.lpUnlockTime;
        reserveReleaseTime = c.reserveReleaseTime;
        projectTreasury = c.projectTreasury;
        minFeed = c.minFeed;
        _binder = msg.sender;
    }

    /**
     * @notice once, by whoever deployed this feeder (LaunchpadFactory): the sale this feeder owns forever.
     *         The sale must already pay its proceeds here and be owned by this feeder.
     */
    function bindSale(address sale_) external {
        if (msg.sender != _binder) revert NotBinder();
        if (address(sale) != address(0)) revert AlreadyBound();
        if (sale_ == address(0)) revert ZeroAddress();
        if (IFeederSale(sale_).treasury() != address(this) || IFeederSale(sale_).owner() != address(this)) {
            revert BadConfig();
        }
        sale = IFeederSale(sale_);
        emit SaleBound(sale_);
    }

    // ─────────────────────────────── views ───────────────────────────────

    function pair() public view returns (address) {
        return dexFactory.getPair(address(token), address(quote));
    }

    /// @notice pool reserves as (token, quote) — (0, 0) when the pair does not exist
    function poolReserves() public view returns (uint256 tokenSide, uint256 quoteSide) {
        address p = pair();
        if (p == address(0)) return (0, 0);
        (uint112 r0, uint112 r1,) = IFeederPair(p).getReserves();
        (tokenSide, quoteSide) = IFeederPair(p).token0() == address(token) ? (r0, r1) : (r1, r0);
    }

    /**
     * @notice pool price relative to a reference, in bps (10000 = equal). 0 when the pool is empty.
     *         >10000 means the pool gives MORE tokens per quote than the reference (token is cheaper there).
     */
    function poolVsReferenceBps(uint256 refNum, uint256 refDen) public view returns (uint256) {
        (uint256 tr, uint256 qr) = poolReserves();
        if (tr == 0 || qr == 0) return 0;
        // (tr / qr) / (refNum / refDen) in bps
        return (tr * refDen * BPS) / (qr * refNum);
    }

    function poolVsSaleBps() external view returns (uint256) {
        return poolVsReferenceBps(rateNumerator, rateDenominator);
    }

    function tokenReserve() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function pendingQuote() external view returns (uint256) {
        return quote.balanceOf(address(this));
    }

    // ─────────────────────────────── feed ───────────────────────────────

    /// @notice anyone may call: split the collected quote and add the pool share as liquidity at the sale-price band
    function feed() external nonReentrant returns (uint256 quoteToPool, uint256 tokenToPool, uint256 liquidity) {
        return _feed(rateNumerator, rateDenominator, false);
    }

    /// @notice owner only: same as feed() but the band is checked against a reference price the owner states
    ///         (e.g. after the sale, when the market price has moved away from the sale price)
    function feedWithReference(uint256 refNum, uint256 refDen)
        external
        onlyOwner
        nonReentrant
        returns (uint256 quoteToPool, uint256 tokenToPool, uint256 liquidity)
    {
        if (refNum == 0 || refDen == 0 || refNum >= 2 ** 96 || refDen >= 2 ** 96) revert BadConfig();
        return _feed(refNum, refDen, true);
    }

    function _feed(uint256 refNum, uint256 refDen, bool ownerReference)
        private
        returns (uint256 quoteToPool, uint256 tokenToPool, uint256 liquidity)
    {
        // new money = everything above what is already set aside for the pool
        uint256 balance = quote.balanceOf(address(this));
        uint256 newIn = balance > pendingPool ? balance - pendingPool : 0;

        // the project share of new money leaves at once — it never waits on the pool
        uint256 toProject = (newIn * (BPS - poolShareBps)) / BPS;
        pendingPool += newIn - toProject;

        if (toProject > 0) {
            totalQuoteToProject += toProject;
            quote.safeTransfer(projectTreasury, toProject);
        }

        uint256 vs;
        if (pendingPool > 0 && pendingPool >= minFeed) {
            (quoteToPool, tokenToPool, liquidity, vs) = _addToPool(pendingPool, refNum, refDen);
            pendingPool -= quoteToPool;
        }
        if (quoteToPool == 0 && toProject == 0) {
            if (vs != 0) revert OutOfBand(vs);
            revert NothingToFeed();
        }
        emit Fed(quoteToPool, tokenToPool, liquidity, toProject, ownerReference);
    }

    /// @dev returns all 0 with `outOfBand` set when the pool price is outside the band
    function _addToPool(uint256 forPool, uint256 refNum, uint256 refDen)
        private
        returns (uint256 quoteUsed, uint256 tokenUsed, uint256 liquidity, uint256 outOfBand)
    {
        uint256 reserveAvail = token.balanceOf(address(this));
        if (reserveAvail == 0) return (0, 0, 0, 0);

        (uint256 tr, uint256 qr) = poolReserves();
        bool empty = tr == 0 || qr == 0;
        uint256 tokenWanted;
        if (empty) {
            // empty pool: clear donated balances so the first deposit sets exactly the reference price
            address p = pair();
            if (p != address(0)) IFeederPair(p).skim(projectTreasury);
            tokenWanted = (forPool * refNum) / refDen;
        } else {
            uint256 vs = (tr * refDen * BPS) / (qr * refNum);
            if (vs < BPS - bandBps || vs > BPS + bandBps) return (0, 0, 0, vs == 0 ? 1 : vs);
            tokenWanted = (forPool * tr) / qr;
        }

        uint256 quoteAmt = forPool;
        if (tokenWanted > reserveAvail) {
            // not enough tokens left to pair everything: pair what we can, the rest of the quote waits here
            tokenWanted = reserveAvail;
            quoteAmt = empty ? (reserveAvail * refDen) / refNum : (reserveAvail * qr) / tr;
        }
        if (tokenWanted == 0 || quoteAmt == 0) return (0, 0, 0, 0);

        token.forceApprove(address(router), tokenWanted);
        quote.forceApprove(address(router), quoteAmt);
        (tokenUsed, quoteUsed, liquidity) = router.addLiquidity(
            address(token),
            address(quote),
            tokenWanted,
            quoteAmt,
            (tokenWanted * (BPS - ROUTER_SLACK_BPS)) / BPS,
            (quoteAmt * (BPS - ROUTER_SLACK_BPS)) / BPS,
            address(this),
            block.timestamp
        );
        token.forceApprove(address(router), 0);
        quote.forceApprove(address(router), 0);

        totalQuoteToPool += quoteUsed;
        totalTokenToPool += tokenUsed;
    }

    // ─────────────────────────────── owner ───────────────────────────────

    function setProjectTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        projectTreasury = treasury_;
        emit ProjectTreasuryUpdated(treasury_);
    }

    // ── the sale, driven as its permanent owner (no setTreasury, no ownership transfer) ──

    function pauseSale() external onlyOwner {
        _sale().pause();
    }

    function unpauseSale() external onlyOwner {
        _sale().unpause();
    }

    /// @notice move or shorten the sale — never past the original end, or later proceeds could miss the pool
    function setSaleWindow(uint64 startTime_, uint64 endTime_) external onlyOwner {
        if (endTime_ > reserveReleaseTime) revert BadConfig();
        _sale().setWindow(startTime_, endTime_);
    }

    function setSaleLimits(uint256 minPurchase_, uint256 maxPerWallet_) external onlyOwner {
        _sale().setLimits(minPurchase_, maxPerWallet_);
    }

    /// @notice unsold sale tokens (FixedPriceSale allows it after the end, or while paused)
    function withdrawUnsold(address to) external onlyOwner nonReentrant {
        _sale().withdrawUnsold(to);
    }

    function _sale() private view returns (IFeederSale s) {
        s = sale;
        if (address(s) == address(0)) revert NotBound();
    }

    /// @notice LP tokens leave only after lpUnlockTime
    function withdrawLiquidity(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (block.timestamp < lpUnlockTime) revert StillLocked();
        address p = pair();
        uint256 amount = p == address(0) ? 0 : IERC20(p).balanceOf(address(this));
        if (amount == 0) revert NothingToFeed();
        IERC20(p).safeTransfer(to, amount);
        emit LiquidityWithdrawn(to, amount);
    }

    /**
     * @notice the unused token reserve, after the sale ends — and only once no proceeds wait for the pool
     *         (feed them first, or feedWithReference when the pool price left the band)
     */
    function withdrawReserve(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (block.timestamp < reserveReleaseTime) revert StillLocked();
        uint256 q = quote.balanceOf(address(this));
        if (q >= minFeed) revert QuotePending(q);
        uint256 t = token.balanceOf(address(this));
        if (t == 0) revert NothingToFeed();
        token.safeTransfer(to, t);
        emit ReserveWithdrawn(to, t, 0);
    }

    /// @notice proceeds that never made it into the pool, only once the LP itself is unlocked
    function withdrawLeftoverQuote(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (block.timestamp < lpUnlockTime) revert StillLocked();
        uint256 q = quote.balanceOf(address(this));
        if (q == 0) revert NothingToFeed();
        pendingPool = 0;
        quote.safeTransfer(to, q);
        emit ReserveWithdrawn(to, 0, q);
    }

    /// @notice anything else sent here by mistake — never the token, the quote or the LP
    function recoverToken(IERC20 other, address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        address o = address(other);
        if (o == address(token) || o == address(quote) || (o != address(0) && o == pair())) revert ProtectedToken();
        uint256 amount = other.balanceOf(address(this));
        if (amount == 0) revert NothingToFeed();
        other.safeTransfer(to, amount);
        emit TokenRecovered(o, to, amount);
    }
}
