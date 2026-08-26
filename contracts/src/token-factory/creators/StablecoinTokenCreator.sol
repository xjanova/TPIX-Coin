// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../StablecoinToken.sol";

contract StablecoinTokenCreator {
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
    ) external returns (address) {
        StablecoinToken token = new StablecoinToken{salt: salt}(
            name_, symbol_, decimals_, totalSupply_, owner_,
            reserveWallet_, pausable_, freezeEnabled_, kycRequired_
        );
        return address(token);
    }
}
