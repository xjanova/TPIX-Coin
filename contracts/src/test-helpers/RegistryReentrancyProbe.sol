// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * TEST ONLY — ห้าม deploy ขึ้นเชนจริง
 *
 * operator ที่เป็นสัญญา แล้วพยายามเรียก claimRewards / deregisterNode ซ้ำ
 * ตอนรับเงินรางวัล (reentrancy) — ใช้พิสูจน์ใน test/NodeRegistryV2.test.js
 * ว่าได้เงินแค่รอบเดียว และเงินต้นของคนอื่นไม่ถูกแตะ
 */
interface INodeRegistryV2Probe {
    function registerNode(uint8 _tier, string calldata _endpoint) external payable;
    function claimRewards() external;
    function deregisterNode() external;
}

contract RegistryReentrancyProbe {
    INodeRegistryV2Probe public immutable registry;
    uint256 public reentryAttempts;
    uint256 public reentrySucceeded;

    constructor(address _registry) {
        registry = INodeRegistryV2Probe(_registry);
    }

    function register(uint8 _tier, string calldata _endpoint) external payable {
        registry.registerNode{value: msg.value}(_tier, _endpoint);
    }

    function claim() external {
        registry.claimRewards();
    }

    function exit() external {
        registry.deregisterNode();
    }

    receive() external payable {
        // ลองเจาะซ้ำแค่ครั้งเดียวต่อการรับเงิน — ถ้า guard ทำงาน call ข้างในต้อง revert
        if (reentryAttempts < 2) {
            reentryAttempts++;
            try registry.claimRewards() {
                reentrySucceeded++;
            } catch {}
            try registry.deregisterNode() {
                reentrySucceeded++;
            } catch {}
        }
    }
}
