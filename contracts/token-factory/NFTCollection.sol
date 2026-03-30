// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title NFTCollection — ERC-721 Collection with Mint Config, Delayed Reveal, Royalty
 * @author Xman Studio
 * @notice Phase 2 — NFT Collection ครบวงจร
 *
 * Features:
 *   - Mint types: public, whitelist, free
 *   - Mint price, max per wallet, max per tx
 *   - Owner reserve mint
 *   - Delayed reveal (placeholder → real metadata)
 *   - ERC-2981 Royalty
 *   - ERC-721 Enumerable (list all tokens)
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract NFTCollection is ERC721, ERC721Enumerable, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    uint256 public immutable maxSupply;

    /// @notice Mint type: 0=public, 1=whitelist, 2=free
    uint8 public immutable mintType;

    /// @notice Mint price in native token (wei)
    uint256 public immutable mintPrice;

    /// @notice Max mints per wallet (0 = unlimited)
    uint16 public immutable maxPerWallet;

    /// @notice Max mints per transaction (0 = unlimited)
    uint16 public immutable maxPerTx;

    /// @notice Royalty enabled
    bool public immutable isRoyaltyEnabled;

    /// @notice Delayed reveal enabled
    bool public immutable isDelayedReveal;

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    uint256 private _nextTokenId;

    /// @notice Base URI for metadata (post-reveal)
    string public baseURI;

    /// @notice Placeholder URI (pre-reveal)
    string public placeholderURI;

    /// @notice Whether collection has been revealed
    bool public revealed;

    /// @notice Whitelist
    mapping(address => bool) public whitelisted;

    /// @notice Mints per address (สำหรับ maxPerWallet check)
    mapping(address => uint256) public mintedCount;

    /// @notice Minting active
    bool public mintingActive;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event Minted(address indexed to, uint256 indexed tokenId);
    event BatchMinted(address indexed to, uint256 fromId, uint256 quantity);
    event Revealed(string newBaseURI);
    event WhitelistUpdated(address indexed account, bool status);
    event MintingToggled(bool active);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    /**
     * @param name_            Collection name
     * @param symbol_          Collection symbol
     * @param owner_           Collection owner
     * @param maxSupply_       Maximum tokens in collection
     * @param mintType_        0=public, 1=whitelist, 2=free
     * @param mintPrice_       Price per mint (wei, 0 = free)
     * @param maxPerWallet_    Max per wallet (0 = unlimited)
     * @param maxPerTx_        Max per tx (0 = unlimited)
     * @param reserveCount_    Owner reserve mint count
     * @param baseURI_         Base metadata URI
     * @param placeholderURI_  Placeholder URI for delayed reveal
     * @param delayedReveal_   Enable delayed reveal
     * @param royaltyEnabled_  Enable ERC-2981
     * @param royaltyRecipient_ Royalty recipient
     * @param royaltyBps_      Royalty rate (basis points)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        uint256 maxSupply_,
        uint8 mintType_,
        uint256 mintPrice_,
        uint16 maxPerWallet_,
        uint16 maxPerTx_,
        uint16 reserveCount_,
        string memory baseURI_,
        string memory placeholderURI_,
        bool delayedReveal_,
        bool royaltyEnabled_,
        address royaltyRecipient_,
        uint16 royaltyBps_
    ) ERC721(name_, symbol_) Ownable(owner_) {
        require(maxSupply_ > 0, "COL: zero max supply");
        require(mintType_ <= 2, "COL: invalid mint type");
        require(royaltyBps_ <= 5000, "COL: royalty > 50%");
        require(reserveCount_ <= maxSupply_, "COL: reserve > supply");

        maxSupply = maxSupply_;
        mintType = mintType_;
        mintPrice = mintPrice_;
        maxPerWallet = maxPerWallet_;
        maxPerTx = maxPerTx_;
        isDelayedReveal = delayedReveal_;
        isRoyaltyEnabled = royaltyEnabled_;

        baseURI = baseURI_;
        placeholderURI = delayedReveal_ ? placeholderURI_ : "";
        revealed = !delayedReveal_;

        _nextTokenId = 1;

        // Setup royalty
        if (royaltyEnabled_) {
            address recipient = royaltyRecipient_ != address(0) ? royaltyRecipient_ : owner_;
            _setDefaultRoyalty(recipient, royaltyBps_);
        }

        // Reserve mint
        if (reserveCount_ > 0) {
            for (uint16 i = 0; i < reserveCount_; i++) {
                _safeMint(owner_, _nextTokenId);
                emit Minted(owner_, _nextTokenId);
                _nextTokenId++;
            }
            mintedCount[owner_] = reserveCount_;
        }
    }

    // ═══════════════════════════════════════════
    //  PUBLIC MINT
    // ═══════════════════════════════════════════

    /// @notice Mint NFTs
    function mint(uint256 quantity) external payable nonReentrant {
        require(mintingActive, "COL: minting not active");
        require(quantity > 0, "COL: zero quantity");
        require(_nextTokenId + quantity - 1 <= maxSupply, "COL: exceeds max supply");

        // Max per tx
        if (maxPerTx > 0) {
            require(quantity <= maxPerTx, "COL: exceeds max per tx");
        }

        // Max per wallet
        if (maxPerWallet > 0) {
            require(mintedCount[msg.sender] + quantity <= maxPerWallet, "COL: exceeds max per wallet");
        }

        // Whitelist check
        if (mintType == 1) {
            require(whitelisted[msg.sender], "COL: not whitelisted");
        }

        // Payment check (type 2 = free, skip)
        if (mintType != 2 && mintPrice > 0) {
            require(msg.value >= mintPrice * quantity, "COL: insufficient payment");
        }

        // Mint
        uint256 startId = _nextTokenId;
        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(msg.sender, _nextTokenId);
            _nextTokenId++;
        }
        mintedCount[msg.sender] += quantity;

        emit BatchMinted(msg.sender, startId, quantity);

        // Refund excess payment
        if (msg.value > mintPrice * quantity) {
            uint256 refund = msg.value - (mintPrice * quantity);
            (bool sent, ) = msg.sender.call{value: refund}("");
            require(sent, "COL: refund failed");
        }
    }

    // ═══════════════════════════════════════════
    //  REVEAL
    // ═══════════════════════════════════════════

    /// @notice Reveal the collection (set real baseURI)
    function reveal(string calldata newBaseURI) external onlyOwner {
        require(isDelayedReveal, "COL: not delayed reveal");
        require(!revealed, "COL: already revealed");
        baseURI = newBaseURI;
        revealed = true;
        emit Revealed(newBaseURI);
    }

    // ═══════════════════════════════════════════
    //  METADATA
    // ═══════════════════════════════════════════

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireOwned(tokenId);

        // Pre-reveal: return placeholder
        if (!revealed) {
            return placeholderURI;
        }

        return string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
    }

    // ═══════════════════════════════════════════
    //  OWNER FUNCTIONS
    // ═══════════════════════════════════════════

    function toggleMinting() external onlyOwner {
        mintingActive = !mintingActive;
        emit MintingToggled(mintingActive);
    }

    function setWhitelist(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelisted[accounts[i]] = status;
            emit WhitelistUpdated(accounts[i], status);
        }
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    /// @notice Withdraw collected mint payments
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "COL: no balance");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "COL: withdraw failed");
    }

    /// @notice Update royalty (owner only)
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        require(isRoyaltyEnabled, "COL: royalty disabled");
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    // ═══════════════════════════════════════════
    //  VIEW
    // ═══════════════════════════════════════════

    function remainingSupply() external view returns (uint256) {
        return maxSupply - (_nextTokenId - 1);
    }

    function currentTokenId() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    // ═══════════════════════════════════════════
    //  REQUIRED OVERRIDES
    // ═══════════════════════════════════════════

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
