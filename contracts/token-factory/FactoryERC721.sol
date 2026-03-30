// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FactoryERC721 — Single NFT with Royalty + Soulbound
 * @author Xman Studio
 * @notice Phase 2 — NFT เดี่ยว สร้างพร้อม mint ให้ owner ทันที
 *
 * Features:
 *   - Single token (tokenId = 1) minted to owner
 *   - ERC-2981 Royalty standard
 *   - Soulbound (SBT): non-transferable option
 *   - Metadata URI: IPFS / on-chain / URL
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract FactoryERC721 is ERC721, ERC721URIStorage, ERC2981, Ownable {

    // ═══════════════════════════════════════════
    //  CONFIG
    // ═══════════════════════════════════════════

    bool public immutable isSoulbound;
    bool public immutable isRoyaltyEnabled;
    uint256 public immutable totalMinted;

    /// @notice Next token ID for additional mints
    uint256 private _nextTokenId;

    /// @notice Maximum tokens (0 = unlimited for mintable, 1 = single)
    uint256 public immutable maxSupply;

    /// @notice Whether owner can mint more
    bool public immutable isMintable;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event NFTMinted(address indexed to, uint256 indexed tokenId, string tokenURI);

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    /**
     * @param name_              NFT name
     * @param symbol_            NFT symbol
     * @param owner_             NFT owner
     * @param tokenURI_          Metadata URI (IPFS/URL/on-chain)
     * @param maxSupply_         Max tokens (1 = single NFT, 0 = unlimited)
     * @param mintable_          Owner can mint more
     * @param soulbound_         Non-transferable (SBT)
     * @param royaltyEnabled_    Enable ERC-2981 royalty
     * @param royaltyRecipient_  Address that receives royalties
     * @param royaltyBps_        Royalty rate in basis points (e.g., 500 = 5%)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_,
        string memory tokenURI_,
        uint256 maxSupply_,
        bool mintable_,
        bool soulbound_,
        bool royaltyEnabled_,
        address royaltyRecipient_,
        uint16 royaltyBps_
    ) ERC721(name_, symbol_) Ownable(owner_) {
        require(royaltyBps_ <= 5000, "NFT: royalty > 50%");

        isSoulbound = soulbound_;
        isRoyaltyEnabled = royaltyEnabled_;
        maxSupply = maxSupply_ == 0 ? 1 : maxSupply_;
        isMintable = mintable_;

        // Setup royalty
        if (royaltyEnabled_) {
            address recipient = royaltyRecipient_ != address(0) ? royaltyRecipient_ : owner_;
            _setDefaultRoyalty(recipient, royaltyBps_);
        }

        // Mint first token to owner
        _nextTokenId = 1;
        _safeMint(owner_, _nextTokenId);
        _setTokenURI(_nextTokenId, tokenURI_);
        totalMinted = 1;
        _nextTokenId = 2;

        emit NFTMinted(owner_, 1, tokenURI_);
    }

    // ═══════════════════════════════════════════
    //  SOULBOUND OVERRIDE
    // ═══════════════════════════════════════════

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Soulbound: block transfers (allow mint only)
        if (isSoulbound && from != address(0) && to != address(0)) {
            revert("NFT: soulbound, non-transferable");
        }

        return super._update(to, tokenId, auth);
    }

    // ═══════════════════════════════════════════
    //  MINT
    // ═══════════════════════════════════════════

    /// @notice Mint additional NFTs (if mintable)
    function mint(address to, string calldata uri) external onlyOwner {
        require(isMintable, "NFT: minting disabled");
        require(_nextTokenId <= maxSupply, "NFT: max supply reached");

        _safeMint(to, _nextTokenId);
        _setTokenURI(_nextTokenId, uri);

        emit NFTMinted(to, _nextTokenId, uri);
        _nextTokenId++;
    }

    /// @notice Burn a token (owner of token only)
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "NFT: not token owner");
        _burn(tokenId);
    }

    // ═══════════════════════════════════════════
    //  ROYALTY
    // ═══════════════════════════════════════════

    /// @notice Update default royalty (owner only)
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        require(isRoyaltyEnabled, "NFT: royalty disabled");
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    // ═══════════════════════════════════════════
    //  VIEW
    // ═══════════════════════════════════════════

    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    // ═══════════════════════════════════════════
    //  REQUIRED OVERRIDES
    // ═══════════════════════════════════════════

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
