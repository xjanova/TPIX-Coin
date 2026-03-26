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

    mapping(address => Identity) public identities;
    mapping(address => RecoveryRequest) public recoveries;

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
        require(!recoveries[_wallet].active, "Recovery already pending");

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

        // Mark old identity as migrated (keep for history)
        // The old address still has identity data but new owner controls it

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

    /**
     * @notice Get identity root hash for a wallet.
     */
    function getIdentityRoot(address _wallet) external view returns (bytes32) {
        return identities[_wallet].identityRoot;
    }

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
