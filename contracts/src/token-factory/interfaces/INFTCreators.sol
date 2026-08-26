// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFT Creator Interfaces
 * @notice Lightweight interfaces for NFT sub-factory creators.
 *         Used by TPIXNFTFactory coordinator to avoid importing
 *         heavy NFT implementations (decouples from mcopy/cancun deps).
 */

interface IFactoryERC721Creator {
    function create(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        address owner_,
        string calldata tokenURI_,
        uint256 maxSupply_,
        bool mintable_,
        bool soulbound_,
        bool royaltyEnabled_,
        address royaltyRecipient_,
        uint16 royaltyBps_
    ) external returns (address);
}

interface INFTCollectionCreator {
    function create(
        bytes32 salt,
        string calldata name_,
        string calldata symbol_,
        address owner_,
        uint256 maxSupply_,
        uint8 mintType_,
        uint256 mintPrice_,
        uint16 maxPerWallet_,
        uint16 maxPerTx_,
        uint16 reserveCount_,
        string calldata baseURI_,
        string calldata placeholderURI_,
        bool delayedReveal_,
        bool royaltyEnabled_,
        address royaltyRecipient_,
        uint16 royaltyBps_
    ) external returns (address);
}
