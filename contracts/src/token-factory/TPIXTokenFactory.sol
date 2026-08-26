// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FactoryERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TPIXTokenFactory — Deploy ERC-20 tokens on TPIX Chain
 * @author Xman Studio
 * @notice Factory contract for creating custom ERC-20 tokens via CREATE2
 *
 * Only the deployer (backend service wallet) can create tokens.
 * Each token gets a deterministic address based on salt = keccak256(nonce).
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract TPIXTokenFactory is Ownable {

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    /// @notice Auto-incrementing nonce for CREATE2 salt
    uint256 public nonce;

    /// @notice All deployed token addresses
    address[] public deployedTokens;

    /// @notice Token info by address
    struct TokenInfo {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        address tokenOwner;
        uint8 tokenType; // 0=standard, 1=mintable, 2=burnable, 3=mintable_burnable
        uint256 createdAt;
    }

    mapping(address => TokenInfo) public tokenInfo;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event TokenCreated(
        address indexed tokenAddress,
        string name,
        string symbol,
        uint8 decimals,
        uint256 totalSupply,
        address indexed tokenOwner,
        uint8 tokenType
    );

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    constructor() Ownable(msg.sender) {}

    // ═══════════════════════════════════════════
    //  CORE: Create Token
    // ═══════════════════════════════════════════

    /**
     * @notice Deploy a new ERC-20 token via CREATE2
     * @param name_        Token name (e.g., "My Token")
     * @param symbol_      Token symbol (e.g., "MTK")
     * @param decimals_    Decimals (0-18)
     * @param totalSupply_ Total supply in smallest unit (pre-multiplied by 10^decimals)
     * @param tokenOwner_  Address that receives the initial supply and owns the token
     * @param tokenType_   0=standard, 1=mintable, 2=burnable, 3=mintable_burnable
     * @return tokenAddress The deployed token contract address
     */
    function createToken(
        string calldata name_,
        string calldata symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address tokenOwner_,
        uint8 tokenType_
    ) external onlyOwner returns (address tokenAddress) {
        require(bytes(name_).length > 0, "Factory: empty name");
        require(bytes(symbol_).length > 0, "Factory: empty symbol");
        require(decimals_ <= 18, "Factory: decimals > 18");
        require(tokenOwner_ != address(0), "Factory: zero owner");
        require(tokenType_ <= 3, "Factory: invalid type");

        // Determine mint/burn flags
        bool mintable = (tokenType_ == 1 || tokenType_ == 3);
        bool burnable = (tokenType_ == 2 || tokenType_ == 3);

        // CREATE2 with incrementing nonce as salt
        bytes32 salt = keccak256(abi.encodePacked(nonce));
        nonce++;

        FactoryERC20 token = new FactoryERC20{salt: salt}(
            name_,
            symbol_,
            decimals_,
            totalSupply_,
            tokenOwner_,
            mintable,
            burnable
        );

        tokenAddress = address(token);

        // Store in registry
        deployedTokens.push(tokenAddress);
        tokenInfo[tokenAddress] = TokenInfo({
            name: name_,
            symbol: symbol_,
            decimals: decimals_,
            totalSupply: totalSupply_,
            tokenOwner: tokenOwner_,
            tokenType: tokenType_,
            createdAt: block.timestamp
        });

        emit TokenCreated(
            tokenAddress,
            name_,
            symbol_,
            decimals_,
            totalSupply_,
            tokenOwner_,
            tokenType_
        );
    }

    // ═══════════════════════════════════════════
    //  VIEW
    // ═══════════════════════════════════════════

    /// @notice Total number of tokens created by this factory
    function totalTokens() external view returns (uint256) {
        return deployedTokens.length;
    }

    /// @notice Get deployed token address by index
    function getToken(uint256 index) external view returns (address) {
        return deployedTokens[index];
    }
}
