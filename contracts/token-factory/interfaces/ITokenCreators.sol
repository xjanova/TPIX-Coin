// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Token Creator Interfaces
 * @notice Lightweight interfaces for ERC-20 sub-factory creators.
 *         Used by TPIXTokenFactoryV2 coordinator to avoid importing
 *         heavy token implementations (decouples from mcopy/cancun deps).
 */

// Struct definitions matching UtilityToken.sol
struct TaxConfig {
    uint16 buyTaxBps;
    uint16 sellTaxBps;
    uint16 transferTaxBps;
    address taxWallet;
    address marketingWallet;
    uint16 marketingShareBps;
}

struct ProtectionConfig {
    uint16 maxWalletBps;
    uint16 maxTxBps;
    uint256 antiBotDuration;
    uint256 tradingCooldown;
}

interface IERC20V2Creator {
    function create(
        bytes32 salt,
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
    ) external returns (address);
}

interface IUtilityTokenCreator {
    function create(
        bytes32 salt,
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
    ) external returns (address);
}

interface IRewardTokenCreator {
    function create(
        bytes32 salt,
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
    ) external returns (address);
}

interface IGovernanceTokenCreator {
    function create(
        bytes32 salt,
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
    ) external returns (address);
}

interface IStablecoinTokenCreator {
    function create(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        address reserveWallet_,
        bool pausable_,
        bool freezeEnabled_,
        bool kycRequired_
    ) external returns (address);
}
