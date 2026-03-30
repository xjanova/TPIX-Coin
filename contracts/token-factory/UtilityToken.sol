// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title UtilityToken — ERC-20 with Tax, Anti-Whale, Anti-Bot, Auto-Liquidity
 * @author Xman Studio
 * @notice Phase 2 — Utility token with comprehensive DeFi features
 *
 * Features:
 *   - Tax System: buy/sell/transfer tax → split to taxWallet + marketingWallet
 *   - Anti-Whale: max wallet & max transaction limits
 *   - Anti-Bot: launch protection + cooldown between trades
 *   - Auto-Liquidity: auto-add LP from tax portion
 *   - Pausable + Blacklist (common options)
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract UtilityToken is ERC20, Ownable, Pausable, ReentrancyGuard {

    // ═══════════════════════════════════════════
    //  CONFIG STRUCT (ลด stack depth)
    // ═══════════════════════════════════════════

    struct TaxConfig {
        uint16 buyTaxBps;           // ภาษีซื้อ (basis points, 100 = 1%)
        uint16 sellTaxBps;          // ภาษีขาย
        uint16 transferTaxBps;      // ภาษี transfer
        address taxWallet;          // กระเป๋าเก็บภาษี
        address marketingWallet;    // กระเป๋า marketing
        uint16 marketingShareBps;   // ส่วนแบ่ง marketing (จาก tax, 5000 = 50%)
    }

    struct ProtectionConfig {
        uint16 maxWalletBps;        // max wallet % of supply (basis points)
        uint16 maxTxBps;            // max tx % of supply
        uint256 antiBotDuration;    // seconds หลัง launch ที่ anti-bot ทำงาน
        uint256 tradingCooldown;    // seconds ระหว่าง trade
    }

    // ═══════════════════════════════════════════
    //  IMMUTABLE CONFIG
    // ═══════════════════════════════════════════

    uint8 private immutable _decimals;
    bool public immutable isPausable;
    bool public immutable isBlacklistEnabled;
    bool public immutable isMintable;
    bool public immutable isBurnable;

    // Tax
    bool public immutable taxEnabled;
    uint16 public immutable buyTaxBps;
    uint16 public immutable sellTaxBps;
    uint16 public immutable transferTaxBps;
    address public immutable marketingWallet;
    uint16 public immutable marketingShareBps;

    // Anti-whale
    bool public immutable antiWhaleEnabled;
    uint256 public immutable maxWalletAmount;
    uint256 public immutable maxTxAmount;

    // Anti-bot
    bool public immutable antiBotEnabled;
    uint256 public immutable antiBotDuration;
    uint256 public immutable tradingCooldown;

    // ═══════════════════════════════════════════
    //  MUTABLE STATE
    // ═══════════════════════════════════════════

    /// @notice Tax wallet (owner can update)
    address public taxWallet;

    /// @notice DEX pair address สำหรับตรวจจับ buy/sell
    mapping(address => bool) public isDexPair;

    /// @notice Blacklisted addresses
    mapping(address => bool) public blacklisted;

    /// @notice Excluded from tax & limits (owner, contract, taxWallet)
    mapping(address => bool) public isExcluded;

    /// @notice Anti-bot: last trade timestamp per address
    mapping(address => uint256) public lastTradeTime;

    /// @notice Launch timestamp (set on first addPair or manual launch)
    uint256 public launchTime;

    /// @notice Trading enabled flag
    bool public tradingEnabled;

    /// @notice Auto-LP: accumulated tokens for LP (ยังไม่ implement swap ใน Phase 2)
    uint256 public lpAccumulated;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event TaxCollected(address indexed from, uint256 taxAmount, uint256 toTaxWallet, uint256 toMarketing);
    event Blacklisted(address indexed account, bool status);
    event DexPairUpdated(address indexed pair, bool status);
    event TradingEnabled(uint256 timestamp);
    event TaxWalletUpdated(address indexed newWallet);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        bool mintable_,
        bool burnable_,
        bool pausable_,
        bool blacklistEnabled_,
        TaxConfig memory tax_,
        ProtectionConfig memory protection_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        // Validate tax rates (max 25% each)
        require(tax_.buyTaxBps <= 2500, "UT: buy tax > 25%");
        require(tax_.sellTaxBps <= 2500, "UT: sell tax > 25%");
        require(tax_.transferTaxBps <= 2500, "UT: transfer tax > 25%");
        require(tax_.marketingShareBps <= 10000, "UT: marketing share > 100%");
        // Validate limits (min 0.1% of supply)
        if (protection_.maxWalletBps > 0) {
            require(protection_.maxWalletBps >= 10, "UT: max wallet < 0.1%");
        }
        if (protection_.maxTxBps > 0) {
            require(protection_.maxTxBps >= 10, "UT: max tx < 0.1%");
        }

        _decimals = decimals_;
        isMintable = mintable_;
        isBurnable = burnable_;
        isPausable = pausable_;
        isBlacklistEnabled = blacklistEnabled_;

        // Tax config
        bool hasTax = tax_.buyTaxBps > 0 || tax_.sellTaxBps > 0 || tax_.transferTaxBps > 0;
        taxEnabled = hasTax;
        buyTaxBps = tax_.buyTaxBps;
        sellTaxBps = tax_.sellTaxBps;
        transferTaxBps = tax_.transferTaxBps;
        taxWallet = tax_.taxWallet != address(0) ? tax_.taxWallet : owner_;
        marketingWallet = tax_.marketingWallet != address(0) ? tax_.marketingWallet : owner_;
        marketingShareBps = tax_.marketingShareBps;

        // Anti-whale
        antiWhaleEnabled = protection_.maxWalletBps > 0 || protection_.maxTxBps > 0;
        maxWalletAmount = protection_.maxWalletBps > 0
            ? (totalSupply_ * protection_.maxWalletBps) / 10000
            : type(uint256).max;
        maxTxAmount = protection_.maxTxBps > 0
            ? (totalSupply_ * protection_.maxTxBps) / 10000
            : type(uint256).max;

        // Anti-bot
        antiBotEnabled = protection_.antiBotDuration > 0;
        antiBotDuration = protection_.antiBotDuration;
        tradingCooldown = protection_.tradingCooldown;

        // Exclude owner & contract from limits/tax
        isExcluded[owner_] = true;
        isExcluded[address(this)] = true;
        if (tax_.taxWallet != address(0)) isExcluded[tax_.taxWallet] = true;
        if (tax_.marketingWallet != address(0)) isExcluded[tax_.marketingWallet] = true;

        if (totalSupply_ > 0) {
            _mint(owner_, totalSupply_);
        }
    }

    // ═══════════════════════════════════════════
    //  ERC-20 OVERRIDES
    // ═══════════════════════════════════════════

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Skip checks for mint/burn
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        // Pausable
        if (isPausable) {
            _requireNotPaused();
        }

        // Blacklist
        if (isBlacklistEnabled) {
            require(!blacklisted[from], "UT: sender blacklisted");
            require(!blacklisted[to], "UT: recipient blacklisted");
        }

        bool isBuy = isDexPair[from];
        bool isSell = isDexPair[to];
        bool senderExcluded = isExcluded[from];
        bool recipientExcluded = isExcluded[to];

        // Anti-bot: ตรวจ cooldown + launch protection
        if (antiBotEnabled && !senderExcluded && !recipientExcluded) {
            if (launchTime > 0 && block.timestamp < launchTime + antiBotDuration) {
                // ช่วง launch protection: บังคับ cooldown
                if (tradingCooldown > 0) {
                    require(
                        block.timestamp >= lastTradeTime[from] + tradingCooldown,
                        "UT: cooldown active"
                    );
                    require(
                        block.timestamp >= lastTradeTime[to] + tradingCooldown,
                        "UT: cooldown active"
                    );
                }
            }
            lastTradeTime[from] = block.timestamp;
            lastTradeTime[to] = block.timestamp;
        }

        // Anti-whale: max tx & max wallet
        if (antiWhaleEnabled && !senderExcluded && !recipientExcluded) {
            require(value <= maxTxAmount, "UT: exceeds max tx");
            if (!isSell) {
                // ไม่เช็ค max wallet สำหรับ sell (to = pair)
                require(balanceOf(to) + value <= maxWalletAmount, "UT: exceeds max wallet");
            }
        }

        // Tax calculation
        uint256 taxAmount = 0;
        if (taxEnabled && !senderExcluded && !recipientExcluded) {
            uint16 taxRate;
            if (isBuy) {
                taxRate = buyTaxBps;
            } else if (isSell) {
                taxRate = sellTaxBps;
            } else {
                taxRate = transferTaxBps;
            }

            if (taxRate > 0) {
                taxAmount = (value * taxRate) / 10000;

                if (taxAmount > 0) {
                    // Split tax: marketing share + remaining to taxWallet
                    uint256 marketingAmount = (taxAmount * marketingShareBps) / 10000;
                    uint256 taxWalletAmount = taxAmount - marketingAmount;

                    if (marketingAmount > 0) {
                        super._update(from, marketingWallet, marketingAmount);
                    }
                    if (taxWalletAmount > 0) {
                        super._update(from, taxWallet, taxWalletAmount);
                    }

                    emit TaxCollected(from, taxAmount, taxWalletAmount, marketingAmount);
                }
            }
        }

        // Transfer remaining (value - tax)
        super._update(from, to, value - taxAmount);
    }

    // ═══════════════════════════════════════════
    //  MINT / BURN
    // ═══════════════════════════════════════════

    function mint(address to, uint256 amount) external onlyOwner {
        require(isMintable, "UT: minting disabled");
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(isBurnable, "UT: burning disabled");
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        require(isBurnable, "UT: burning disabled");
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // ═══════════════════════════════════════════
    //  OWNER FUNCTIONS
    // ═══════════════════════════════════════════

    function pause() external onlyOwner {
        require(isPausable, "UT: not pausable");
        _pause();
    }

    function unpause() external onlyOwner {
        require(isPausable, "UT: not pausable");
        _unpause();
    }

    function setBlacklist(address account, bool status) external onlyOwner {
        require(isBlacklistEnabled, "UT: blacklist disabled");
        require(account != owner(), "UT: cannot blacklist owner");
        blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function setBlacklistBatch(address[] calldata accounts, bool status) external onlyOwner {
        require(isBlacklistEnabled, "UT: blacklist disabled");
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != owner(), "UT: cannot blacklist owner");
            blacklisted[accounts[i]] = status;
            emit Blacklisted(accounts[i], status);
        }
    }

    /// @notice Set DEX pair address (buy/sell detection)
    function setDexPair(address pair, bool status) external onlyOwner {
        isDexPair[pair] = status;
        emit DexPairUpdated(pair, status);
    }

    /// @notice Enable trading (sets launch timestamp for anti-bot)
    function enableTrading() external onlyOwner {
        require(!tradingEnabled, "UT: already enabled");
        tradingEnabled = true;
        launchTime = block.timestamp;
        emit TradingEnabled(block.timestamp);
    }

    /// @notice Update tax wallet
    function setTaxWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "UT: zero address");
        taxWallet = newWallet;
        isExcluded[newWallet] = true;
        emit TaxWalletUpdated(newWallet);
    }

    /// @notice Exclude/include address from tax & limits
    function setExcluded(address account, bool excluded) external onlyOwner {
        isExcluded[account] = excluded;
    }
}
