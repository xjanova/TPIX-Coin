// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../FactoryERC721.sol";
import "./CreatorAccess.sol";

/// @dev create() รับคำสั่งจาก factory ที่ผูกไว้เท่านั้น — ดู CreatorAccess
contract FactoryERC721Creator is CreatorAccess {
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
    ) external onlyFactory returns (address) {
        FactoryERC721 nft = new FactoryERC721{salt: salt}(
            name_, symbol_, owner_, tokenURI_,
            maxSupply_, mintable_, soulbound_,
            royaltyEnabled_, royaltyRecipient_, royaltyBps_
        );
        return address(nft);
    }
}
