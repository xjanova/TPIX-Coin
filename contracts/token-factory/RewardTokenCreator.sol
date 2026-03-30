// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../RewardToken.sol";

contract RewardTokenCreator {
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
    ) external returns (address) {
        RewardToken token = new RewardToken{salt: salt}(
            name_, symbol_, decimals_, totalSupply_, owner_,
            mintable_, burnable_, pausable_, blacklistEnabled_,
            rewardType_, rewardRateBps_, minHoldForReward_,
            vestingCliff_, vestingDuration_
        );
        return address(token);
    }
}
