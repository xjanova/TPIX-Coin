# Masternode infrastructure readiness — 2026-10-26

The registry and client rollout is complete: registry `0x0611E3747B3D29d5f2a6347a66e93dE066344098`, Wallet 1.13.45, PC 1.14.11 and web 1.1.255. Production discovery points at that registry. Registration remains paused, the pool is unfunded and the oracle is inactive.

## Read-only findings

- Four validators are healthy, share the same head, each has three peers and is not syncing. Chain host has 22 GB free.
- No bootnode container or listener on 30301/8549 exists. Public masternode config returns an empty bootnode list.
- The website has no peer-report token or oracle keystore configuration. Peer reports, registered node records and uptime periods are all empty. An oracle dry run reports zero nodes and 0% feed coverage. The 48-hour readiness period has not begun.
- Validator gRPC currently binds to `0.0.0.0:10000` inside the shared Docker network. Host mappings are loopback-only, but other containers can still access the unauthenticated admin API.

## Change prepared before bootnode deployment

Bind validator gRPC to container loopback and remove the four host gRPC mappings. Healthchecks and administrative commands continue through `docker exec`. Keep JSON-RPC mappings and P2P configuration unchanged. The canonical database memory limit is aligned to the existing production 2 GB value.

The staged compose was parsed by production Docker Compose and compared semantically with the live configuration, including resolved service settings without logging secrets. Only the intended gRPC binds and mappings differ; all Explorer and database settings match.

This merge does not restart validators. Apply with a backup and the maintenance lock, recreating one validator at a time and verifying health and chain progress after each. Follow [the bootnode runbook](../infrastructure/single-host/bootnode/RUNBOOK.md), Phase 0, before opening public P2P. Avoid 18:45–20:00 UTC (backup window).

## Remaining sequence

1. Apply and verify gRPC isolation on all four validators, including a denied connection from a different container.
2. Create a non-validator bootnode with independent keys, sync privately, apply connection/rate/egress firewall rules, then verify public P2P connectivity. Do not copy validator keys or alter genesis.
3. Configure peer reporting and the website's bootnode address; verify an external test node syncing and peer evidence arriving.
4. Validate heartbeat and oracle behavior in shadow mode for at least 48 hours, including online/offline/recovery. No current operators exist, so an empty scheduler run does not count as an end-to-end test.
5. Only after readiness, use the owner's signer for oracle activation, an approved reward-pool tranche and registration opening as described in [the release runbook](MASTERNODE-RELEASE.md).
