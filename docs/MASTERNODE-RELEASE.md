# Masternode calendar and registration-terms release — 2026-10-26

Status: source changes prepared; no mainnet deployment or discovery switch has been performed by this change.

## Behavior and compatibility

- Rewards follow the three 365-day periods from deployment, including all boundaries when there is no keeper transaction. Nothing new accrues after year three. Existing earned rewards remain claimable subject to available pool funds; principal stays withdrawable under the existing lock rules.
- `currentYear()` and `currentRewardPerSecond()` retain their read ABI and reflect chain time. `advanceRewardYear()` is an optional event/checkpoint and catches up directly to the current year.
- Registration now requires `registerNode(uint8,string,uint256 maxLockDays,uint256 maxSlashBps,uint256 deadline)`. The old two-argument selector is intentionally absent. Wallet, PC and web must ship together. No client may fall back to the old selector or refresh accepted limits silently.
- Every new deployment starts with registration paused. Claims and withdrawals are not paused.
- Runtime hash is pinned in `contracts/masternode-release-hash.json`, Wallet and the PC client. Recompile the exact committed Solidity sources with the locked dependencies; `.gitattributes` preserves LF source bytes. Do not replace pins just to make an unknown deployment pass.

## Before any real transaction

1. Finish CI for all three repositories and distribute updated Wallet/PC clients. Deploy the corresponding web UI while registration is paused. Older clients cannot register with the new ABI; keep access to prior contracts for any historical withdrawals/claims.
2. Confirm the owner signer is `0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7`. Use its existing secure signing process; never send a private key in chat, commit it, or put it in command arguments.
3. Rehearse from `contracts`: `npx hardhat run scripts/stage-masternode-release.js`. This uses an ephemeral local chain and never publishes discovery.

## Stage with the owner signer

For guided Windows signing, run the hidden-input wrapper in a dedicated PowerShell window:

```powershell
powershell.exe -NoProfile -File .\scripts\stage-masternode-release.ps1
```

It verifies the build, asks for the private key with `Read-Host -AsSecureString`, rejects a key that does not match the existing owner, and displays the public owner address before the `DEPLOY` prompt. When following guided steps, stop at that prompt and report only the public address. No chain writes occur before `DEPLOY`. It clears the child process's `DEPLOYER_KEY` on completion, cancellation or failure. Use `-Rehearsal` to exercise the wrapper without a real key or external chain transactions.

With `DEPLOYER_KEY` supplied securely in the local process, run from `contracts`:

```powershell
npx hardhat run scripts/stage-masternode-release.js --network tpix
```

This sends real owner transactions. It checks chain 4289, the compiled release hash, both previous registries' ownership and empty history/funds, and the existing KYC contract. It pauses previous registrations, checks emptiness again to catch a registration mined during the first inspection, deploys the new paused registry, and reuses existing KYC. It writes a `masternode-staged-<address>.json` receipt manifest. It does **not** update `deployed-contracts.json`, publish the address to the website, transfer pool money, set an oracle, or open registration.

Previous addresses: current `0x44c497C67B4F756a7769F11c8BEc26439C31F70E`; historical `0x9c3662972921705FeFa9E9bF0d91190d7B514A2B`. Existing KYC: `0x55E918D8D4D3EC9499f26981B49769Af7Fc094a3`.

If history or funds exist, stop automatic cutover and design migration/access for those users. The 2026-10-25 empty snapshot is not a substitute for these checks. If a transaction succeeds and a later step fails, inspect receipts and owner nonce before resuming; do not blindly deploy again. Paused previous contracts still allow eligible claims/exits.

## Open only after readiness verification

1. Verify deployed source on the explorer, exact runtime hash, owner, all four tier settings and APR caps, KYC address, paused state, and zero initial stake/funds. Record deployment timestamp; the three-year clock starts then.
2. Configure and verify actual bootnodes and PC peer connectivity. Confirm heartbeat authorization and the uptime collector. Run the collector in shadow mode for at least 48 hours and inspect false positives before enabling it. Without an oracle the current contract credits active stake at 100% uptime; that does not prove a node is running.
3. Set the reviewed uptime oracle while there are still no operators, if rewards are intended to require running a node. Validate report authentication, offline/online transitions and recovery. Do not treat ANTIX HTTP/IP bans as proof of node uptime or an on-chain account ban.
4. Fund an explicitly approved tranche from the masternode reward allocation using `fundRewardPool()` and the existing funding helper. Pool funding is irreversible; do not use a plain 21,000-gas transfer. Reconcile the receipt and `availableRewardFunds()`; never count user principal as rewards.
5. Update deployment metadata while preserving previous addresses. Publish the exact verified address through the existing registry process, then inspect `/api/v1/masternode/config`, web, Wallet and PC against that same address/hash. Keep `registrationPaused=true` throughout this step.
6. The owner opens registration only after the preceding checks. Confirm the exact signed lock/slash/deadline on a controlled registration and observe reward/uptime behavior. Document the operator, amount and transaction receipt before sending any stake.

## Remaining risks outside this fix

This is not a guarantee of no vulnerabilities. Owner configuration/slashing powers and the uptime oracle remain trusted. Validator concentration, zero-gas transaction flooding/admission limits, ANTIX integration, off-host recovery and independent audit remain separate work. Increasing block size or changing the registry alone does not resolve chain-wide spam.
