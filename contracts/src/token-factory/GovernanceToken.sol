// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title GovernanceToken — ERC-20 with Voting (ERC20Votes) + Delegation
 * @author Xman Studio
 * @notice Phase 2 — Governance token ที่รองรับ voting, delegation, checkpoints
 *
 * Features:
 *   - ERC20Votes: vote delegation, checkpoints, getPastVotes
 *   - ERC20Permit: gasless approvals via EIP-2612
 *   - Pausable + Blacklist (common options)
 *   - Mintable + Burnable (optional)
 *
 * Note: Governor contract สำหรับ proposal/quorum/voting period เป็น Phase 3
 *       Token นี้รองรับ delegation + checkpoints พร้อมใช้กับ Governor ได้เลย
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable, Pausable {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    uint8 private immutable _decimals;
    bool public immutable isMintable;
    bool public immutable isBurnable;
    bool public immutable isPausable;
    bool public immutable isBlacklistEnabled;
    bool public immutable isDelegationEnabled;

    /// @notice Maximum total supply (0 = unlimited)
    uint256 public immutable mintCap;

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    mapping(address => bool) public blacklisted;

    // Governance metadata (on-chain reference, actual Governor is separate)
    /// @notice Minimum tokens to create a proposal (informational)
    uint256 public proposalThreshold;
    /// @notice Quorum percentage required (informational, basis points)
    uint16 public quorumBps;
    /// @notice Voting period in seconds (informational)
    uint256 public votingPeriod;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event Blacklisted(address indexed account, bool status);
    event GovernanceParamsUpdated(uint256 proposalThreshold, uint16 quorumBps, uint256 votingPeriod);

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
        bool delegationEnabled_,
        uint256 mintCap_,
        uint256 proposalThreshold_,
        uint16 quorumBps_,
        uint256 votingPeriod_
    ) ERC20(name_, symbol_) ERC20Permit(name_) Ownable(owner_) {
        require(mintCap_ == 0 || mintCap_ >= totalSupply_, "GOV: cap < supply");
        require(quorumBps_ <= 10000, "GOV: quorum > 100%");

        _decimals = decimals_;
        isMintable = mintable_;
        isBurnable = burnable_;
        isPausable = pausable_;
        isBlacklistEnabled = blacklistEnabled_;
        isDelegationEnabled = delegationEnabled_;
        mintCap = mintCap_;

        // Governance params (informational, ใช้ร่วมกับ Governor contract)
        proposalThreshold = proposalThreshold_;
        quorumBps = quorumBps_;
        votingPeriod = votingPeriod_;

        if (totalSupply_ > 0) {
            _mint(owner_, totalSupply_);
        }

        // Auto-delegate ให้ owner ถ้า delegation เปิด
        if (delegationEnabled_) {
            _delegate(owner_, owner_);
        }
    }

    // ═══════════════════════════════════════════
    //  ERC-20 OVERRIDES (resolve conflicts)
    // ═══════════════════════════════════════════

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        // Pausable (skip mint/burn)
        if (isPausable && from != address(0) && to != address(0)) {
            _requireNotPaused();
        }

        // Blacklist
        if (isBlacklistEnabled) {
            if (from != address(0)) require(!blacklisted[from], "GOV: sender blacklisted");
            if (to != address(0)) require(!blacklisted[to], "GOV: recipient blacklisted");
        }

        super._update(from, to, value);
    }

    function nonces(address owner_)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner_);
    }

    // ═══════════════════════════════════════════
    //  DELEGATION
    // ═══════════════════════════════════════════

    /// @notice Override delegate เพื่อ check delegation enabled
    function delegate(address delegatee) public override {
        require(isDelegationEnabled, "GOV: delegation disabled");
        super.delegate(delegatee);
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce_,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        require(isDelegationEnabled, "GOV: delegation disabled");
        super.delegateBySig(delegatee, nonce_, expiry, v, r, s);
    }

    // ═══════════════════════════════════════════
    //  MINT / BURN
    // ═══════════════════════════════════════════

    function mint(address to, uint256 amount) external onlyOwner {
        require(isMintable, "GOV: minting disabled");
        if (mintCap > 0) {
            require(totalSupply() + amount <= mintCap, "GOV: exceeds mint cap");
        }
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(isBurnable, "GOV: burning disabled");
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        require(isBurnable, "GOV: burning disabled");
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // ═══════════════════════════════════════════
    //  OWNER FUNCTIONS
    // ═══════════════════════════════════════════

    function pause() external onlyOwner {
        require(isPausable, "GOV: not pausable");
        _pause();
    }

    function unpause() external onlyOwner {
        require(isPausable, "GOV: not pausable");
        _unpause();
    }

    function setBlacklist(address account, bool status) external onlyOwner {
        require(isBlacklistEnabled, "GOV: blacklist disabled");
        require(account != owner(), "GOV: cannot blacklist owner");
        blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    /// @notice Update governance parameters (informational only)
    function setGovernanceParams(
        uint256 proposalThreshold_,
        uint16 quorumBps_,
        uint256 votingPeriod_
    ) external onlyOwner {
        require(quorumBps_ <= 10000, "GOV: quorum > 100%");
        proposalThreshold = proposalThreshold_;
        quorumBps = quorumBps_;
        votingPeriod = votingPeriod_;
        emit GovernanceParamsUpdated(proposalThreshold_, quorumBps_, votingPeriod_);
    }
}
