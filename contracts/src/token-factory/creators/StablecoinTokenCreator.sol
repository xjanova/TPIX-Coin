// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../StablecoinToken.sol";
import "./CreatorAccess.sol";

/// @dev create() รับคำสั่งจาก factory ที่ผูกไว้เท่านั้น — ดู CreatorAccess
contract StablecoinTokenCreator is CreatorAccess {
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
    ) external onlyFactory returns (address) {
        StablecoinToken token = new StablecoinToken{salt: salt}(
            name_, symbol_, decimals_, totalSupply_, owner_,
            reserveWallet_, pausable_, freezeEnabled_, kycRequired_
        );
        return address(token);
    }
}
