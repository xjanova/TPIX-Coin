// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/ITokenCreators.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TPIXTokenFactoryV2 — Deploy ERC-20 Tokens (All Types)
 * @author Xman Studio
 * @notice Phase 2 — Factory coordinator สำหรับ ERC-20 ทุกประเภท
 *
 * Architecture: Coordinator + Sub-Factory Creators
 * แต่ละ Creator embed bytecode ของ token type เดียว
 * เพื่อให้แต่ละ contract อยู่ภายใน EIP-170 (24KB) limit
 *
 * Token Categories:
 *   0 = ERC20V2       (standard/mintable/burnable + pausable, blacklist, autoBurn)
 *   1 = Utility       (tax, anti-whale, anti-bot, auto-LP)
 *   2 = Reward        (reflection, dividend, staking, vesting)
 *   3 = Governance    (ERC20Votes, delegation, permit)
 *   4 = Stablecoin    (freeze, KYC, authority mint/burn)
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract TPIXTokenFactoryV2 is Ownable {

    // ═══════════════════════════════════════════
    //  SUB-FACTORY CREATORS (interfaces only)
    // ═══════════════════════════════════════════

    IERC20V2Creator public immutable erc20V2Creator;
    IUtilityTokenCreator public immutable utilityCreator;
    IRewardTokenCreator public immutable rewardCreator;
    IGovernanceTokenCreator public immutable governanceCreator;
    IStablecoinTokenCreator public immutable stablecoinCreator;

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    uint256 public nonce;
    address[] public deployedTokens;

    struct TokenRecord {
        string name;
        string symbol;
        address tokenOwner;
        uint8 category;    // 0-4
        uint256 createdAt;
    }

    mapping(address => TokenRecord) public tokenRecords;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event TokenCreated(
        address indexed tokenAddress,
        string name,
        string symbol,
        address indexed tokenOwner,
        uint8 category
    );

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    constructor(
        address erc20V2Creator_,
        address utilityCreator_,
        address rewardCreator_,
        address governanceCreator_,
        address stablecoinCreator_
    ) Ownable(msg.sender) {
        erc20V2Creator = IERC20V2Creator(erc20V2Creator_);
        utilityCreator = IUtilityTokenCreator(utilityCreator_);
        rewardCreator = IRewardTokenCreator(rewardCreator_);
        governanceCreator = IGovernanceTokenCreator(governanceCreator_);
        stablecoinCreator = IStablecoinTokenCreator(stablecoinCreator_);
    }

    // ═══════════════════════════════════════════
    //  INTERNAL HELPERS
    // ═══════════════════════════════════════════

    function _nextSalt() internal returns (bytes32) {
        bytes32 salt = keccak256(abi.encodePacked(nonce));
        nonce++;
        return salt;
    }

    function _register(address token, string memory name_, string memory symbol_, address owner_, uint8 category_) internal {
        deployedTokens.push(token);
        tokenRecords[token] = TokenRecord({
            name: name_,
            symbol: symbol_,
            tokenOwner: owner_,
            category: category_,
            createdAt: block.timestamp
        });
        emit TokenCreated(token, name_, symbol_, owner_, category_);
    }

    // ═══════════════════════════════════════════
    //  CREATE: ERC20V2 (category 0)
    // ═══════════════════════════════════════════

    function createERC20V2(
        string calldata name_,
        string calldata symbol_,
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
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        address addr = erc20V2Creator.create(
            salt, name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            mintCap_, autoBurnEnabled_, autoBurnRateBps_, burnFloor_
        );

        _register(addr, name_, symbol_, owner_, 0);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  CREATE: Utility Token (category 1)
    // ═══════════════════════════════════════════

    function createUtilityToken(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        bool mintable_,
        bool burnable_,
        bool pausable_,
        bool blacklistEnabled_,
        TaxConfig calldata taxConfig_,
        ProtectionConfig calldata protectionConfig_
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        address addr = utilityCreator.create(
            salt, name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            taxConfig_, protectionConfig_
        );

        _register(addr, name_, symbol_, owner_, 1);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  CREATE: Reward Token (category 2)
    // ═══════════════════════════════════════════

    function createRewardToken(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        bool mintable_,
        bool burnable_,
        bool pausable_,
        bool blacklistEnabled_,
        uint8 rewardType_,
        uint16 rewardRateBps_,
        uint256 minHoldForReward_,
        uint256 vestingCliff_,
        uint256 vestingDuration_
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        address addr = rewardCreator.create(
            salt, name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            rewardType_, rewardRateBps_, minHoldForReward_,
            vestingCliff_, vestingDuration_
        );

        _register(addr, name_, symbol_, owner_, 2);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  CREATE: Governance Token (category 3)
    // ═══════════════════════════════════════════

    function createGovernanceToken(
        string calldata name_,
        string calldata symbol_,
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
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        address addr = governanceCreator.create(
            salt, name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            delegationEnabled_, mintCap_,
            proposalThreshold_, quorumBps_, votingPeriod_
        );

        _register(addr, name_, symbol_, owner_, 3);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  CREATE: Stablecoin Token (category 4)
    // ═══════════════════════════════════════════

    function createStablecoinToken(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        address reserveWallet_,
        bool pausable_,
        bool freezeEnabled_,
        bool kycRequired_
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        address addr = stablecoinCreator.create(
            salt, name_, symbol_, decimals_, totalSupply_, owner_,
            reserveWallet_, pausable_, freezeEnabled_, kycRequired_
        );

        _register(addr, name_, symbol_, owner_, 4);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  VIEW
    // ═══════════════════════════════════════════

    function totalTokens() external view returns (uint256) {
        return deployedTokens.length;
    }

    function getToken(uint256 index) external view returns (address) {
        return deployedTokens[index];
    }
}
