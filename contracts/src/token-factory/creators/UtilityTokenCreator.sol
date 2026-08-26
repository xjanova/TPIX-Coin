// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../UtilityToken.sol";

contract UtilityTokenCreator {
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
        UtilityToken.TaxConfig calldata taxConfig_,
        UtilityToken.ProtectionConfig calldata protectionConfig_
    ) external returns (address) {
        UtilityToken token = new UtilityToken{salt: salt}(
            name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            taxConfig_, protectionConfig_
        );
        return address(token);
    }
}
