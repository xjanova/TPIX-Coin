// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FixedPriceSale.sol";
import "./PoolFeeder.sol";
import "./LaunchVestingDeployer.sol";

/**
 * @title LaunchpadFactory — one transaction opens a child-token sale whose proceeds feed a locked pool
 * @author Xman Studio
 * @notice For any token on TPIX Chain (first: IDTC). createLaunch():
 *   1. deploys a PoolFeeder (owner = caller) and a FixedPriceSale whose treasury AND permanent owner is that
 *      feeder — the caller drives the sale through the feeder (pause, window, limits, unsold) but can never
 *      point the proceeds anywhere else
 *   2. pulls `saleCap` tokens into the sale and `feederReserve` tokens into the feeder from the caller
 *   3. optionally pulls `seedQuote` (USDT_TPIX) into the feeder and feeds it at once, so the pool is
 *      opened at exactly the sale price in the same transaction — nobody can slip in first at a bad price
 *   4. optionally deploys a TrancheVesting (no owner, schedule fixed) and pulls its whole allocation in
 *
 * The caller must approve this factory for saleCap + feederReserve + vesting total tokens (and seedQuote of the quote).
 * No owner, no fee, no upgrade: the factory keeps only a public list of what it created.
 * Tokens that take a fee on transfer are rejected (received amounts are checked).
 */
contract LaunchpadFactory is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// the LP must stay locked at least this long after the sale ends
    uint64 public constant MIN_LP_LOCK = 30 days;
    uint16 public constant DEFAULT_BAND_BPS = 300;

    IERC20 public immutable quote;
    IFeederRouter public immutable router;
    LaunchVestingDeployer public immutable vestingDeployer;

    struct Params {
        IERC20 token;
        uint256 rateNumerator; // tokens out = pay × rateNumerator ÷ rateDenominator (smallest units)
        uint256 rateDenominator;
        uint256 saleCap; // tokens for sale (smallest units)
        uint256 feederReserve; // tokens set aside to pair with the proceeds
        uint64 startTime;
        uint64 endTime;
        uint16 poolShareBps; // share of proceeds that goes into the pool (10000 = all)
        uint16 bandBps; // 0 = DEFAULT_BAND_BPS
        uint64 lpUnlockTime;
        address projectTreasury;
        uint256 minFeed; // smallest quote amount worth a feed (quote smallest units, ≥ 1, fixed forever)
        uint256 seedQuote; // quote to open the pool with now (0 = first purchase opens it)
    }

    /// empty `tranches` = no vesting contract
    struct VestingParams {
        address beneficiary;
        uint64 start;
        uint64 period;
        TrancheVesting.Tranche[] tranches;
        string label;
    }

    struct Launch {
        address token;
        address sale;
        address feeder;
        address vesting;
        address creator;
        uint64 createdAt;
    }

    Launch[] private _launches;
    mapping(address => uint256) public launchIdOfSale; // id + 1 (0 = not ours)

    /// sale terms are read from the sale/feeder/vesting contracts themselves
    event LaunchCreated(
        uint256 indexed id, address indexed token, address indexed creator, address sale, address feeder, address vesting
    );

    error ZeroAddress();
    error BadConfig();
    error FeeOnTransfer();
    error PoolPriceOff(uint256 poolVsSaleBps);

    constructor(IERC20 quote_, IFeederRouter router_, LaunchVestingDeployer vestingDeployer_) {
        if (address(quote_) == address(0) || address(router_) == address(0) || address(vestingDeployer_) == address(0)) {
            revert ZeroAddress();
        }
        quote = quote_;
        router = router_;
        vestingDeployer = vestingDeployer_;
    }

    function launchCount() external view returns (uint256) {
        return _launches.length;
    }

    function launchAt(uint256 id) external view returns (Launch memory) {
        return _launches[id];
    }

    function createLaunch(Params calldata p, VestingParams calldata v)
        external
        nonReentrant
        returns (address sale, address feeder, address vesting)
    {
        if (address(p.token) == address(0) || p.projectTreasury == address(0)) revert ZeroAddress();
        if (address(p.token) == address(quote) || p.saleCap == 0) revert BadConfig();
        if (p.endTime <= p.startTime || p.endTime <= block.timestamp) revert BadConfig();
        if (p.lpUnlockTime < uint256(p.endTime) + MIN_LP_LOCK) revert BadConfig();
        if (p.poolShareBps > 0 && p.feederReserve == 0) revert BadConfig();
        if (p.seedQuote > 0 && p.poolShareBps == 0) revert BadConfig();

        PoolFeeder f = new PoolFeeder(
            PoolFeeder.Config({
                token: p.token,
                quote: quote,
                router: router,
                rateNumerator: p.rateNumerator,
                rateDenominator: p.rateDenominator,
                poolShareBps: p.poolShareBps,
                bandBps: p.bandBps == 0 ? DEFAULT_BAND_BPS : p.bandBps,
                lpUnlockTime: p.lpUnlockTime,
                reserveReleaseTime: p.endTime,
                projectTreasury: p.projectTreasury,
                minFeed: p.minFeed
            }),
            msg.sender
        );
        feeder = address(f);

        // a pool that already exists must sit inside the band, or the first feed would add at its price
        uint256 vs = f.poolVsSaleBps();
        if (vs != 0 && (vs < 10_000 - f.bandBps() || vs > 10_000 + f.bandBps())) revert PoolPriceOff(vs);

        sale = address(
            new FixedPriceSale(
                p.token,
                quote,
                p.rateNumerator,
                p.rateDenominator,
                p.saleCap,
                feeder,
                p.startTime,
                p.endTime,
                feeder // the feeder owns the sale forever — proceeds can never be redirected
            )
        );
        f.bindSale(sale);

        _pull(p.token, sale, p.saleCap);
        if (p.feederReserve > 0) _pull(p.token, feeder, p.feederReserve);
        if (p.seedQuote > 0) {
            _pull(quote, feeder, p.seedQuote);
            f.feed();
        }

        if (v.tranches.length > 0) {
            vesting = vestingDeployer.deploy(p.token, v.beneficiary, v.start, v.period, v.tranches, v.label);
            _pull(p.token, vesting, TrancheVesting(vesting).totalAllocation());
        }

        uint256 id = _launches.length;
        _launches.push(
            Launch({
                token: address(p.token),
                sale: sale,
                feeder: feeder,
                vesting: vesting,
                creator: msg.sender,
                createdAt: uint64(block.timestamp)
            })
        );
        launchIdOfSale[sale] = id + 1;
        emit LaunchCreated(id, address(p.token), msg.sender, sale, feeder, vesting);
    }

    function _pull(IERC20 t, address to, uint256 amount) private {
        uint256 before = t.balanceOf(to);
        t.safeTransferFrom(msg.sender, to, amount);
        if (t.balanceOf(to) - before != amount) revert FeeOnTransfer();
    }
}
