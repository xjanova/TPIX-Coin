// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title USDT_TPIX (Bridged Tether) — ERC-20 บน TPIX Chain
 * @author Xman Studio
 * @notice Wrapped Tether ที่ peg 1:1 กับ USDT จริง (BSC USDT-BEP20 / ETH USDT-ERC20)
 *         User bridge USDT จาก BSC/ETH มา → relayer mint USDT_TPIX ที่นี่
 *         User bridge ออก → burn USDT_TPIX → relayer unlock USDT ที่ chain ต้นทาง
 *
 * Decimals: 6 (เหมือน Tether จริง — กัน user งงเรื่องราคา)
 *
 * Security:
 *   - Mint/burn เฉพาะ relayer addresses ใน whitelist (multi-sig recommended)
 *   - Pausable เผื่อกรณี bridge exploit ต้อง freeze ทันที
 *   - ไม่มี max supply (peg 1:1 — supply ขึ้นกับยอด USDT ที่ lock บน chain ต้นทาง)
 */
contract USDT_TPIX is ERC20, ERC20Burnable, Ownable2Step, Pausable {
    /// @notice Whitelist ของ relayer addresses ที่ mint/burn ได้
    mapping(address => bool) public bridges;

    /// @notice Replay protection — sourceTxHash ที่ process แล้วห้าม mint ซ้ำ
    /// @dev สำคัญมาก: ถ้าไม่มีตัวนี้, compromised relayer สามารถ mint ซ้ำได้ไม่จำกัด
    mapping(bytes32 => bool) public processedTxHashes;

    /// @notice Total minted ตลอดอายุ (ไม่ลดเมื่อ burn — สำหรับ audit/proof)
    uint256 public totalEverMinted;

    /// @notice Total burned ตลอดอายุ (สำหรับ reconciliation กับ source chain)
    uint256 public totalEverBurned;

    event BridgeSet(address indexed bridge, bool status);
    event Minted(address indexed to, uint256 amount, bytes32 indexed sourceTxHash);
    event Burned(address indexed from, uint256 amount, uint256 indexed targetChainId, string targetAddress);

    constructor() ERC20("Tether USD (TPIX bridged)", "USDT") Ownable(msg.sender) {}

    /// @notice เลขทศนิยม — ตั้ง 6 ให้ตรงกับ Tether จริง
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // =========================================================================
    // Admin
    // =========================================================================

    /**
     * @notice ตั้ง relayer/bridge address ที่อนุญาตให้ mint/burn
     * @dev ควรเป็น multi-sig wallet ที่ team controls — ห้ามใช้ EOA หลัก deploy
     */
    function setBridge(address bridge, bool status) external onlyOwner {
        bridges[bridge] = status;
        emit BridgeSet(bridge, status);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =========================================================================
    // Bridge mint/burn (relayer-only)
    // =========================================================================

    /**
     * @notice Mint USDT_TPIX ให้ user — เรียกหลังตรวจ deposit บน chain ต้นทาง
     * @param to ที่อยู่ผู้รับบน TPIX chain
     * @param amount จำนวน (6 decimals — ตรงกับ Tether)
     * @param sourceTxHash tx hash ของ deposit บน source chain (unique key — ป้องกัน replay)
     * @dev sourceTxHash ใช้เป็น nonce — ห้ามใช้ tx hash เดียวกัน mint ซ้ำ
     */
    function bridgeMint(address to, uint256 amount, bytes32 sourceTxHash)
        external
        whenNotPaused
    {
        require(bridges[msg.sender], "USDT_TPIX: not a bridge");
        require(to != address(0), "USDT_TPIX: zero recipient");
        require(amount > 0, "USDT_TPIX: zero amount");
        require(sourceTxHash != bytes32(0), "USDT_TPIX: empty txhash");
        require(!processedTxHashes[sourceTxHash], "USDT_TPIX: txhash replayed");

        // CEI: state ก่อน external interaction
        processedTxHashes[sourceTxHash] = true;
        totalEverMinted += amount;

        _mint(to, amount);
        emit Minted(to, amount, sourceTxHash);
    }

    /**
     * @notice Burn USDT_TPIX จาก user — user เรียกเอง (พร้อม approve เผื่อ bridge เป็น contract)
     * @param amount จำนวน
     * @param targetChainId chain id ปลายทาง (1=ETH, 56=BSC, ฯลฯ — uint256 ตามมาตรฐาน EIP-155)
     * @param targetAddress ที่อยู่ปลายทาง (string เผื่อ chain ที่ไม่ใช่ EVM ในอนาคต)
     */
    function bridgeBurn(uint256 amount, uint256 targetChainId, string calldata targetAddress)
        external
        whenNotPaused
    {
        require(amount > 0, "USDT_TPIX: zero amount");
        require(targetChainId != 0, "USDT_TPIX: zero chain id");
        require(bytes(targetAddress).length > 0, "USDT_TPIX: empty target");

        totalEverBurned += amount;
        _burn(msg.sender, amount);
        emit Burned(msg.sender, amount, targetChainId, targetAddress);
    }

    // =========================================================================
    // Pausable hook
    // =========================================================================

    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
