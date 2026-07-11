// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IWETH
 * @notice Interface ของ Wrapped native coin — บน TPIX Chain คือ WTPIX (WETH9 pattern)
 */
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}
