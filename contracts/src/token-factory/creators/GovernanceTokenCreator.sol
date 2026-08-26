// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../GovernanceToken.sol";

contract GovernanceTokenCreator {
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
    ) external returns (address) {
        GovernanceToken token = new GovernanceToken{salt: salt}(
            name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            delegationEnabled_, mintCap_,
            proposalThreshold_, quorumBps_, votingPeriod_
        );
        return address(token);
    }
}
