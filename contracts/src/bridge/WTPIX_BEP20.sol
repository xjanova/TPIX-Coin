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
 *
 * 2026-10-11 (รีวิวจากเซสชันสะพาน USDT):
 *   - เดิม setMinter() เพิ่ม minter ได้ทันที → คีย์เจ้าของหลุด = เพิ่ม minter ของตัวเองแล้ว mint ถึง MAX_SUPPLY
 *     ข้ามเพดานรายวันของ WTPIXBridgeMinter ไปทั้งหมด แล้วเทใส่พูล PancakeSwap
 *   - ตอนนี้: ตั้ง minter ตัวแรกได้ครั้งเดียว (setInitialMinter — สคริปต์ deploy ผูก WTPIXBridgeMinter ทันที)
 *     เพิ่มตัวต่อไปต้อง queueMinter → รอ 2 วัน → executeMinter (คนเห็นทันบน explorer)
 *     ถอด minter ทำได้ทันที (removeMinter) เพื่อตัดตัวที่มีปัญหาได้เร็ว
 *
 * ⚠️ เจ้าของสั่ง pause() ได้ = หยุดการโอนทุกกระเป๋า (เบรกฉุกเฉินเมื่อสะพานถูกโจมตี)
 *    ตัวตรวจเหรียญ/CMC จะขึ้นเตือน "owner can pause transfers" — เจ้าของต้องเป็น multisig ก่อนเปิดพูลจริง
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

    /// @notice Timelock สำหรับการ "เพิ่ม" minter (2 days) — การถอดไม่ต้องรอ
    uint256 public constant MINTER_ADD_TIMELOCK = 2 days;

    /// @notice Minter addresses — ปกติมีตัวเดียวคือ WTPIXBridgeMinter
    mapping(address => bool) public minters;

    /// @notice ตั้ง minter ตัวแรกไปแล้วหรือยัง (setInitialMinter ใช้ได้ครั้งเดียวตลอดอายุสัญญา)
    bool public initialMinterSet;

    /// @notice เวลาที่ minter ที่รอคิวจะ execute ได้ (0 = ไม่มีคิว)
    mapping(address => uint256) public pendingMinterExecuteAfter;

    event MinterSet(address indexed minter, bool status);
    event MinterQueued(address indexed minter, uint256 executeAfter);
    event MinterCancelled(address indexed minter);
    event BridgeContractQueued(address indexed bridge, uint256 executeAfter);
    event BridgeContractCancelled(address indexed bridge);
    event BridgeContractSet(address indexed bridge);

    constructor() ERC20("Wrapped TPIX", "wTPIX") Ownable(msg.sender) {}

    /**
     * @notice ตั้ง minter ตัวแรกทันที — ใช้ได้ครั้งเดียว (สคริปต์ deploy ผูก WTPIXBridgeMinter ในรอบเดียวกับที่ deploy)
     * @param minter ที่อยู่ contract ที่มีสิทธิ์ mint
     */
    function setInitialMinter(address minter) external onlyOwner {
        require(!initialMinterSet, "WTPIX: initial minter already set");
        require(minter != address(0), "WTPIX: zero minter");
        initialMinterSet = true;
        minters[minter] = true;
        emit MinterSet(minter, true);
    }

    /**
     * @notice เข้าคิวเพิ่ม minter — execute ได้หลัง MINTER_ADD_TIMELOCK
     * @dev คีย์เจ้าของหลุดก็เพิ่ม minter ฉับพลันไม่ได้ — ทีมมีเวลา 2 วันเห็น event แล้วย้ายเจ้าของ/pause
     */
    function queueMinter(address minter) external onlyOwner {
        require(minter != address(0), "WTPIX: zero minter");
        require(!minters[minter], "WTPIX: already a minter");
        uint256 executeAfter = block.timestamp + MINTER_ADD_TIMELOCK;
        pendingMinterExecuteAfter[minter] = executeAfter;
        emit MinterQueued(minter, executeAfter);
    }

    /// @notice ยกเลิกคิวเพิ่ม minter
    function cancelMinter(address minter) external onlyOwner {
        require(pendingMinterExecuteAfter[minter] != 0, "WTPIX: no pending minter");
        delete pendingMinterExecuteAfter[minter];
        emit MinterCancelled(minter);
    }

    /// @notice เพิ่ม minter ที่รอคิวครบเวลาแล้ว
    function executeMinter(address minter) external onlyOwner {
        uint256 executeAfter = pendingMinterExecuteAfter[minter];
        require(executeAfter != 0, "WTPIX: no pending minter");
        require(block.timestamp >= executeAfter, "WTPIX: timelock not expired");
        delete pendingMinterExecuteAfter[minter];
        minters[minter] = true;
        emit MinterSet(minter, true);
    }

    /// @notice ถอดสิทธิ์ minter ทันที (และล้างคิวของที่อยู่นั้นถ้ามี) — ทางตัดตัวที่มีปัญหาให้เร็วที่สุด
    function removeMinter(address minter) external onlyOwner {
        require(minters[minter] || pendingMinterExecuteAfter[minter] != 0, "WTPIX: not a minter");
        minters[minter] = false;
        if (pendingMinterExecuteAfter[minter] != 0) {
            delete pendingMinterExecuteAfter[minter];
            emit MinterCancelled(minter);
        }
        emit MinterSet(minter, false);
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
     *
     * @dev แก้ 2026-08-05 (SECURITY-AUDIT ข้อ W1):
     *      เดิมมีแค่ `require(msg.sender == bridgeContract)` แล้ว `_burn(from, amount)`
     *      คอมเมนต์บอกว่า "ผู้ใช้ต้อง approve bridge contract ก่อน" แต่โค้ด
     *      **ไม่เคยตรวจ allowance เลย** → bridge เผาเหรียญของใครก็ได้โดยเจ้าของ
     *      ไม่ต้องยินยอม ถ้า bridge ถูกยึดหรือมีบั๊กสักจุด = เผา wTPIX ได้ทั้งเชน
     *      ตอนนี้หัก allowance จริงตาม ERC-20 semantics ที่คอมเมนต์อ้างไว้แต่แรก
     */
    function bridgeBurn(address from, uint256 amount) external whenNotPaused {
        require(msg.sender == bridgeContract, "WTPIX: only bridge");
        _spendAllowance(from, msg.sender, amount);
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
