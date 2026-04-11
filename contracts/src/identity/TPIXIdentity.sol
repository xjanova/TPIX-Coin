// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TPIX Living Identity
 * @notice On-chain identity anchoring for wallet recovery without seed phrase.
 * @dev Stores only hashes — never actual questions, answers, or coordinates.
 *
 * Recovery Flow:
 *   1. User registers identity_root (hash of questions + locations + PIN)
 *   2. User loses device / seed phrase
 *   3. User proves identity off-chain (answers + GPS) → generates proof hash
 *   4. Anyone calls requestRecovery(oldWallet, newWallet, proof)
 *   5. 48-hour time-lock → original owner can cancel
 *   6. After 48h → executeRecovery() marks recovery as approved
 *   7. Wallet app reads approval and transfers control
 *
 * Gas: 0 on TPIX Chain — free to register and recover.
 */
contract TPIXIdentity {

    // ================================================================
    // Structs
    // ================================================================

    struct Identity {
        bytes32 identityRoot;     // hash(questions_hash + locations_hash + pin_hash)
        uint256 registeredAt;
        uint256 updatedAt;
        bool exists;
    }

    struct RecoveryRequest {
        address newOwner;         // new wallet address to transfer to
        bytes32 proof;            // hash of recovery answers + location
        uint256 requestedAt;
        bool active;
        bool executed;
    }

    // ================================================================
    // State
    // ================================================================

    mapping(address => Identity) private identities;
    mapping(address => RecoveryRequest) public recoveries;

    /// @notice Cooldown period after a cancelled recovery before a new one can be requested
    uint256 public constant RECOVERY_COOLDOWN = 24 hours;

    /// @notice Timestamp of last cancelled recovery per wallet
    mapping(address => uint256) public lastRecoveryCancelledAt;

    uint256 public constant TIMELOCK_DURATION = 48 hours;
    uint256 public totalRegistered;

    // ================================================================
    // Events
    // ================================================================

    event IdentityRegistered(address indexed wallet, uint256 timestamp);
    event IdentityUpdated(address indexed wallet, uint256 timestamp);
    event RecoveryRequested(address indexed wallet, address indexed newOwner, uint256 executeAfter);
    event RecoveryCancelled(address indexed wallet);
    event RecoveryExecuted(address indexed wallet, address indexed newOwner);

    // ================================================================
    // Modifiers
    // ================================================================

    modifier onlyRegistered() {
        require(identities[msg.sender].exists, "Identity not registered");
        _;
    }

    // ================================================================
    // Identity Registration
    // ================================================================

    /**
     * @notice Register your identity root hash on-chain.
     * @param _identityRoot Hash of all identity proof data.
     *
     * The wallet app computes this off-chain:
     *   identityRoot = keccak256(abi.encodePacked(
     *     questionsHash,   // hash of all Q&A hashes
     *     locationsHash,   // hash of all location hashes
     *     pinHash          // hash of recovery PIN
     *   ))
     */
    function register(bytes32 _identityRoot) external {
        require(_identityRoot != bytes32(0), "Empty identity root");
        require(!identities[msg.sender].exists, "Already registered, use update()");

        identities[msg.sender] = Identity({
            identityRoot: _identityRoot,
            registeredAt: block.timestamp,
            updatedAt: block.timestamp,
            exists: true
        });

        totalRegistered++;
        emit IdentityRegistered(msg.sender, block.timestamp);
    }

    /**
     * @notice Update your identity root (e.g. after changing questions or locations).
     * @param _identityRoot New identity root hash.
     */
    function update(bytes32 _identityRoot) external onlyRegistered {
        require(_identityRoot != bytes32(0), "Empty identity root");

        identities[msg.sender].identityRoot = _identityRoot;
        identities[msg.sender].updatedAt = block.timestamp;

        emit IdentityUpdated(msg.sender, block.timestamp);
    }

    // ================================================================
    // Recovery
    // ================================================================

    /**
     * @notice Request recovery of a wallet. Starts 48-hour time-lock.
     * @param _wallet The wallet address to recover.
     * @param _newOwner The new wallet address that will receive control.
     * @param _proof Hash proving the caller knows the identity secrets.
     *
     * The wallet app verifies off-chain that the proof matches,
     * then submits this transaction from any address.
     */
    function requestRecovery(
        address _wallet,
        address _newOwner,
        bytes32 _proof
    ) external {
        require(identities[_wallet].exists, "Wallet has no identity");
        require(_newOwner != address(0), "Invalid new owner");
        require(_newOwner != _wallet, "New owner same as old");
        require(!recoveries[_wallet].active, "Recovery already pending");
        require(
            block.timestamp >= lastRecoveryCancelledAt[_wallet] + RECOVERY_COOLDOWN,
            "Recovery cooldown active"
        );
        require(_proof != bytes32(0), "Empty proof");

        // Validate proof: caller must provide keccak256(identityRoot, newOwner, block.chainid)
        // This prevents replay attacks and proves knowledge of the identity root
        // without simply reading the public identityRoot value.
        bytes32 expectedProof = keccak256(abi.encodePacked(
            identities[_wallet].identityRoot,
            _newOwner,
            block.chainid
        ));
        require(
            _proof == expectedProof,
            "Proof does not match identity"
        );

        recoveries[_wallet] = RecoveryRequest({
            newOwner: _newOwner,
            proof: _proof,
            requestedAt: block.timestamp,
            active: true,
            executed: false
        });

        emit RecoveryRequested(
            _wallet,
            _newOwner,
            block.timestamp + TIMELOCK_DURATION
        );
    }

    /**
     * @notice Cancel a pending recovery. Only the original wallet owner can cancel.
     */
    function cancelRecovery() external {
        require(recoveries[msg.sender].active, "No active recovery");

        recoveries[msg.sender].active = false;
        lastRecoveryCancelledAt[msg.sender] = block.timestamp;
        emit RecoveryCancelled(msg.sender);
    }

    /**
     * @notice Execute recovery after time-lock expires.
     * @param _wallet The wallet being recovered.
     */
    function executeRecovery(address _wallet) external {
        RecoveryRequest storage req = recoveries[_wallet];
        require(req.active, "No active recovery");
        require(!req.executed, "Already executed");
        require(
            block.timestamp >= req.requestedAt + TIMELOCK_DURATION,
            "Time-lock not expired"
        );

        req.executed = true;
        req.active = false;

        // Transfer identity to new owner
        Identity storage id = identities[_wallet];
        identities[req.newOwner] = Identity({
            identityRoot: id.identityRoot,
            registeredAt: id.registeredAt,
            updatedAt: block.timestamp,
            exists: true
        });

        // Invalidate old identity to prevent duplication and state fork
        id.exists = false;
        id.identityRoot = bytes32(0);

        emit RecoveryExecuted(_wallet, req.newOwner);
    }

    // ================================================================
    // View Functions
    // ================================================================

    /**
     * @notice Check if a wallet has identity registered.
     */
    function hasIdentity(address _wallet) external view returns (bool) {
        return identities[_wallet].exists;
    }

    // getIdentityRoot() intentionally removed — identityRoot must not be publicly
    // readable to prevent attackers from trivially computing recovery proofs.
    // The wallet app stores identityRoot locally after registration.

    /**
     * @notice Get recovery status for a wallet.
     */
    function getRecoveryStatus(address _wallet) external view returns (
        bool active,
        address newOwner,
        uint256 executeAfter,
        bool executed
    ) {
        RecoveryRequest storage req = recoveries[_wallet];
        return (
            req.active,
            req.newOwner,
            req.requestedAt + TIMELOCK_DURATION,
            req.executed
        );
    }

    /**
     * @notice Check if recovery time-lock has expired.
     */
    function canExecuteRecovery(address _wallet) external view returns (bool) {
        RecoveryRequest storage req = recoveries[_wallet];
        return req.active && !req.executed &&
            block.timestamp >= req.requestedAt + TIMELOCK_DURATION;
    }
}
