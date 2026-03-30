// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../FactoryERC20V2.sol";

contract ERC20V2Creator {
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
    ) external returns (address) {
        FactoryERC20V2 token = new FactoryERC20V2{salt: salt}(
            name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            mintCap_, autoBurnEnabled_, autoBurnRateBps_, burnFloor_
        );
        return address(token);
    }
}
