// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CreatorAccess — ให้ creator รับคำสั่งสร้างจาก factory ตัวเดียวเท่านั้น
 * @author Xman Studio
 *
 * ทำไมต้องมี (ออดิท 2026-10-11): create() ของ creator ทุกตัวเคยเรียกได้จากทุกคน
 *   1. ข้ามการตรวจของ factory ได้หมด — คนนอกสร้างเหรียญ decimals=77 ได้ตรง ๆ
 *   2. salt ของ factory = keccak(nonce) ซึ่งเดาได้ → เห็น tx ของ factory ใน mempool แล้ว
 *      ยิง create() ตัดหน้าด้วยพารามิเตอร์ชุดเดียวกัน → CREATE2 ชนที่อยู่ → tx ของ factory
 *      revert ถาวรสำหรับพารามิเตอร์ชุดนั้น และบนเชนค่าแก๊ส 0 การป่วนนี้ฟรี
 *
 * factory ต้อง deploy หลัง creator (constructor ของ factory รับที่อยู่ creator) จึงผูกกันทีหลัง
 * ด้วย bindFactory() — เรียกได้ครั้งเดียว โดยกระเป๋าที่ deploy creator เท่านั้น แล้วเปลี่ยนไม่ได้อีก
 */
abstract contract CreatorAccess {
    /// @notice กระเป๋าที่ deploy creator — คนเดียวที่ผูก factory ได้
    address public immutable deployer;

    /// @notice factory ที่ได้รับอนุญาตให้เรียก create() (address(0) = ยังไม่ผูก สร้างไม่ได้)
    address public factory;

    event FactoryBound(address indexed factory);

    error NotDeployer();
    error FactoryAlreadyBound();
    error ZeroFactory();
    error NotFactory();

    constructor() {
        deployer = msg.sender;
    }

    function bindFactory(address factory_) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (factory != address(0)) revert FactoryAlreadyBound();
        if (factory_ == address(0)) revert ZeroFactory();
        factory = factory_;
        emit FactoryBound(factory_);
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }
}
