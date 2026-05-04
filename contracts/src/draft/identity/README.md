# TPIXIdentity — DRAFT (DO NOT DEPLOY)

**Status:** Quarantined 2026-05-04 — Critical design flaw identified during security audit.

## Why disabled

The original `TPIXIdentity.sol` stored `identityRoot` in `mapping(address => Identity) private identities`.

The `private` keyword **only blocks compiler-level access from other Solidity contracts**. On-chain
storage is **publicly readable** by anyone via `eth_getStorageAt(contract, slot)` — the storage slot
of a mapping value can be derived deterministically:

```
slot = keccak256(abi.encodePacked(uint256(uint160(victim)), uint256(0)))  // mapping slot
identityRootSlot = slot + 0  // first field of Identity struct
```

Because the recovery proof was computed as
`keccak256(identityRoot, newOwner, chainid)`, **any attacker** could:

1. Read `identityRoot` of any victim wallet via `eth_getStorageAt`.
2. Compute a valid proof for `newOwner = attacker`.
3. Submit `requestRecovery(victim, attacker, proof)` — passes validation.
4. Wait 48 hours (timelock).
5. If victim doesn't actively monitor and call `cancelRecovery()`, attacker calls
   `executeRecovery(victim)` — identity is transferred to attacker.

The 24-hour cooldown after cancel does not solve this — attacker can spam every 25 hours forever.

## Required redesign

Any future identity recovery system must NOT rely on hashes of secrets stored on-chain. Options:

- **Commit-reveal:** commit hash on-chain, reveal answers in execute (one-shot).
- **Off-chain guardian signatures:** N-of-M social recovery (Argent-style).
- **ZK proof of knowledge:** SNARK proves user knows the secret without revealing it.
- **Stake-based DoS protection:** require attacker to stake tokens that are slashed if cancelled.

See: https://docs.argent.xyz/argent-vault/social-recovery for production reference.

## Files

- `TPIXIdentity.sol.disabled` — original vulnerable contract, kept for reference only.
- The `.disabled` extension prevents Hardhat from compiling it.
