// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./TrancheVesting.sol";

/**
 * @title LaunchVestingDeployer — deploys a TrancheVesting for LaunchpadFactory
 * @author Xman Studio
 * @notice Split out only to keep LaunchpadFactory under the 24 KB contract size limit (EIP-170).
 *         It holds nothing and has no owner; anyone may call it, it only creates an empty vesting contract.
 */
contract LaunchVestingDeployer {
    event VestingDeployed(address indexed vesting, address indexed token, address indexed beneficiary);

    function deploy(
        IERC20 token,
        address beneficiary,
        uint64 start,
        uint64 period,
        TrancheVesting.Tranche[] calldata tranches,
        string calldata label
    ) external returns (address vesting) {
        vesting = address(new TrancheVesting(token, beneficiary, start, period, tranches, label));
        emit VestingDeployed(vesting, address(token), beneficiary);
    }
}
