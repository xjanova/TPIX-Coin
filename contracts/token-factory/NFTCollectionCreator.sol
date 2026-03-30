// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../NFTCollection.sol";

contract NFTCollectionCreator {
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
    ) external returns (address) {
        NFTCollection nft = new NFTCollection{salt: salt}(
            name_, symbol_, owner_, maxSupply_,
            mintType_, mintPrice_, maxPerWallet_, maxPerTx_,
            reserveCount_, baseURI_, placeholderURI_,
            delayedReveal_, royaltyEnabled_, royaltyRecipient_, royaltyBps_
        );
        return address(nft);
    }
}
