// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./FactoryERC721.sol";
import "./NFTCollection.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TPIXNFTFactory — Deploy NFT Tokens (Single + Collection)
 * @author Xman Studio
 * @notice Phase 2 — Factory สำหรับ ERC-721 ทุกประเภท
 *
 * NFT Categories:
 *   0 = Single NFT    (FactoryERC721 — mint 1 NFT ทันที)
 *   1 = Collection     (NFTCollection — public/whitelist/free mint)
 *
 * Deployed on TPIX Chain (ID: 4289) — Gas FREE
 */
contract TPIXNFTFactory is Ownable {

    // ═══════════════════════════════════════════
    //  STATE
    // ═══════════════════════════════════════════

    uint256 public nonce;
    address[] public deployedNFTs;

    struct NFTRecord {
        string name;
        string symbol;
        address tokenOwner;
        uint8 nftType;    // 0=single, 1=collection
        uint256 createdAt;
    }

    mapping(address => NFTRecord) public nftRecords;

    // ═══════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════

    event NFTCreated(
        address indexed nftAddress,
        string name,
        string symbol,
        address indexed tokenOwner,
        uint8 nftType
    );

    // ═══════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════

    constructor() Ownable(msg.sender) {}

    // ═══════════════════════════════════════════
    //  INTERNAL
    // ═══════════════════════════════════════════

    function _nextSalt() internal returns (bytes32) {
        bytes32 salt = keccak256(abi.encodePacked(nonce));
        nonce++;
        return salt;
    }

    function _register(address nft, string memory name_, string memory symbol_, address owner_, uint8 type_) internal {
        deployedNFTs.push(nft);
        nftRecords[nft] = NFTRecord({
            name: name_,
            symbol: symbol_,
            tokenOwner: owner_,
            nftType: type_,
            createdAt: block.timestamp
        });
        emit NFTCreated(nft, name_, symbol_, owner_, type_);
    }

    // ═══════════════════════════════════════════
    //  CREATE: Single NFT (type 0)
    // ═══════════════════════════════════════════

    function createNFT(
        string calldata name_,
        string calldata symbol_,
        address owner_,
        string calldata tokenURI_,
        uint256 maxSupply_,
        bool mintable_,
        bool soulbound_,
        bool royaltyEnabled_,
        address royaltyRecipient_,
        uint16 royaltyBps_
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        FactoryERC721 nft = new FactoryERC721{salt: salt}(
            name_, symbol_, owner_, tokenURI_,
            maxSupply_, mintable_, soulbound_,
            royaltyEnabled_, royaltyRecipient_, royaltyBps_
        );

        address addr = address(nft);
        _register(addr, name_, symbol_, owner_, 0);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  CREATE: NFT Collection (type 1)
    // ═══════════════════════════════════════════

    function createNFTCollection(
        string calldata name_,
        string calldata symbol_,
        address owner_,
        uint256 maxSupply_,
        uint8 mintType_,
        uint256 mintPrice_,
        uint16 maxPerWallet_,
        uint16 maxPerTx_,
        uint16 reserveCount_,
        string calldata baseURI_,
        string calldata placeholderURI_,
        bool delayedReveal_,
        bool royaltyEnabled_,
        address royaltyRecipient_,
        uint16 royaltyBps_
    ) external onlyOwner returns (address) {
        bytes32 salt = _nextSalt();

        NFTCollection nft = new NFTCollection{salt: salt}(
            name_, symbol_, owner_, maxSupply_,
            mintType_, mintPrice_, maxPerWallet_, maxPerTx_,
            reserveCount_, baseURI_, placeholderURI_,
            delayedReveal_, royaltyEnabled_, royaltyRecipient_, royaltyBps_
        );

        address addr = address(nft);
        _register(addr, name_, symbol_, owner_, 1);
        return addr;
    }

    // ═══════════════════════════════════════════
    //  VIEW
    // ═══════════════════════════════════════════

    function totalNFTs() external view returns (uint256) {
        return deployedNFTs.length;
    }

    function getNFT(uint256 index) external view returns (address) {
        return deployedNFTs[index];
    }
}
