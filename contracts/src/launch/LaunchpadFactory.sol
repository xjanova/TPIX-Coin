// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FixedPriceSale.sol";
import "./PoolFeeder.sol";
import "./LaunchVestingDeployer.sol";

/// the TPIX Token Factory's public register of the tokens it created
interface ILaunchTokenRegistry {
    function tokenRecords(address token)
        external
        view
        returns (string memory name, string memory symbol, address tokenOwner, uint8 category, uint256 createdAt);
}

/// the immutable feature switches of a Token Factory ERC20V2 token
interface ILaunchTokenFlags {
    function isMintable() external view returns (bool);
    function isPausable() external view returns (bool);
    function isBlacklistEnabled() external view returns (bool);
    function isAutoBurnEnabled() external view returns (bool);
}

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
 *
 * Anti-rug rules — checked here, so they hold even for callers who skip the website:
 *   - only plain ERC20V2 tokens made by the TPIX Token Factory, with minting, pausing, blacklisting and
 *     auto-burn all switched off (those switches are immutable, so they can never be turned on later)
 *   - the LP stays locked at least MIN_LP_LOCK after the sale ends; until then the feeder also keeps the
 *     unsold sale tokens and the unpaired reserve (see PoolFeeder)
 *   - at least MIN_POOL_SHARE_BPS of every purchase goes into the pool
 *   - at least MIN_LOCKED_SUPPLY_BPS of the total supply sits in the sale, the feeder reserve, or vesting
 *     that is still locked when the LP unlocks — the creator can never hold more than the rest freely
 * Tokens that take a fee on transfer are rejected (received amounts are checked).
 */
contract LaunchpadFactory is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// the LP must stay locked at least this long after the sale ends
    uint64 public constant MIN_LP_LOCK = 180 days;
    uint16 public constant DEFAULT_BAND_BPS = 300;
    /// share of every purchase that must go into the pool
    uint16 public constant MIN_POOL_SHARE_BPS = 5000;
    /// share of the total supply that must be in the sale, the reserve or still-locked vesting
    uint16 public constant MIN_LOCKED_SUPPLY_BPS = 8000;
    /// Token Factory category of plain ERC20V2 tokens
    uint8 private constant CATEGORY_ERC20V2 = 0;
    uint256 private constant BPS = 10_000;

    IERC20 public immutable quote;
    IFeederRouter public immutable router;
    LaunchVestingDeployer public immutable vestingDeployer;
    ILaunchTokenRegistry public immutable tokenRegistry;

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
    error NotFactoryToken();
    error RiskyToken();
    error TooMuchUnlocked(uint256 lockedBps);

    constructor(
        IERC20 quote_,
        IFeederRouter router_,
        LaunchVestingDeployer vestingDeployer_,
        ILaunchTokenRegistry tokenRegistry_
    ) {
        if (
            address(quote_) == address(0) || address(router_) == address(0) || address(vestingDeployer_) == address(0)
                || address(tokenRegistry_) == address(0)
        ) revert ZeroAddress();
        quote = quote_;
        router = router_;
        vestingDeployer = vestingDeployer_;
        tokenRegistry = tokenRegistry_;
    }

    /// @notice why a token cannot be launched: 0 = ok, 1 = not from the Token Factory, 2 = risky switches on
    function tokenCheck(address token) public view returns (uint8) {
        (,,, uint8 category, uint256 createdAt) = tokenRegistry.tokenRecords(token);
        if (createdAt == 0 || category != CATEGORY_ERC20V2) return 1;
        ILaunchTokenFlags t = ILaunchTokenFlags(token);
        if (t.isMintable() || t.isPausable() || t.isBlacklistEnabled() || t.isAutoBurnEnabled()) return 2;
        return 0;
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
        if (p.poolShareBps < MIN_POOL_SHARE_BPS || p.feederReserve == 0) revert BadConfig();
        uint8 check = tokenCheck(address(p.token));
        if (check == 1) revert NotFactoryToken();
        if (check == 2) revert RiskyToken();

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
                saleEndLimit: p.endTime,
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
        _pull(p.token, feeder, p.feederReserve);
        if (p.seedQuote > 0) {
            _pull(quote, feeder, p.seedQuote);
            f.feed();
        }

        if (v.tranches.length > 0) {
            vesting = vestingDeployer.deploy(p.token, v.beneficiary, v.start, v.period, v.tranches, v.label);
            _pull(p.token, vesting, TrancheVesting(vesting).totalAllocation());
        }
        _checkLocked(p, vesting);

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

    /// the sale, the reserve and vesting still locked at lpUnlockTime must hold MIN_LOCKED_SUPPLY_BPS of the supply
    function _checkLocked(Params calldata p, address vesting) private view {
        uint256 locked = p.saleCap + p.feederReserve;
        if (vesting != address(0)) {
            TrancheVesting tv = TrancheVesting(vesting);
            locked += tv.totalAllocation() - tv.vestedAmount(p.lpUnlockTime);
        }
        uint256 supply = p.token.totalSupply();
        if (locked * BPS < supply * MIN_LOCKED_SUPPLY_BPS) revert TooMuchUnlocked((locked * BPS) / supply);
    }

    function _pull(IERC20 t, address to, uint256 amount) private {
        uint256 before = t.balanceOf(to);
        t.safeTransferFrom(msg.sender, to, amount);
        if (t.balanceOf(to) - before != amount) revert FeeOnTransfer();
    }
}
