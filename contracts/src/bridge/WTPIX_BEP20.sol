// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title WTPIX (Wrapped TPIX) — BEP-20 Token on BSC
 * @author Xman Studio
 * @notice Wrapped version ของ TPIX native coin สำหรับซื้อขายบน BSC
 * ใช้เป็นตัวแทน TPIX ก่อนที่ bridge จะพร้อมใช้งาน
 *
 * Flow: ผู้ใช้ซื้อ TPIX ผ่าน Token Sale → ได้รับ wTPIX (BEP-20) บน BSC
 * เมื่อ bridge พร้อม: wTPIX บน BSC → lock → mint native TPIX บน TPIX Chain
 *
 * Security 2026-05-04 hardening:
 *   - Ownable2Step (กัน typo เปลี่ยน owner)
 *   - ERC20Pausable (emergency stop เผื่อ minter exploit)
 *   - Bridge contract change มี 2-day timelock (กัน rug แบบเปลี่ยน bridge ฉับพลัน)
 */
contract WTPIX is ERC20, ERC20Burnable, ERC20Pausable, Ownable2Step {
    /// @notice จำนวน supply สูงสุดที่สามารถ mint ได้ (ตรงกับ Token Sale allocation)
    uint256 public constant MAX_SUPPLY = 700_000_000 * 10 ** 18; // 700M (10% of 7B)

    /// @notice Timelock duration สำหรับการเปลี่ยน bridge contract (2 days)
    uint256 public constant BRIDGE_CHANGE_TIMELOCK = 2 days;

    /// @notice Bridge contract address (ตั้งค่าภายหลังเมื่อ bridge พร้อม)
    address public bridgeContract;

    /// @notice Pending bridge contract change (address(0) = no pending change)
    address public pendingBridgeContract;

    /// @notice Timestamp เมื่อ pending bridge change execute ได้
    uint256 public pendingBridgeExecuteAfter;

    /// @notice Minter addresses — TokenSale contract + bridge
    mapping(address => bool) public minters;

    event MinterSet(address indexed minter, bool status);
    event BridgeContractQueued(address indexed bridge, uint256 executeAfter);
    event BridgeContractCancelled(address indexed bridge);
    event BridgeContractSet(address indexed bridge);

    constructor() ERC20("Wrapped TPIX", "wTPIX") Ownable(msg.sender) {}

    /**
     * @notice ตั้งค่า minter (TokenSale contract หรือ bridge)
     * @param minter ที่อยู่ contract ที่มีสิทธิ์ mint
     * @param status เปิด/ปิดสิทธิ์
     */
    function setMinter(address minter, bool status) external onlyOwner {
        require(minter != address(0), "WTPIX: zero minter");
        minters[minter] = status;
        emit MinterSet(minter, status);
    }

    /**
     * @notice Queue bridge contract change ด้วย 2-day timelock
     * @dev ป้องกันไม่ให้ owner สลับ bridge ฉับพลันไปยัง malicious contract
     */
    function queueBridgeContract(address bridge) external onlyOwner {
        require(bridge != address(0), "WTPIX: zero bridge");
        pendingBridgeContract = bridge;
        pendingBridgeExecuteAfter = block.timestamp + BRIDGE_CHANGE_TIMELOCK;
        emit BridgeContractQueued(bridge, pendingBridgeExecuteAfter);
    }

    /**
     * @notice Cancel queued bridge change
     */
    function cancelBridgeContract() external onlyOwner {
        require(pendingBridgeContract != address(0), "WTPIX: no pending");
        emit BridgeContractCancelled(pendingBridgeContract);
        pendingBridgeContract = address(0);
        pendingBridgeExecuteAfter = 0;
    }

    /**
     * @notice Execute queued bridge change หลัง timelock หมด
     */
    function executeBridgeContract() external onlyOwner {
        require(pendingBridgeContract != address(0), "WTPIX: no pending");
        require(block.timestamp >= pendingBridgeExecuteAfter, "WTPIX: timelock not expired");
        bridgeContract = pendingBridgeContract;
        emit BridgeContractSet(pendingBridgeContract);
        pendingBridgeContract = address(0);
        pendingBridgeExecuteAfter = 0;
    }

    /**
     * @notice Pause transfers + minting (emergency)
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Mint wTPIX ให้ผู้ซื้อ (เรียกจาก TokenSale หรือ bridge)
     * @param to ที่อยู่ผู้รับ
     * @param amount จำนวน wTPIX (18 decimals)
     */
    function mint(address to, uint256 amount) external whenNotPaused {
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
    function bridgeBurn(address from, uint256 amount) external whenNotPaused {
        require(msg.sender == bridgeContract, "WTPIX: only bridge");
        _burn(from, amount);
    }

    // Pausable hook — required เพราะ multiple inheritance (ERC20 + ERC20Pausable)
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
