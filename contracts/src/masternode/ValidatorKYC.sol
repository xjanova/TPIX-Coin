// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TPIX Validator KYC Registry
 * @notice On-chain KYC status tracking for Validator-tier applicants
 * @dev PDPA-Compliant Design:
 *      - NO personal data stored on-chain (name, passport, company docs)
 *      - Only keccak256 hash of encrypted KYC bundle stored on-chain
 *      - Off-chain: encrypted KYC data in admin system with access logging
 *      - Right to erasure: admin can clear kycHash while preserving approval status
 *      - Consent tracked on-chain: applicant must call giveConsent() before submission
 *
 * Flow:
 *   1. Applicant gives PDPA consent on-chain (giveConsent)
 *   2. Applicant submits KYC documents off-chain (via tpix.online admin panel)
 *   3. Admin reviews documents, submits kycHash on-chain (submitKYC)
 *   4. Admin approves or rejects (approveKYC / rejectKYC)
 *   5. If approved, applicant can register as Validator in NodeRegistryV2
 *   6. Applicant can request data erasure (revokeConsent → admin erases off-chain data)
 */
contract ValidatorKYC is Ownable {

    // ============================================================
    //  Types
    // ============================================================

    enum KYCStatus { None, ConsentGiven, Submitted, Approved, Rejected, Revoked }

    struct KYCRecord {
        address applicant;
        KYCStatus status;
        bytes32 kycHash;          // keccak256 of encrypted KYC data bundle
        uint256 consentAt;        // When PDPA consent was given
        uint256 submittedAt;      // When KYC was submitted by admin
        uint256 reviewedAt;       // When admin approved/rejected
        address reviewer;         // Admin who reviewed
        string rejectReason;      // Reason for rejection (if any)
    }

    // ============================================================
    //  State
    // ============================================================

    mapping(address => KYCRecord) public records;
    address[] public applicants;

    // PDPA consent text hash — applicant signs this before submitting
    bytes32 public consentTextHash;

    // ============================================================
    //  Events
    // ============================================================

    event ConsentGiven(address indexed applicant, uint256 timestamp);
    event ConsentRevoked(address indexed applicant, uint256 timestamp);
    event KYCSubmitted(address indexed applicant, bytes32 kycHash);
    event KYCApproved(address indexed applicant, address indexed reviewer);
    event KYCRejected(address indexed applicant, address indexed reviewer, string reason);
    event KYCDataErased(address indexed applicant);
    event ConsentTextUpdated(bytes32 indexed consentTextHash);

    // ============================================================
    //  Constructor
    // ============================================================

    constructor(bytes32 _consentTextHash) Ownable(msg.sender) {
        consentTextHash = _consentTextHash;
    }

    // ============================================================
    //  Applicant Functions
    // ============================================================

    /**
     * @notice Give PDPA consent — required before KYC submission
     * @dev Applicant acknowledges data collection purpose and rights
     */
    function giveConsent() external {
        KYCRecord storage r = records[msg.sender];
        require(r.status == KYCStatus.None || r.status == KYCStatus.Revoked, "Consent already active");

        if (r.applicant == address(0)) {
            applicants.push(msg.sender);
        }

        r.applicant = msg.sender;
        r.status = KYCStatus.ConsentGiven;
        r.consentAt = block.timestamp;
        // Clear previous rejection data if re-applying
        r.kycHash = bytes32(0);
        r.rejectReason = "";

        emit ConsentGiven(msg.sender, block.timestamp);
    }

    /**
     * @notice Revoke PDPA consent — triggers right to erasure
     * @dev After revoking, admin must erase off-chain KYC data
     */
    function revokeConsent() external {
        KYCRecord storage r = records[msg.sender];
        require(
            r.status == KYCStatus.ConsentGiven ||
            r.status == KYCStatus.Submitted ||
            r.status == KYCStatus.Rejected,
            "Cannot revoke in current state"
        );

        r.status = KYCStatus.Revoked;
        r.kycHash = bytes32(0); // Clear on-chain hash

        emit ConsentRevoked(msg.sender, block.timestamp);
    }

    // ============================================================
    //  Admin Functions
    // ============================================================

    /**
     * @notice Submit KYC hash after receiving off-chain documents
     * @param _applicant Applicant address
     * @param _kycHash keccak256 hash of the encrypted KYC data bundle
     */
    function submitKYC(address _applicant, bytes32 _kycHash) external onlyOwner {
        KYCRecord storage r = records[_applicant];
        require(r.status == KYCStatus.ConsentGiven, "Consent not given");
        require(_kycHash != bytes32(0), "Invalid hash");

        r.status = KYCStatus.Submitted;
        r.kycHash = _kycHash;
        r.submittedAt = block.timestamp;

        emit KYCSubmitted(_applicant, _kycHash);
    }

    /**
     * @notice Approve KYC — applicant can now register as Validator
     */
    function approveKYC(address _applicant) external onlyOwner {
        KYCRecord storage r = records[_applicant];
        require(r.status == KYCStatus.Submitted, "Not submitted");

        r.status = KYCStatus.Approved;
        r.reviewedAt = block.timestamp;
        r.reviewer = msg.sender;

        emit KYCApproved(_applicant, msg.sender);
    }

    /**
     * @notice Reject KYC with reason
     */
    function rejectKYC(address _applicant, string calldata _reason) external onlyOwner {
        KYCRecord storage r = records[_applicant];
        require(r.status == KYCStatus.Submitted, "Not submitted");

        r.status = KYCStatus.Rejected;
        r.reviewedAt = block.timestamp;
        r.reviewer = msg.sender;
        r.rejectReason = _reason;

        emit KYCRejected(_applicant, msg.sender, _reason);
    }

    /**
     * @notice Erase KYC data hash — PDPA right to erasure
     * @dev Admin must also delete off-chain encrypted data separately
     */
    function eraseKYCData(address _applicant) external onlyOwner {
        KYCRecord storage r = records[_applicant];
        r.kycHash = bytes32(0);
        r.rejectReason = "";

        emit KYCDataErased(_applicant);
    }

    /**
     * @notice Update PDPA consent text hash
     */
    function updateConsentText(bytes32 _consentTextHash) external onlyOwner {
        consentTextHash = _consentTextHash;
        emit ConsentTextUpdated(_consentTextHash);
    }

    // ============================================================
    //  View Functions
    // ============================================================

    /**
     * @notice Check if an address has approved KYC (used by NodeRegistryV2)
     */
    function isApproved(address _applicant) external view returns (bool) {
        return records[_applicant].status == KYCStatus.Approved;
    }

    function getRecord(address _applicant) external view returns (KYCRecord memory) {
        return records[_applicant];
    }

    function getApplicantCount() external view returns (uint256) {
        return applicants.length;
    }
}
