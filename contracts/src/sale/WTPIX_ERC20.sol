// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title WTPIX (Wrapped TPIX) — ERC-20 บน TPIX Chain
 * @author Xman Studio
 * @notice Standard WETH9-style wrapper ที่ห่อ native TPIX coin ให้เป็น ERC-20
 *         จำเป็นเพราะ bonding curve + DEX router ต้องการ ERC-20 interface
 *
 * Pattern: pure WETH9 — 1:1 backed by native TPIX ล็อกอยู่ใน contract นี้
 *   - deposit()  → user ส่ง native TPIX → mint WTPIX จำนวนเท่ากัน
 *   - withdraw() → user burn WTPIX → get native TPIX กลับคืน
 *   - receive()  → bare send ก็ deposit อัตโนมัติ (สะดวกสำหรับ EOA)
 *
 * Security:
 *   - NO owner, NO admin, NO minter whitelist — แบบ WETH9 pure
 *   - Total supply = native balance เสมอ (invariant)
 *   - ReentrancyGuard บน withdraw() เผื่อ receiver เป็น malicious contract
 *   - Decimals = 18 (ตรงกับ native TPIX)
 *
 * ต่างจาก WTPIX_BEP20.sol:
 *   - BEP-20 version: mint ควบคุมโดย TokenSale contract (ก่อนมี bridge)
 *   - ERC-20 version (นี้): user wrap/unwrap เองได้อิสระ — ไม่มี mint cap
 */
contract WTPIX is ERC20, ReentrancyGuard {
    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor() ERC20("Wrapped TPIX", "WTPIX") {}

    /**
     * @notice Wrap native TPIX → WTPIX (1:1)
     */
    function deposit() public payable {
        require(msg.value > 0, "WTPIX: zero deposit");
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Unwrap WTPIX → native TPIX (1:1)
     * @param amount จำนวน WTPIX ที่จะ burn (18 decimals)
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "WTPIX: zero withdraw");
        require(balanceOf(msg.sender) >= amount, "WTPIX: insufficient balance");

        _burn(msg.sender, amount);

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "WTPIX: native transfer failed");

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice bare send native coin → auto deposit (WETH9 convention)
     */
    receive() external payable {
        deposit();
    }
}
