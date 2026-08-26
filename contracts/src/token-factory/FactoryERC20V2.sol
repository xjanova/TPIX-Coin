// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title FactoryERC20V2 — Enhanced ERC-20 with Pausable, Blacklist, MintCap, AutoBurn
 * @author Xman Studio
 * @notice Phase 2 — รองรับ common sub-options ทุก fungible token type
 *
 * Token Types: standard(0), mintable(1), burnable(2), mintable_burnable(3)
 * Sub-Options: pausable, blacklist, mintCap, autoBurn, burnFloor
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract FactoryERC20V2 is ERC20, Ownable, Pausable {

    // ═══════════════════════════════════════════
    //  IMMUTABLE CONFIG
    // ═══════════════════════════════════════════

    uint8 private immutable _decimals;
    bool public immutable isMintable;
    bool public immutable isBurnable;
    bool public immutable isPausable;
    bool public immutable isBlacklistEnabled;
    bool public immutable isAutoBurnEnabled;

    /// @notice Maximum total supply (0 = unlimited). ใช้ได้กับ mintable tokens เท่านั้น
    uint256 public immutable mintCap;

    /// @notice Auto-burn rate per transfer (basis points, 100 = 1%)
    uint16 public immutable autoBurnRateBps;

    /// @notice Minimum total supply — หยุด auto-burn เมื่อ supply ต่ำกว่านี้
    uint256 public immutable burnFloor;

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    /// @notice Blacklisted addresses (ห้าม transfer/receive)
    mapping(address => bool) public blacklisted;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event Blacklisted(address indexed account, bool status);
    event AutoBurned(address indexed from, uint256 amount);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    /**
     * @param name_              Token name
     * @param symbol_            Token ticker
     * @param decimals_          Token decimals (0-18)
     * @param totalSupply_       Initial supply (wei)
     * @param owner_             Token owner
     * @param mintable_          Owner can mint
     * @param burnable_          Holders can burn
     * @param pausable_          Owner can pause transfers
     * @param blacklistEnabled_  Owner can blacklist addresses
     * @param mintCap_           Max supply for minting (0 = unlimited)
     * @param autoBurnEnabled_   Auto-burn on each transfer
     * @param autoBurnRateBps_   Burn rate in basis points (e.g., 100 = 1%)
     * @param burnFloor_         Stop auto-burn below this supply
     */
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
        uint256 mintCap_,
        bool autoBurnEnabled_,
        uint16 autoBurnRateBps_,
        uint256 burnFloor_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        require(autoBurnRateBps_ <= 2500, "V2: burn rate > 25%");
        require(mintCap_ == 0 || mintCap_ >= totalSupply_, "V2: cap < supply");

        _decimals = decimals_;
        isMintable = mintable_;
        isBurnable = burnable_;
        isPausable = pausable_;
        isBlacklistEnabled = blacklistEnabled_;
        mintCap = mintCap_;
        isAutoBurnEnabled = autoBurnEnabled_;
        autoBurnRateBps = autoBurnRateBps_;
        burnFloor = burnFloor_;

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

    /**
     * @dev Override _update สำหรับ pausable + blacklist + autoBurn
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Pausable check (ยกเว้น mint/burn)
        if (isPausable && from != address(0) && to != address(0)) {
            _requireNotPaused();
        }

        // Blacklist check
        if (isBlacklistEnabled) {
            require(!blacklisted[from], "V2: sender blacklisted");
            require(!blacklisted[to], "V2: recipient blacklisted");
        }

        // Auto-burn (เฉพาะ transfer ปกติ ไม่ใช่ mint/burn)
        if (isAutoBurnEnabled && from != address(0) && to != address(0) && autoBurnRateBps > 0) {
            uint256 burnAmount = (value * autoBurnRateBps) / 10000;
            if (burnAmount > 0 && totalSupply() - burnAmount >= burnFloor) {
                super._update(from, address(0), burnAmount);
                emit AutoBurned(from, burnAmount);
                value -= burnAmount;
            }
        }

        super._update(from, to, value);
    }

    // ═══════════════════════════════════════════
    //  MINT / BURN
    // ═══════════════════════════════════════════

    function mint(address to, uint256 amount) external onlyOwner {
        require(isMintable, "V2: minting disabled");
        if (mintCap > 0) {
            require(totalSupply() + amount <= mintCap, "V2: exceeds mint cap");
        }
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(isBurnable, "V2: burning disabled");
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        require(isBurnable, "V2: burning disabled");
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // ═══════════════════════════════════════════
    //  PAUSABLE
    // ═══════════════════════════════════════════

    function pause() external onlyOwner {
        require(isPausable, "V2: not pausable");
        _pause();
    }

    function unpause() external onlyOwner {
        require(isPausable, "V2: not pausable");
        _unpause();
    }

    // ═══════════════════════════════════════════
    //  BLACKLIST
    // ═══════════════════════════════════════════

    function setBlacklist(address account, bool status) external onlyOwner {
        require(isBlacklistEnabled, "V2: blacklist disabled");
        require(account != owner(), "V2: cannot blacklist owner");
        blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function setBlacklistBatch(address[] calldata accounts, bool status) external onlyOwner {
        require(isBlacklistEnabled, "V2: blacklist disabled");
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != owner(), "V2: cannot blacklist owner");
            blacklisted[accounts[i]] = status;
            emit Blacklisted(accounts[i], status);
        }
    }
}
