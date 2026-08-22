// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TPIX Validator Governance
 * @notice On-chain governance for IBFT2 Validator-tier nodes
 * @dev Only Validator-tier nodes (10M TPIX stake, KYC-approved) can create and vote on proposals.
 *      Validators act as the "board of directors" for TPIX Chain governance.
 *
 * Proposal Types:
 *   - AddValidator: Propose adding a new IBFT2 validator
 *   - RemoveValidator: Propose removing an IBFT2 validator
 *   - ChangeParameter: Propose changing a protocol parameter
 *   - UpgradeContract: Propose upgrading a smart contract
 *   - General: General governance proposal
 *
 * Voting Rules:
 *   - Quorum: >50% of active validators must vote
 *   - Approval: >50% of votes must be "for"
 *   - Voting period: 7 days
 *   - Timelock: 48 hours after vote passes before execution
 *   - One vote per validator per proposal
 */
contract ValidatorGovernance is Ownable, ReentrancyGuard {

    // ============================================================
    //  Types
    // ============================================================

    enum ProposalType { AddValidator, RemoveValidator, ChangeParameter, UpgradeContract, General }
    enum ProposalStatus { Active, Passed, Rejected, Executed, Cancelled }
    enum Vote { None, For, Against }

    struct Proposal {
        uint256 id;
        address proposer;
        ProposalType proposalType;
        ProposalStatus status;
        string title;
        string description;
        bytes data;               // Encoded action data (address for Add/Remove, bytes for params)
        uint256 createdAt;
        uint256 votingEndsAt;
        uint256 executionUnlocksAt;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 totalEligible;    // Snapshot of active validators at creation
    }

    // ============================================================
    //  State
    // ============================================================

    // Reference to NodeRegistryV2 for validator checks
    address public nodeRegistry;

    // Proposals
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;

    // Votes: proposalId => voter => Vote
    mapping(uint256 => mapping(address => Vote)) public votes;

    // Config
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant TIMELOCK = 48 hours;
    uint256 public constant QUORUM_BPS = 5000; // 50% quorum

    // ============================================================
    //  Events
    // ============================================================

    event ProposalCreated(uint256 indexed id, address indexed proposer, ProposalType proposalType, string title);
    event VoteCast(uint256 indexed proposalId, address indexed voter, Vote vote);
    event ProposalFinalized(uint256 indexed id, ProposalStatus status);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCancelled(uint256 indexed id);
    event NodeRegistryUpdated(address indexed nodeRegistry);

    // ============================================================
    //  Modifiers
    // ============================================================

    modifier onlyValidator() {
        require(_isValidator(msg.sender), "Not a Validator-tier node");
        _;
    }

    // ============================================================
    //  Constructor
    // ============================================================

    constructor(address _nodeRegistry) Ownable(msg.sender) {
        require(_nodeRegistry != address(0), "Zero address");
        nodeRegistry = _nodeRegistry;
    }

    // ============================================================
    //  Proposal Lifecycle
    // ============================================================

    /**
     * @notice Create a new governance proposal
     * @param _type Proposal type
     * @param _title Short title
     * @param _description Detailed description
     * @param _data Encoded action data (e.g., abi.encode(address) for Add/RemoveValidator)
     */
    function createProposal(
        ProposalType _type,
        string calldata _title,
        string calldata _description,
        bytes calldata _data
    ) external onlyValidator returns (uint256) {
        require(bytes(_title).length > 0 && bytes(_title).length <= 200, "Invalid title");
        require(bytes(_description).length <= 5000, "Description too long");

        uint256 eligible = _activeValidatorCount();
        require(eligible >= 1, "No active validators");

        proposalCount++;
        uint256 id = proposalCount;

        proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            proposalType: _type,
            status: ProposalStatus.Active,
            title: _title,
            description: _description,
            data: _data,
            createdAt: block.timestamp,
            votingEndsAt: block.timestamp + VOTING_PERIOD,
            executionUnlocksAt: block.timestamp + VOTING_PERIOD + TIMELOCK,
            votesFor: 0,
            votesAgainst: 0,
            totalEligible: eligible
        });

        emit ProposalCreated(id, msg.sender, _type, _title);
        return id;
    }

    /**
     * @notice Cast a vote on an active proposal
     * @param _proposalId Proposal ID
     * @param _vote Vote.For or Vote.Against
     */
    function castVote(uint256 _proposalId, Vote _vote) external onlyValidator {
        require(_vote == Vote.For || _vote == Vote.Against, "Invalid vote");

        Proposal storage p = proposals[_proposalId];
        require(p.id > 0, "Proposal not found");
        require(p.status == ProposalStatus.Active, "Not active");
        require(block.timestamp <= p.votingEndsAt, "Voting ended");
        require(votes[_proposalId][msg.sender] == Vote.None, "Already voted");

        votes[_proposalId][msg.sender] = _vote;

        if (_vote == Vote.For) {
            p.votesFor++;
        } else {
            p.votesAgainst++;
        }

        emit VoteCast(_proposalId, msg.sender, _vote);
    }

    /**
     * @notice Finalize a proposal after voting ends
     * @dev Anyone can call this after votingEndsAt
     */
    function finalizeProposal(uint256 _proposalId) external {
        Proposal storage p = proposals[_proposalId];
        require(p.id > 0, "Proposal not found");
        require(p.status == ProposalStatus.Active, "Not active");
        require(block.timestamp > p.votingEndsAt, "Voting not ended");

        uint256 totalVotes = p.votesFor + p.votesAgainst;
        uint256 quorumRequired = (p.totalEligible * QUORUM_BPS) / 10000;

        if (totalVotes >= quorumRequired && p.votesFor > p.votesAgainst) {
            p.status = ProposalStatus.Passed;
        } else {
            p.status = ProposalStatus.Rejected;
        }

        emit ProposalFinalized(_proposalId, p.status);
    }

    /**
     * @notice Execute a passed proposal after timelock
     * @dev Only the contract owner (admin) can execute — action is off-chain (IBFT2 CLI vote, parameter change)
     */
    function executeProposal(uint256 _proposalId) external onlyOwner {
        Proposal storage p = proposals[_proposalId];
        require(p.id > 0, "Proposal not found");
        require(p.status == ProposalStatus.Passed, "Not passed");
        require(block.timestamp >= p.executionUnlocksAt, "Timelock active");

        p.status = ProposalStatus.Executed;
        emit ProposalExecuted(_proposalId);
    }

    /**
     * @notice Cancel a proposal (only proposer or admin, only while active)
     */
    function cancelProposal(uint256 _proposalId) external {
        Proposal storage p = proposals[_proposalId];
        require(p.id > 0, "Proposal not found");
        require(p.status == ProposalStatus.Active, "Not active");
        require(msg.sender == p.proposer || msg.sender == owner(), "Not authorized");

        p.status = ProposalStatus.Cancelled;
        emit ProposalCancelled(_proposalId);
    }

    // ============================================================
    //  View Functions
    // ============================================================

    function getProposal(uint256 _proposalId) external view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    function getVote(uint256 _proposalId, address _voter) external view returns (Vote) {
        return votes[_proposalId][_voter];
    }

    // ============================================================
    //  Admin
    // ============================================================

    function setNodeRegistry(address _nodeRegistry) external onlyOwner {
        require(_nodeRegistry != address(0), "Zero address");
        nodeRegistry = _nodeRegistry;
        emit NodeRegistryUpdated(_nodeRegistry);
    }

    // ============================================================
    //  Internal Helpers
    // ============================================================

    function _isValidator(address _addr) internal view returns (bool) {
        (bool success, bytes memory data) = nodeRegistry.staticcall(
            abi.encodeWithSignature("isValidator(address)", _addr)
        );
        return success && abi.decode(data, (bool));
    }

    function _activeValidatorCount() internal view returns (uint256) {
        (bool success, bytes memory data) = nodeRegistry.staticcall(
            abi.encodeWithSignature("activeValidatorCount()")
        );
        require(success, "Registry call failed");
        return abi.decode(data, (uint256));
    }
}
