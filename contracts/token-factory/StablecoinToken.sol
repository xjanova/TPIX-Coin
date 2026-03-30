// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title StablecoinToken — ERC-20 with Freeze, KYC Allowlist, Authority Mint/Burn
 * @author Xman Studio
 * @notice Phase 2 — Stablecoin ที่ owner mint/burn ตามสำรอง
 *
 * Features:
 *   - Authority Mint/Burn: owner mint เมื่อ deposit, burn เมื่อ withdraw
 *   - Freeze: อายัดกระเป๋าเฉพาะราย (compliance)
 *   - KYC Allowlist: เฉพาะ address ที่ผ่าน KYC ถึง transfer ได้
 *   - Pausable: หยุดทุก transfer ชั่วคราว (emergency)
 *
 * Metadata (off-chain, stored in DB):
 *   - peg_currency: THB/USD/EUR
 *   - reserve_type: fiat/crypto/algorithmic
 *   - peg_ratio: e.g., 1:1
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract StablecoinToken is ERC20, Ownable, Pausable {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    uint8 private immutable _decimals;
    bool public immutable isPausable;
    bool public immutable isFreezeEnabled;
    bool public immutable isKycRequired;

    /// @notice Reserve wallet address (informational, for transparency)
    address public reserveWallet;

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    /// @notice Frozen addresses (ห้าม transfer ทั้ง send และ receive)
    mapping(address => bool) public frozen;

    /// @notice KYC-approved addresses
    mapping(address => bool) public kycApproved;

    /// @notice Minter role (owner + approved minters)
    mapping(address => bool) public isMinter;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event Frozen(address indexed account, bool status);
    event KycUpdated(address indexed account, bool approved);
    event KycBatchUpdated(address[] accounts, bool approved);
    event MinterUpdated(address indexed account, bool status);
    event ReserveWalletUpdated(address indexed newWallet);
    event StablecoinMinted(address indexed to, uint256 amount, string reason);
    event StablecoinBurned(address indexed from, uint256 amount, string reason);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        address reserveWallet_,
        bool pausable_,
        bool freezeEnabled_,
        bool kycRequired_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        _decimals = decimals_;
        isPausable = pausable_;
        isFreezeEnabled = freezeEnabled_;
        isKycRequired = kycRequired_;
        reserveWallet = reserveWallet_ != address(0) ? reserveWallet_ : owner_;

        // Owner เป็น minter + KYC approved by default
        isMinter[owner_] = true;
        kycApproved[owner_] = true;
        kycApproved[address(this)] = true;

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
        if (from != address(0) && to != address(0)) {
            // Pausable
            if (isPausable) _requireNotPaused();

            // Freeze check
            if (isFreezeEnabled) {
                require(!frozen[from], "SC: sender frozen");
                require(!frozen[to], "SC: recipient frozen");
            }

            // KYC check (ทั้ง sender และ receiver ต้อง KYC)
            if (isKycRequired) {
                require(kycApproved[from], "SC: sender not KYC");
                require(kycApproved[to], "SC: recipient not KYC");
            }
        }

        super._update(from, to, value);
    }

    // ═══════════════════════════════════════════
    //  AUTHORITY MINT / BURN
    // ═══════════════════════════════════════════

    modifier onlyMinter() {
        require(isMinter[msg.sender] || msg.sender == owner(), "SC: not minter");
        _;
    }

    /// @notice Mint stablecoins (เมื่อ deposit reserve)
    function mint(address to, uint256 amount, string calldata reason) external onlyMinter {
        require(to != address(0), "SC: mint to zero");
        _mint(to, amount);
        emit StablecoinMinted(to, amount, reason);
    }

    /// @notice Burn stablecoins (เมื่อ withdraw reserve)
    function burn(uint256 amount, string calldata reason) external onlyMinter {
        _burn(msg.sender, amount);
        emit StablecoinBurned(msg.sender, amount, reason);
    }

    /// @notice Burn from address (regulatory seizure — owner only)
    function burnFrom(address account, uint256 amount, string calldata reason) external onlyOwner {
        _burn(account, amount);
        emit StablecoinBurned(account, amount, reason);
    }

    // ═══════════════════════════════════════════
    //  FREEZE
    // ═══════════════════════════════════════════

    function setFrozen(address account, bool status) external onlyOwner {
        require(isFreezeEnabled, "SC: freeze disabled");
        require(account != owner(), "SC: cannot freeze owner");
        frozen[account] = status;
        emit Frozen(account, status);
    }

    function setFrozenBatch(address[] calldata accounts, bool status) external onlyOwner {
        require(isFreezeEnabled, "SC: freeze disabled");
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != owner(), "SC: cannot freeze owner");
            frozen[accounts[i]] = status;
            emit Frozen(accounts[i], status);
        }
    }

    // ═══════════════════════════════════════════
    //  KYC
    // ═══════════════════════════════════════════

    function setKyc(address account, bool approved) external onlyOwner {
        kycApproved[account] = approved;
        emit KycUpdated(account, approved);
    }

    function setKycBatch(address[] calldata accounts, bool approved) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            kycApproved[accounts[i]] = approved;
        }
        emit KycBatchUpdated(accounts, approved);
    }

    // ═══════════════════════════════════════════
    //  OWNER FUNCTIONS
    // ═══════════════════════════════════════════

    function pause() external onlyOwner {
        require(isPausable, "SC: not pausable");
        _pause();
    }

    function unpause() external onlyOwner {
        require(isPausable, "SC: not pausable");
        _unpause();
    }

    function setMinter(address account, bool status) external onlyOwner {
        isMinter[account] = status;
        emit MinterUpdated(account, status);
    }

    function setReserveWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "SC: zero address");
        reserveWallet = newWallet;
        emit ReserveWalletUpdated(newWallet);
    }
}
