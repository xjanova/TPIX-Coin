// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FactoryERC20 — Token template deployed by TPIXTokenFactory
 * @author Xman Studio
 * @notice ERC-20 token with optional mint/burn capabilities
 *
 * Token Types:
 *   0 = standard       (fixed supply, no mint, no burn)
 *   1 = mintable        (owner can mint more)
 *   2 = burnable        (holders can burn their tokens)
 *   3 = mintable_burnable (both)
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract FactoryERC20 is ERC20, Ownable {

    uint8 private immutable _decimals;
    bool public immutable isMintable;
    bool public immutable isBurnable;

    /**
     * @param name_        Token name
     * @param symbol_      Token ticker
     * @param decimals_    Token decimals (0-18)
     * @param totalSupply_ Initial supply in smallest unit (already multiplied by 10^decimals)
     * @param owner_       Token owner who receives the initial supply
     * @param mintable_    Whether the owner can mint additional tokens
     * @param burnable_    Whether holders can burn their tokens
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address owner_,
        bool mintable_,
        bool burnable_
    ) ERC20(name_, symbol_) Ownable(owner_) {
        _decimals = decimals_;
        isMintable = mintable_;
        isBurnable = burnable_;

        if (totalSupply_ > 0) {
            _mint(owner_, totalSupply_);
        }
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Mint new tokens (only if mintable)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(isMintable, "FactoryERC20: minting disabled");
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from caller (only if burnable)
     */
    function burn(uint256 amount) external {
        require(isBurnable, "FactoryERC20: burning disabled");
        _burn(msg.sender, amount);
    }

    /**
     * @notice Burn tokens from another account with allowance (only if burnable)
     */
    function burnFrom(address account, uint256 amount) external {
        require(isBurnable, "FactoryERC20: burning disabled");
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }
}
