// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WTPIX (Wrapped TPIX) — BEP-20 Token on BSC
 * @author Xman Studio
 * @notice Wrapped version ของ TPIX native coin สำหรับซื้อขายบน BSC
 * ใช้เป็นตัวแทน TPIX ก่อนที่ bridge จะพร้อมใช้งาน
 *
 * Flow: ผู้ใช้ซื้อ TPIX ผ่าน Token Sale → ได้รับ wTPIX (BEP-20) บน BSC
 * เมื่อ bridge พร้อม: wTPIX บน BSC → lock → mint native TPIX บน TPIX Chain
 */
contract WTPIX is ERC20, ERC20Burnable, Ownable {
    /// @notice จำนวน supply สูงสุดที่สามารถ mint ได้ (ตรงกับ Token Sale allocation)
    uint256 public constant MAX_SUPPLY = 700_000_000 * 10 ** 18; // 700M (10% of 7B)

    /// @notice Bridge contract address (ตั้งค่าภายหลังเมื่อ bridge พร้อม)
    address public bridgeContract;

    /// @notice Minter addresses — TokenSale contract + bridge
    mapping(address => bool) public minters;

    event MinterSet(address indexed minter, bool status);
    event BridgeContractSet(address indexed bridge);

    constructor() ERC20("Wrapped TPIX", "wTPIX") Ownable(msg.sender) {}

    /**
     * @notice ตั้งค่า minter (TokenSale contract หรือ bridge)
     * @param minter ที่อยู่ contract ที่มีสิทธิ์ mint
     * @param status เปิด/ปิดสิทธิ์
     */
    function setMinter(address minter, bool status) external onlyOwner {
        minters[minter] = status;
        emit MinterSet(minter, status);
    }

    /**
     * @notice ตั้งค่า bridge contract
     * @param bridge ที่อยู่ bridge contract
     */
    function setBridgeContract(address bridge) external onlyOwner {
        bridgeContract = bridge;
        emit BridgeContractSet(bridge);
    }

    /**
     * @notice Mint wTPIX ให้ผู้ซื้อ (เรียกจาก TokenSale หรือ bridge)
     * @param to ที่อยู่ผู้รับ
     * @param amount จำนวน wTPIX (18 decimals)
     */
    function mint(address to, uint256 amount) external {
        require(minters[msg.sender], "WTPIX: not a minter");
        require(totalSupply() + amount <= MAX_SUPPLY, "WTPIX: exceeds max supply");
        _mint(to, amount);
    }

    /**
     * @notice Burn wTPIX เมื่อ bridge ไป TPIX Chain (lock/burn)
     * ผู้ใช้ต้อง approve bridge contract ก่อน
     * @param from ที่อยู่ผู้ burn
     * @param amount จำนวน wTPIX
     */
    function bridgeBurn(address from, uint256 amount) external {
        require(msg.sender == bridgeContract, "WTPIX: only bridge");
        _burn(from, amount);
    }
}
