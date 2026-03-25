// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TPIXTokenSale — สัญญาขายเหรียญ TPIX บน BSC
 * @author Xman Studio
 * @notice รับ BNB / USDT / BUSD แล้วบันทึก allocation ให้ผู้ซื้อ
 * Backend verify transaction แล้ว mint wTPIX ให้ทีหลัง (หรือ record allocation)
 *
 * Design: On-chain payment collection → backend verify → off-chain allocation
 * เหตุผล: ปลอดภัยกว่าการ mint ทันที, ตรวจสอบได้ผ่าน tx_hash
 */
contract TPIXTokenSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // === State ===

    /// @notice Wallet ที่รับเงินจากการขาย
    address public treasuryWallet;

    /// @notice สกุลเงินที่รับ (USDT, BUSD addresses บน BSC)
    mapping(address => bool) public acceptedTokens;

    /// @notice สถานะ sale (เปิด/ปิด)
    bool public saleActive;

    /// @notice จำนวน BNB ที่ได้รับทั้งหมด
    uint256 public totalBnbRaised;

    /// @notice จำนวน token ที่ได้รับทั้งหมด (USDT/BUSD)
    mapping(address => uint256) public totalTokenRaised;

    // === Events ===

    event PurchaseWithBNB(address indexed buyer, uint256 amount, uint256 timestamp);
    event PurchaseWithToken(address indexed buyer, address indexed token, uint256 amount, uint256 timestamp);
    event SaleStatusChanged(bool active);
    event TreasuryWalletChanged(address indexed newWallet);
    event TokenAccepted(address indexed token, bool accepted);
    event FundsWithdrawn(address indexed token, uint256 amount);

    constructor(address _treasuryWallet) Ownable(msg.sender) {
        require(_treasuryWallet != address(0), "Invalid treasury");
        treasuryWallet = _treasuryWallet;
        saleActive = false;
    }

    // === Purchase Functions ===

    /**
     * @notice ซื้อด้วย BNB — ส่ง BNB ตรงมาที่ contract
     * เงินจะถูกส่งต่อไป treasury wallet ทันที
     */
    function purchaseWithBNB() external payable nonReentrant {
        require(saleActive, "Sale not active");
        require(msg.value > 0, "Amount must be > 0");

        // ส่ง BNB ไปที่ treasury wallet ทันที (ไม่เก็บไว้ใน contract)
        (bool sent, ) = payable(treasuryWallet).call{value: msg.value}("");
        require(sent, "BNB transfer failed");

        totalBnbRaised += msg.value;

        emit PurchaseWithBNB(msg.sender, msg.value, block.timestamp);
    }

    /**
     * @notice ซื้อด้วย token (USDT/BUSD) — ผู้ซื้อต้อง approve ก่อน
     * @param token ที่อยู่ ERC-20 token (USDT/BUSD)
     * @param amount จำนวน token
     */
    function purchaseWithToken(address token, uint256 amount) external nonReentrant {
        require(saleActive, "Sale not active");
        require(acceptedTokens[token], "Token not accepted");
        require(amount > 0, "Amount must be > 0");

        // โอน token จากผู้ซื้อไป treasury wallet โดยตรง
        IERC20(token).safeTransferFrom(msg.sender, treasuryWallet, amount);

        totalTokenRaised[token] += amount;

        emit PurchaseWithToken(msg.sender, token, amount, block.timestamp);
    }

    // === Admin Functions ===

    /**
     * @notice เปิด/ปิด sale
     */
    function setSaleActive(bool active) external onlyOwner {
        saleActive = active;
        emit SaleStatusChanged(active);
    }

    /**
     * @notice เปลี่ยน treasury wallet
     */
    function setTreasuryWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid wallet");
        treasuryWallet = newWallet;
        emit TreasuryWalletChanged(newWallet);
    }

    /**
     * @notice ตั้งค่า token ที่ยอมรับ
     */
    function setAcceptedToken(address token, bool accepted) external onlyOwner {
        acceptedTokens[token] = accepted;
        emit TokenAccepted(token, accepted);
    }

    /**
     * @notice ถอนเงินฉุกเฉิน (กรณี BNB ค้างใน contract)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent, ) = payable(treasuryWallet).call{value: balance}("");
            require(sent, "Withdraw failed");
            emit FundsWithdrawn(address(0), balance);
        }
    }

    /**
     * @notice ถอน ERC-20 token ฉุกเฉิน
     */
    function emergencyWithdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(treasuryWallet, balance);
            emit FundsWithdrawn(token, balance);
        }
    }

    /// @notice รับ BNB ตรง (fallback)
    receive() external payable {
        if (saleActive) {
            totalBnbRaised += msg.value;
            (bool sent, ) = payable(treasuryWallet).call{value: msg.value}("");
            require(sent, "BNB transfer failed");
            emit PurchaseWithBNB(msg.sender, msg.value, block.timestamp);
        }
    }
}
