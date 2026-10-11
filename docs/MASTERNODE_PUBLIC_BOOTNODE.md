# Public bootnode so community master nodes can sync TPIX Chain

> **สถานะ: ข้อเสนอ (proposal) — ยังไม่ได้ทำอะไรบนเซิร์ฟเวอร์เลย**
> Observed read-only on `tpixserver` (123.253.62.252) on 2026-10-11, 04:42–05:00 UTC.
> Nothing was restarted, written or opened. Every server command in this file is for the owner to run.

## 0. TL;DR

- **The problem is real.** The 4 validators' libp2p port (container `10001`) is not published to the host at all. The TPIX Master Node app's bundled genesis points at `/ip4/123.253.62.252/tcp/10001..10004/...`. Nothing listens there, so every community node fails the bootnode probe and falls back to monitoring mode.
- **Proposal.** Add one non-validator full node, `tpix-bootnode`, on the chain host:
  - libp2p on `0.0.0.0:30301` is published to the internet. It uses the same port inside and outside, and `--nat 123.253.62.252`.
  - JSON-RPC is on host loopback only. gRPC is inside the container only.
  - It joins the existing `tpix_tpix` network and dials the validators by their container names. The names come from the server's existing genesis, so neither the validators nor their genesis change.
  - It runs as a **separate compose project** (`/opt/tpix-bootnode`). The watchdog's `compose up -d`, `apply-rolling.sh`, the backup script and the GitHub workflows never touch it.
- **Two blockers in the desktop app.** I checked both against the live `0xpolygon/polygon-edge:0.9.0` image. Fixing the infrastructure alone is not enough:
  1. `electron/node-manager.js:694-700` passes `--bootnode <addr>` to `server`. polygon-edge 0.9.0 has **no such flag** and exits right away with `Error: unknown flag: --bootnode`. Bootnodes can only come from the `bootnodes` array of the genesis file passed with `--chain`.
  2. `electron/node-manager.js:490` runs `secrets init` without `--insecure`. Every script that worked on 0.9.0 passes `--insecure`, for example `infrastructure/scripts/build-genesis.sh:112`. Treat this as likely broken and check it with the bundled binary.
- **Adding a bootnode does not change the genesis hash.** The app's pinned-hash test keeps passing as long as the new entry is in `/ip4/<IPv4>/tcp/<port>/p2p/16Uiu2…` form.
- **Recommended before going public (separate change, one rolling restart): Phase 0.** Bind the validators' admin gRPC to the container loopback. Today any container on `tpix_tpix` can reach all 4 validators' unauthenticated `ibft propose` gRPC on `:10000`. An internet-facing P2P container on the same network makes that path one exploit closer. See §4.4.

---

## 1. Current state as observed — สถานะจริงบนเครื่อง

### 1.1 Commands run (all read-only)

The commands ran through the BrainX `ssh_run` tool, profile `tpix-chain-new` (user `tpixadmin`):

```bash
hostname; uptime; nproc; free -m; df -h / /opt /var
sudo -n ss -ltnup
sudo -n docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
sudo -n docker network ls
sudo -n docker network inspect tpix_tpix --format '{{.IPAM.Config}} {{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'
sudo -n docker inspect tpix-validator-1 --format 'path={{.Path}} args={{json .Args}} ... project/config_files labels'
sudo -n docker info | grep -iE 'firewall|userland|Server Version|Kernel|Operating'; cat /etc/docker/daemon.json
sudo -n python3 -c '<print bootnodes/chainID/blockTime of /opt/tpix/chain/genesis.json>'   # public data only
cat /opt/tpix/chain/genesis.json.meta; sudo -n sha256sum /opt/tpix/chain/genesis.json
sudo -n grep -n -E '<services|ports|command|mem_limit|networks>' /opt/tpix/docker-compose.yml
ls -la /opt/tpix /opt/tpix/chain
for p in 8545 8546 8547 8548; do curl -s -X POST 127.0.0.1:$p  # eth_blockNumber, net_peerCount, txpool_status, eth_syncing (batch)
for i in 1 2 3 4; do sudo -n docker logs tpix-validator-$i 2>&1 | grep -m2 'LibP2P server running'; done
sudo -n docker exec tpix-validator-1 polygon-edge peers list --grpc-address 127.0.0.1:10000
sudo -n docker exec tpix-validator-1 polygon-edge status --grpc-address 127.0.0.1:10000
sudo -n docker exec tpix-validator-1 polygon-edge server --help                      # flag list of the live image
sudo -n docker exec tpix-validator-1 polygon-edge server --bootnode /ip4/1.2.3.4/tcp/1/p2p/16Uiu2HAmTest --help
sudo -n docker exec tpix-validator-1 polygon-edge server --seal=false --help
sudo -n docker exec tpix-validator-1 polygon-edge secrets init --help
sudo -n docker exec tpix-validator-1 polygon-edge secrets output --help
sudo -n docker exec tpix-validator-1 polygon-edge peers add --help
sudo -n docker stats --no-stream; grep anon/oom_kill in /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.{stat,events}
sudo -n du -sh /opt/tpix/chain/data/validator-* /var/backups/tpix
sudo -n ufw status verbose; sudo -n iptables -S DOCKER-USER; -S INPUT; -S FORWARD; -S DOCKER-FORWARD; -t nat -S DOCKER
ip -br addr; ip route; sysctl net.netfilter.nf_conntrack_max net.netfilter.nf_conntrack_count net.bridge.bridge-nf-call-iptables
modinfo -n xt_connlimit xt_hashlimit
cat /etc/cron.d/tpix-*; sudo -n grep -E '^TPIX_(INFRA_DIR|RPC_URL|NODE_NAME|MAX_RESTART_PER_HOUR)=' /etc/tpix-watchdog.env
grep -n 'VALIDATORS=|compose up|docker restart|grep -c' /usr/local/sbin/tpix-chain-watchdog /usr/local/sbin/tpix-backup-chain
```

- `docker exec … --help` only prints help. Cobra parses flags, then either prints help or prints the flag error. It never starts a server.
- No key file was opened. Peer IDs came from public sources only: the genesis `bootnodes` list, `LibP2P server running` log lines and `peers list`.

### 1.2 Host

| Item | Value |
|---|---|
| Host | `tpixserver`, Ubuntu 24.04.4, kernel 6.8.0-142. A VMware VM (`ens33`). Up 14 days |
| CPU / load | 16 vCPU, load average ~2.6 |
| RAM | 7.9 GB total, **4.5 GB available**, swap 4 GB (122 MB used) |
| Disk (`/` = `/opt` = `/var`) | 77 GB total, 45 GB used, **29 GB free (62 %)** |
| Biggest disk user | `/var/backups/tpix` **19 GB** (16 encrypted tarballs; the newest is 1.42 GB and each one grows ~22 MB/day) |
| Validator data | 1.8 GB each. validator-3 is 3.2 GB, most likely because it still holds the quarantined copy from the 2026-09-26 fork repair |
| Docker | 29.7.1, compose 5.4.0 (from network labels), **Firewall Backend: iptables**, userland proxy on, `live-restore: true`, containerd snapshotter |
| Other services on this host | nginx on 80/443 (ufw allows 80/443 only from Cloudflare ranges, plus 443 from 123.253.62.251). sshd 22 open to anywhere. **GpuxMine.Relay** (user `gpuxmine`) listens on 127.0.0.1:5080, and ufw opens **8443/tcp to anywhere** for it ("GPUxMINE relay (wss + tunnel)"). `CHAIN_HOST` says this host runs the chain only, which is no longer true. |

### 1.3 Chain containers and ports

```
tpix-validator-1  0xpolygon/polygon-edge:0.9.0  healthy  127.0.0.1:8545->8545  127.0.0.1:10000->10000
tpix-validator-2  0xpolygon/polygon-edge:0.9.0  healthy  127.0.0.1:8546->8545  127.0.0.1:10010->10000
tpix-validator-3  0xpolygon/polygon-edge:0.9.0  healthy  127.0.0.1:8547->8545  127.0.0.1:10020->10000
tpix-validator-4  0xpolygon/polygon-edge:0.9.0  healthy  127.0.0.1:8548->8545  127.0.0.1:10030->10000
blockscout-{backend,db,frontend,stats,visualizer,sc-verifier}  (127.0.0.1-only ports 4000, 3100, 8153, 8154)
```

- **libp2p `10001` is not published for any validator.** `ss -ltnup` has no listener on 10001–10004 and no listener on any `0.0.0.0` port except 22, 80, 443 and 8443.
- **Command line** (identical for all 4, from `docker inspect`): `server --data-dir /data --chain /genesis.json --grpc-address 0.0.0.0:10000 --libp2p 0.0.0.0:10001 --jsonrpc 0.0.0.0:8545 --seal --price-limit 0 --max-slots 4096 --max-enqueued 16 --block-gas-target 10000000 --log-level INFO`.
- **Compose:** project `tpix`, file `/opt/tpix/docker-compose.yml`, `restart: always`, `mem_limit: 2g`, `GOGC=50`, `GOMEMLIMIT=1600MiB`, `GOMAXPROCS=4`.
- **Network:** `tpix_tpix`, a bridge on `br-a0398bb83aab` with subnet **172.18.0.0/16**. ICC is on. `br_netfilter` is **not loaded**, so traffic between containers on the same bridge never passes through iptables.
- **Drift between live and repo compose:** live `blockscout-db` has `mem_limit: 2g` (line 130), while `infrastructure/single-host/docker-compose.yml` still says `1g`. Reconcile the repo file before copying it to the server (§5 Phase 0).

### 1.4 Peers and bootnodes in use

| Validator | Container IP | libp2p peer ID (from `LibP2P server running`) |
|---|---|---|
| tpix-validator-1 | 172.18.0.9 | `16Uiu2HAmSmFLK2z9HhZifQ3xaZmbZkZbT3hcEodRvVdX9tNnB8xv` |
| tpix-validator-2 | 172.18.0.10 | `16Uiu2HAmFZFHnseVxL4Qhp4m1SqjEH7Gck9NLE94MzwfWnY47mLk` |
| tpix-validator-3 | 172.18.0.5 | `16Uiu2HAmRgJU3iSmp6vF8Z77yKT2DfCBDCmC69bdwSZvrLVbatb2` |
| tpix-validator-4 | 172.18.0.4 | `16Uiu2HAm8twUKnogszAyfeHi4MY6oRCXfbL63bXd8nowtTR7XVU1` |

- **Server genesis `bootnodes`** (`/opt/tpix/chain/genesis.json`, sha256 `c1966dfc…41b9`, built 2026-08-06):
  `/dns4/tpix-validator-{1..4}/tcp/10001/p2p/<id above>`.
- **App bundled genesis `bootnodes`** (`TPIX-Masternode chain/genesis.json:72-77`):
  `/ip4/123.253.62.252/tcp/{10001,10002,10003,10004}/p2p/<same 4 ids>`.
  These ports are not reachable, so all four entries are dead from the internet.
- **`net_peerCount`** is `0x3` on all 4 validators, so they form a full mesh with only each other. `peers list` on validator-1 shows exactly the other three.
- **Chain health:** head at block **2,752,952** at 04:45 UTC. `eth_syncing=false`, `txpool pending=0, queued=0`. blockTime 2 s.

### 1.5 Load headroom

| Container | CPU | docker-stats mem | real anon mem (cgroup) | OOM kills |
|---|---|---|---|---|
| validator-1..4 | 2.5–5 % | 116–177 MiB / 2 GiB | **87–105 MB** | 0 |
| blockscout-backend | ~15 % | 362 MiB / 2 GiB | — | — |

A non-validator full node costs about the same as one validator:

- ~100 MB anon memory (1 GiB cap proposed),
- 1.8 GB disk now plus ~29 MB/day (a quarter of the 115 MB/day measured for 4 validators on 2026-09-07),
- a few % CPU in steady state, more while serving initial syncs (capped, see §2).

There is room. The real disk pressure is the backups (19 GB), not this node.

### 1.6 Firewall

- `INPUT` policy DROP + ufw (`deny incoming`, `deny routed`).
- `FORWARD` policy DROP, with `-A FORWARD -j DOCKER-USER` evaluated first. **DOCKER-USER is empty.**
- **Ports published by docker bypass ufw entirely.** The DNAT happens in PREROUTING and the forwarded packet never reaches ufw's INPUT rules. Any limit on a published port must go in `DOCKER-USER`.
- No `iptables-persistent`/`netfilter-persistent` is installed, so hand-added DOCKER-USER rules disappear on reboot.
- `nf_conntrack_max` 262144 with 358 in use. `xt_connlimit` and `xt_hashlimit` are available.

### 1.7 Automation that touches containers (the race history)

- **cron `* * * * *`** → `/usr/local/sbin/tpix-chain-watchdog`. `TPIX_INFRA_DIR=/opt/tpix`, `MAX_RESTART_PER_HOUR=3`.
  - It acts only on the hard-coded `VALIDATORS=(tpix-validator-1..4)`.
  - On a stall it runs `docker restart` on those 4. If any of them is missing, it runs **`docker compose -f /opt/tpix/docker-compose.yml up -d`** on the whole project.
  - It skips its run if `flock -n /run/tpix-chain-maint.lock` fails.
- **cron `17 19 * * *` UTC** → `tpix-backup-chain`.
  - It takes `flock -w … /run/tpix-chain-maint.lock` and stops `tpix-validator-4` for ~60–80 s.
  - It counts validators with `docker ps | grep -c '^tpix-validator-'`.
- **`apply-rolling.sh` does not take the maintenance lock itself.** The README shows wrapping manual work in `sudo flock /run/tpix-chain-maint.lock bash`, and this proposal does the same for Phase 0.

---

## 2. Design — ออกแบบ

```
                 internet (community master nodes, any port 30303 behind NAT)
                                   │ TCP 30301 only
                    ┌──────────────▼─────────────── DOCKER-USER (per-IP caps, rate, egress block)
 123.253.62.252     │  tpix-bootnode  (NO validator key in the set, --seal=false)
                    │   libp2p 0.0.0.0:30301  --nat 123.253.62.252   (published 0.0.0.0:30301)
                    │   jsonrpc 0.0.0.0:8545  → host 127.0.0.1:8549 only
                    │   grpc    127.0.0.1:10000 (inside container only)
                    └──────────────┬──────────────── docker network tpix_tpix (172.18.0.0/16)
                                   │ dials /dns4/tpix-validator-N/tcp/10001 (from the existing genesis)
            ┌───────────┬──────────┴─┬────────────┐
       validator-1  validator-2  validator-3  validator-4   (unchanged; 10001 stays unpublished)
```

### 2.1 Decisions and why

1. **Separate compose project `tpix-bootnode` in `/opt/tpix-bootnode`, on the external network `tpix_tpix`.**
   - The watchdog's `compose up -d` and every GitHub workflow work on project `tpix` in `/opt/tpix`. They can never recreate, restart or "heal" the bootnode, and they can never undo a deliberate `docker stop tpix-bootnode` (the kill switch).
   - `apply-rolling.sh` loops over its own explicit `VALIDATORS` list.
   - The container name `tpix-bootnode` does not match `^tpix-validator-` (backup count) or `name=tpix-validator-1` (watchdog).
   - **Never add the bootnode to `/opt/tpix/docker-compose.yml` or to any `VALIDATORS` array.**
2. **No change to the validators or to `/opt/tpix/chain/genesis.json`.**
   - The bootnode mounts the same genesis read-only. Its `/dns4/tpix-validator-N/tcp/10001` entries resolve through Docker DNS on `tpix_tpix`, so the bootnode dials the validators.
   - From the validators' side it is just one more inbound peer: 3 → 4 peers out of their default 32 inbound slots.
3. **Same port inside and outside (30301:30301).** With `--nat`, polygon-edge 0.9 advertises `/ip4/<nat>/tcp/<listen port>`. Mapping host 30301 to container 10001 would make it advertise `…/tcp/10001`, and peers that learn the address through discovery would dial the wrong port. Matching ports also lets DOCKER-USER rules match `--dport 30301` after DNAT.
4. **`--nat 123.253.62.252`, not `--dns`.**
   - Cloudflare cannot proxy raw libp2p TCP. Only Spectrum (paid) can, so a DNS name would have to be grey-cloud anyway.
   - The app test `genesis-guard.test.js:71-80` accepts only `/ip4/` bootnodes.
   - The origin IP is already public: it appears in the app's bundled genesis, in `CHAIN_HOST` and in the public TPIX-Coin repo. Publishing P2P on it reveals nothing new, but it does add a new internet-facing service on this IP (§4).
5. **`--seal=false`.** polygon-edge 0.9.0's `server --help` reports `--seal … (default true)`. The bootnode's freshly generated key is not in the validator set, so it could never seal anyway. Setting the flag explicitly records the intent. The live image accepts the flag (checked).
6. **No validator key from anywhere else.** The bootnode generates its own new keys (ECDSA, BLS and libp2p). The ECDSA/BLS pair is never added to the validator set and is worthless. **Never copy `consensus/` or `libp2p/` from a validator data dir or a backup.** A copied libp2p key gives two nodes the same peer ID. A copied validator key means double signing.
7. **JSON-RPC is published on host loopback `127.0.0.1:8549` only**, for monitoring with the same `curl` checks used on 8545–8548. gRPC stays inside the container, and the healthcheck uses `docker exec`. **Do not point Blockscout `ETHEREUM_JSONRPC_TRACE_URL` at this node.** The trace format bug in 0.9.0 (compose comment 2026-10-11) would put the endless retry loop on the bootnode. Keep this node single-purpose.
8. **Peer limits:**
   - `--max-inbound-peers 48 --max-outbound-peers 8`. These two flags and `--max-peers` are mutually exclusive in 0.9, so `--max-peers` is not used.
   - The bootnode dials the 4 validators with **outbound** slots, which internet peers cannot use up. The egress rule in §3.3 stops the bootnode from spending outbound slots on community nodes.
9. **Do not use `--no-discover`.** According to the 0.9 network-server source, the genesis `bootnodes` are parsed and dialed only when discovery is on, so the bootnode would never dial the validators. Discovery is also what lets the bootnode reconnect after the watchdog restarts all validators: the 60-second bootnode-discovery tick plus peer exchange brings the connections back within ~1–2 minutes.
10. **Resource caps:** `cpus: 1.5`, `GOMAXPROCS=2`, `mem_limit: 1g`, `GOMEMLIMIT=768MiB`, `GOGC=50`, `pids_limit: 256`, `nofile 8192`, `cap_drop: ALL`, `no-new-privileges`.
    - The CPU cap matters most. It bounds how fast the bootnode imports blocks during its own initial sync, which in turn bounds the load it puts on the validator serving it. It also bounds how fast it can relay gossip to the validators (§4).
    - The validators are untouched: 4 × `GOMAXPROCS=4` = 16 cores by design.
11. **Two-stage exposure.** Stage 1 publishes P2P on `127.0.0.1:30301` while the bootnode syncs 2.75 M blocks from the validators. Stage 2 switches to `0.0.0.0:30301`. Community nodes therefore never see a half-synced bootnode, and the first-sync load happens on a quiet, watched window.

### 2.2 Flags confirmed in the live image (`polygon-edge server --help`, 0.9.0)

These are supported: `--chain`, `--data-dir`, `--libp2p` (default `127.0.0.1:1478`), `--nat`, `--dns`, `--no-discover`, `--max-peers` (40), `--max-inbound-peers` (32), `--max-outbound-peers` (8), `--grpc-address`, `--jsonrpc`, `--price-limit`, `--max-slots`, `--max-enqueued`, `--block-gas-target`, `--seal` (default **true**), `--log-level`, `--config`, `--secrets-config`, `--json-rpc-batch-request-limit` (20) and `--json-rpc-block-range-limit` (1000).

**There is no `--bootnode` flag.** `server --bootnode …` returns `Error: unknown flag: --bootnode`. In 0.9.0 there are only two ways to give a node its bootnodes:

1. The `bootnodes` array of the genesis file passed with `--chain`. This is persistent and is the only real option.
2. `polygon-edge peers add --addr <multiaddr> --grpc-address <node gRPC>` at runtime. This is one-shot and lost on restart. Use it for manual tests only.

The `--config` file mirrors the CLI flags and has no bootnode field either (from the 0.9 source). I could not confirm this on prod, because `server export` writes a file.

---

## 3. Concrete artifacts

> The repo convention is "canonical file in the repo, copy to the server". Once this proposal is approved, commit the two files below as `infrastructure/single-host/bootnode/docker-compose.yml` and `infrastructure/single-host/bootnode/tpix-p2p-firewall`. This commit only adds the proposal.

### 3.1 `/opt/tpix-bootnode/docker-compose.yml`

```yaml
# TPIX Chain — public bootnode / sentry (NON-validator). Separate compose project ON PURPOSE:
# the watchdog's `docker compose up -d` (project tpix, /opt/tpix) must never touch this
# container, so `docker stop tpix-bootnode` stays a reliable kill switch.
# DO NOT add this service to /opt/tpix/docker-compose.yml or to any VALIDATORS list.
# DO NOT copy consensus/ or libp2p/ from any validator into ./data — its keys are its own.
name: tpix-bootnode

services:
  tpix-bootnode:
    image: 0xpolygon/polygon-edge:0.9.0
    container_name: tpix-bootnode
    restart: unless-stopped          # a manual stop (kill switch) survives reboots/daemon restarts
    stop_grace_period: 30s
    command: >
      server --data-dir /data --chain /genesis.json
      --libp2p 0.0.0.0:30301 --nat 123.253.62.252
      --grpc-address 127.0.0.1:10000 --jsonrpc 0.0.0.0:8545
      --seal=false --price-limit 0 --max-slots 4096 --max-enqueued 16
      --max-inbound-peers 48 --max-outbound-peers 8
      --log-level INFO
    ports:
      # STAGE 1 (initial sync, not public):  "127.0.0.1:30301:30301/tcp"
      # STAGE 2 (public):                    "0.0.0.0:30301:30301/tcp"
      - "127.0.0.1:30301:30301/tcp"
      - "127.0.0.1:8549:8545/tcp"    # JSON-RPC: host loopback only, for monitoring
    volumes:
      - /opt/tpix-bootnode/data:/data
      - /opt/tpix/chain/genesis.json:/genesis.json:ro   # same file as validators (its /dns4 bootnodes = validators)
    environment:
      GOGC: "50"
      GOMEMLIMIT: "768MiB"
      GOMAXPROCS: "2"
    cpus: 1.5
    mem_limit: 1g
    pids_limit: 256
    ulimits:
      nofile: { soft: 8192, hard: 8192 }
    cap_drop: [ALL]                  # if it ever fails with EPERM on /data, remove this line first
    security_opt: ["no-new-privileges:true"]
    healthcheck:
      test: ["CMD-SHELL", "polygon-edge status --grpc-address 127.0.0.1:10000 > /dev/null 2>&1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: json-file
      options: { max-size: "20m", max-file: "3" }
    networks: [tpix]

networks:
  tpix:
    name: tpix_tpix
    external: true
```

### 3.2 Bootnode keys and peer ID (owner runs this)

```bash
sudo install -d -m 700 /opt/tpix-bootnode /opt/tpix-bootnode/data
# fresh keys, NOT in the validator set. --insecure = store on local FS (same as build-genesis.sh)
sudo docker run --rm -v /opt/tpix-bootnode/data:/data 0xpolygon/polygon-edge:0.9.0 \
  secrets init --data-dir /data --insecure
# prints ONLY the public libp2p node ID (16Uiu2HAm…)
sudo docker run --rm -v /opt/tpix-bootnode/data:/data 0xpolygon/polygon-edge:0.9.0 \
  secrets output --data-dir /data --node-id
```

- **Bootnode multiaddr:** `/ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>`.
- **To confirm it after start:** `sudo docker exec tpix-bootnode polygon-edge status --grpc-address 127.0.0.1:10000`. Because of `--nat`, the `Libp2p Address` line must show exactly that multiaddr.
- **Do not use a `/dns4/` form** unless the app test is relaxed first and the DNS record is DNS-only (grey cloud).

### 3.3 Firewall — DOCKER-USER rules managed by one script and one systemd unit

Docker-published ports ignore ufw, so `ufw allow 30301/tcp` would only be decoration. Do not use it as the control. The rules below go into `DOCKER-USER`, the chain that Docker reserves for user rules and never flushes. A oneshot unit applies them at boot because the host has no `iptables-persistent`.

`/usr/local/sbin/tpix-p2p-firewall` (mode 0755, root):

```bash
#!/bin/bash
# DOCKER-USER rules for the TPIX public bootnode. usage: tpix-p2p-firewall apply|remove|status
# Every rule carries a "tpix-p2p-*" comment; remove deletes by comment (no state needed).
set -euo pipefail
WAN_IF="${WAN_IF:-ens33}"
P2P_PORT="${P2P_PORT:-30301}"
NET_NAME="${NET_NAME:-tpix_tpix}"
CH=DOCKER-USER

subnet_of_net() {   # chain network subnet (172.18.0.0/16 today); wait for dockerd at boot
  local s i
  for i in $(seq 1 30); do
    s="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$NET_NAME" 2>/dev/null || true)"
    [[ "$s" =~ ^[0-9.]+/[0-9]+$ ]] && { echo "$s"; return 0; }
    sleep 2
  done
  echo "tpix-p2p-firewall: network $NET_NAME not found — rules NOT applied" >&2; return 1
}

specs() {
  local sn="$1"
  # 1) global cap: concurrent inbound P2P connections from all sources
  echo "-i $WAN_IF -p tcp --dport $P2P_PORT --syn -m connlimit --connlimit-above 256 --connlimit-mask 0 -m comment --comment tpix-p2p-global -j REJECT --reject-with tcp-reset"
  # 2) per-IP concurrent cap — 8, not 2-3: Thai home/mobile ISPs use CGNAT (many users, one IP)
  echo "-i $WAN_IF -p tcp --dport $P2P_PORT --syn -m connlimit --connlimit-above 8 --connlimit-mask 32 -m comment --comment tpix-p2p-perip -j REJECT --reject-with tcp-reset"
  # 3) per-IP new-connection rate (edge re-dials bootnodes every ~60s; this leaves lots of slack)
  echo "-i $WAN_IF -p tcp --dport $P2P_PORT --syn -m hashlimit --hashlimit-name tpix_p2p --hashlimit-mode srcip --hashlimit-above 20/minute --hashlimit-burst 40 -m comment --comment tpix-p2p-rate -j DROP"
  # 4) chain-network containers may not open NEW TCP to the internet except DNS/HTTP(S):
  #    - validators never dial community nodes directly (bootnode stays the only choke point)
  #    - bootnode outbound slots stay free for validators (RST = dial fails instantly)
  #    blockscout only needs 443/80 (compiler downloads etc.) — allowed
  echo "-s $sn ! -d $sn -o $WAN_IF -p tcp --syn -m multiport ! --dports 53,80,443 -m comment --comment tpix-p2p-noegress -j REJECT --reject-with tcp-reset"
}

case "${1:-status}" in
  apply)
    sn="$(subnet_of_net)"
    while IFS= read -r r; do
      # shellcheck disable=SC2086
      iptables -C $CH $r 2>/dev/null || iptables -I $CH 1 $r
    done < <(specs "$sn")
    iptables -L $CH -v -n --line-numbers ;;
  remove)
    { iptables -S $CH | grep -- '--comment tpix-p2p-' || true; } | sed 's/^-A /-D /' | while read -r r; do
      # shellcheck disable=SC2086
      iptables $r
    done
    iptables -L $CH -v -n --line-numbers ;;
  status)
    iptables -L $CH -v -n --line-numbers ;;
  *) echo "usage: $0 apply|remove|status" >&2; exit 2 ;;
esac
```

`/etc/systemd/system/tpix-p2p-firewall.service`:

```ini
[Unit]
Description=TPIX public bootnode firewall rules (DOCKER-USER)
Wants=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/tpix-p2p-firewall apply
ExecStop=/usr/local/sbin/tpix-p2p-firewall remove

[Install]
WantedBy=multi-user.target
```

There is deliberately no `PartOf=docker.service`. Stopping dockerd with `live-restore` keeps the containers running, and the rules must stay in place while it is stopped.

**Known gap:** on boot, dockerd may start `tpix-bootnode` a few seconds before this unit applies the rules. For those seconds 30301 is open without the per-IP limits, which I judge acceptable.

**Not possible with iptables here:** `br_netfilter` is not loaded, so container-to-container traffic on `tpix_tpix` never reaches DOCKER-USER. iptables cannot stop the bootnode container from reaching the validators' `:8545`/`:10000`. Loading `br_netfilter` would change filtering for every bridge on the host, so it is not proposed. Phase 0 (§4.4) closes the gRPC part at the source instead.

### 3.4 Genesis `bootnodes`: does editing them change the genesis hash?

**No.** polygon-edge builds block 0 from the `genesis` object: header fields plus `alloc`, which yields the stateRoot. The top-level `bootnodes` array is node configuration and is never hashed. Evidence:

- The live validators run with `/dns4/…` bootnodes. The app's bundled genesis has `/ip4/…` bootnodes, so the file hashes differ.
- Yet the app pins both to the same chain:
  - `computeGenesisHash()` reads only `genesis` and equals `LIVE_GENESIS_HASH 0x0d35…2488` (`test/genesis-guard.test.js:54-59`).
  - `checkLiveGenesis()` compares the bundled file with the live chain's block 0 at runtime.
  - `chainIdentity()` excludes `bootnodes` by design (`electron/genesis-guard.js:80-90`, `test/genesis-guard.test.js:83-87`).

Consequences:

- **Server:** nothing to edit. The bootnode reuses `/opt/tpix/chain/genesis.json` unchanged.
- **App:** replacing the bundled bootnode list keeps every hash/identity test green. The only constraint is `test/genesis-guard.test.js:71-80`: every entry must match `^/ip4/<IPv4>/tcp/<port>/p2p/16Uiu2…$` and the IDs must be unique. polygon-edge libp2p keys are secp256k1, so the ID starts with `16Uiu2HAm`.
- **Existing installs:** `prepareGenesis()` sees "same chain, different file" and returns `refreshed`. It replaces the data-dir genesis and leaves chain data alone.
- **The CLI-flag alternative does not exist in 0.9.0** (§2.2).

### 3.5 Desktop app changes (TPIX-Masternode — for the agent that owns that repo)

| File:line | Change |
|---|---|
| `chain/genesis.json:72-77` | Replace the 4 dead `/ip4/123.253.62.252/tcp/1000{1..4}/…` entries with `"/ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>"`. Drop the validator entries: they are unreachable by design, they slow the probe, and they waste polygon-edge's random-bootnode re-dial. Add a second entry later if a VPS bootnode is added (§4.6). polygon-edge 0.9 needs ≥ 1 bootnode. |
| `electron/node-manager.js:694-700` (`buildArgs`) | **Blocker.** Remove the `--bootnode` args; 0.9.0 exits on them (verified). For user overrides (`config.bootnodes`, read at `:296`), write a derived genesis to a separate file, e.g. `<dataDir>/genesis.run.json` = bundled + overridden `bootnodes`, and pass that to `--chain`. Do not overwrite `<dataDir>/genesis.json`: `prepareGenesis()` refreshes it from the bundled file on every start. |
| `test/node-args.test.js:60-67` | Asserts `--bootnode` is passed; this pins the bug and must change. |
| `electron/node-manager.js:490` | `secrets init --data-dir …` has no `--insecure`. Every script that worked on 0.9.0 passes it (`build-genesis.sh:112`); `path3-regenesis.sh:93`, which failed, did not. Verify with the bundled binary (`polygon-edge secrets init --data-dir %TEMP%\x`). If it errors, add `--insecure`, or skip the step, since `server` generates missing keys on first start. |
| `electron/node-manager.js:474-476` | The user-facing hint tells people to ask the admin to open 10001–10004 and use `--nat`. Update it to say the public bootnode is `…:30301` and to check internet/firewall to 123.253.62.252:30301. |
| `electron/node-manager.js:687-691` | Non-validator tiers omit `--seal`, but 0.9.0 defaults `--seal` to **true**. Harmless (their key is not in the set), but pass `--seal=false` explicitly for non-validator tiers. |
| Packaging | `bin/` is not tracked and `.github/workflows/release.yml` fetches no binary, so most installs have no `polygon-edge` and run monitoring-only regardless. Upstream 0.9.0 release archives are Linux/macOS; confirm a Windows build exists before promising full-node mode on Windows. |

---

## 4. Abuse, DoS and the backup/watchdog interplay

### 4.1 What becomes internet-facing

One TCP port (30301) speaks polygon-edge 0.9.0's libp2p stack. **polygon-edge is archived upstream, so no security fixes will come.** Everything below follows from "an anonymous peer is now one hop from the validators' gossip mesh".

| Risk | Mechanism | Mitigation in this design | Residual |
|---|---|---|---|
| **Connection or handshake flood** | Many TCP connections or libp2p handshakes, which cost CPU on the bootnode | DOCKER-USER rules: global cap 256, per-IP cap 8, per-IP SYN rate 20/min (burst 40); `--max-inbound-peers 48`; `cpus 1.5`, `mem 1g`, `pids 256`; kernel SYN cookies | A volumetric DDoS on 123.253.62.252 also hits nginx/validators on the same NIC; P2P cannot go behind Cloudflare. See §4.6 |
| **Gossip relay into validators — bypasses the njs RPC flood gate** | libp2p gossipsub forwards `txpool` and `ibft` topic messages to mesh peers; polygon-edge 0.9 registers no topic validators. The non-sealing bootnode ignores gossiped txs for its own pool but still relays them | `cpus 1.5` on the bootnode bounds relay throughput. Watchdog already alerts on mempool > 1000 and full blocks. Kill switch (§4.5). Validator `--max-slots 4096 --max-enqueued 16` | **Accepted risk.** Any full node that peers into the mesh can inject zero-gas txs or junk IBFT messages (each costs validators an ecrecover); per-IP RPC limits in `infrastructure/njs/` do not apply to P2P. This is inherent to letting community nodes join at all. |
| **Validators dialing out to community nodes** | Discovery teaches validators about community peers; public-IP ones would be dialed directly, skipping the bootnode choke point | Rule 4 (`tpix-p2p-noegress`): no NEW TCP from 172.18.0.0/16 to the internet except 53/80/443 | A malicious node listening on 80/443 could still be dialed. Closing that needs validator-specific egress (Phase 2) |
| **Bandwidth from serving initial syncs** | Each brand-new community node pulls the whole chain from the bootnode. Estimate: 2.75 M blocks × ~0.7 KB ≈ **~2 GB per new node** | CPU cap throttles serving; measure with `docker stats` NET I/O | The owner should check the VM's egress allowance. The VPS option moves this off the host |
| **Compromise of the bootnode process (RCE)** | Root in the bootnode container on `tpix_tpix` can reach validators' JSON-RPC `:8545` and **admin gRPC `:10000`** (`ibft propose` with 3 of 4 votes = validator-set takeover) | `cap_drop ALL`, `no-new-privileges`, no keys of value inside. **Phase 0** binds validator gRPC to the container loopback (§4.4) | `:8545` stays reachable from the container (same as blockscout today): debug_trace DoS. Phase 2 can move bootnode↔validator traffic onto a dedicated network |
| **Disk** | The bootnode is a full chain copy | +1.8 GB now, ~+29 MB/day; 29 GB free | Backups (19 GB, growing) remain the real disk risk (`TPIX_BACKUP_UPLOAD`/R2 still pending) |

### 4.2 Why this does not reintroduce the 2026-09-03 backup/watchdog race

- **The bootnode never touches validator data or containers.** It has its own data dir (`/opt/tpix-bootnode/data`), and its compose project, `restart` policy and healthcheck are its own.
- **The watchdog's whole-project `compose up -d`** targets project `tpix` only. It cannot recreate the bootnode, and the bootnode is not in `VALIDATORS`.
- **The backup** stops only `tpix-validator-4` and counts `^tpix-validator-` containers, which never matches `tpix-bootnode`. While validator-4 is stopped, the bootnode simply has 3 validator peers, then reconnects.
- **Phase 1 steps never run `docker compose` in `/opt/tpix`.** They only touch `/opt/tpix-bootnode` and DOCKER-USER, so they need no maintenance lock. **Phase 0 does touch validators and must run under `flock /run/tpix-chain-maint.lock`** (`apply-rolling.sh` does not take it itself). Otherwise, while a validator is being recreated, the watchdog can see it missing and `compose up -d` the other three at once.
- **Caveat — `docker compose down` in `/opt/tpix`.** It will now fail to remove network `tpix_tpix` ("active endpoints") because the bootnode is attached. Stop the bootnode first. If `tpix_tpix` is ever recreated, run `docker compose up -d --force-recreate` in `/opt/tpix-bootnode` and `systemctl restart tpix-p2p-firewall`, which re-reads the subnet.
- **Optional later (Phase 2).** Add an alert-only bootnode check to the watchdog: peer count on 8549 and lag vs 8545.
  - Inside the existing `flock` main path.
  - It must never call `restart_chain`, never `docker compose` the bootnode, and never use the restart quota.
  - Docker's `restart: unless-stopped` already handles crashes.

### 4.3 Max-peers interplay

| Node | Peers |
|---|---|
| Validators (defaults) | 40 total = 32 inbound + 8 outbound; today 3 used |
| Bootnode | 4 outbound (validators) + up to 48 inbound (community) |

Community nodes behind NAT advertise private addresses (the app sets no `--nat`). Other peers that learn them try to dial them and fail; that noise is harmless.

### 4.4 Phase 0 (recommended before going public): validators' gRPC to container loopback

- **Today:** `--grpc-address 0.0.0.0:10000` inside each validator, plus host mappings `127.0.0.1:10000/10010/10020/10030`. Nothing on the host uses those mappings: a repo grep finds only the in-container healthcheck, which uses `127.0.0.1:10000`. The open bind makes the unauthenticated admin gRPC reachable from **every container on `tpix_tpix`**, including the internet-facing explorer stack and, after this change, the bootnode.
- **Change in `x-cmd`:** `--grpc-address 127.0.0.1:10000`, and remove the four `"127.0.0.1:10…0:10000"` port entries. The healthcheck keeps working (it is in-container loopback). Admin access stays available through `docker exec tpix-validator-N polygon-edge … --grpc-address 127.0.0.1:10000`.
- **Rollout:** one rolling recreate, under the maintenance lock (§5 Phase 0). This is a validator change, so it is optional for the bootnode to work. It closes the worst consequence of a bootnode compromise.

### 4.5 Kill switch and rollback (ถอยกลับ)

| Level | Command | Effect |
|---|---|---|
| **Kill switch** (seconds, validators unaffected) | `sudo docker stop tpix-bootnode` | All community peers drop; apps fall back to monitoring mode. `unless-stopped` keeps it stopped across reboots. Restore: `sudo docker start tpix-bootnode` |
| Un-publish | Set ports back to `127.0.0.1:30301:30301/tcp`, then `cd /opt/tpix-bootnode && sudo docker compose up -d` | Recreates only the bootnode |
| Remove firewall rules | `sudo systemctl disable --now tpix-p2p-firewall` | ExecStop deletes every `tpix-p2p-*` rule |
| Remove container | `cd /opt/tpix-bootnode && sudo docker compose down` | External network `tpix_tpix` is not removed. Validators see 4 → 3 peers |
| Remove data | `sudo rm -rf /opt/tpix-bootnode` | Destructive. Holds only a throwaway key and a chain copy; owner confirms before running |
| App | Ship an app update with the previous bootnode list, or leave it | With the bootnode gone, the app's probe fails and it shows monitoring mode, as it does today |
| Phase 0 rollback | Restore `/opt/tpix/docker-compose.yml.bak-<ts>`, then `sudo flock -w 900 /run/tpix-chain-maint.lock bash infrastructure/single-host/apply-rolling.sh` | — |

`/opt/tpix` (validators, genesis, Blockscout) is untouched by Phase 1, so nothing there needs rolling back.

### 4.6 Cheaper or stronger alternative: public bootnode on a separate VPS (two-tier sentry)

1. Run the same `tpix-bootnode` on the chain host, but replace rules 1–3 with one allow-list rule:
   ```
   iptables -I DOCKER-USER -i ens33 -p tcp --dport 30301 ! -s <VPS_IP> -j DROP
   ```
2. On a cheap VPS (~€4/month), run a public non-validator node:
   - Use `infrastructure/oracle/bootstrap-node.sh --rpc-only` + `docker-compose.node.yml`, with `SEAL="--seal=false"`. The template's empty `SEAL` still seals by default in 0.9.0.
   - `--nat <VPS_IP>`.
   - Its genesis `bootnodes` = the on-host sentry multiaddr.
   - Port 10001 open to the world. `bootstrap-node.sh` restricts it to `--peers` IPs, so that must be changed for a public node.
   - Align `--max-enqueued 16 --block-gas-target 10000000` with prod; the template has 1024 / 20M.
3. Put the VPS multiaddr in the app bundle, optionally together with the on-host one.

**Pros:**
- Internet-facing DDoS and sync bandwidth land on the VPS.
- The chain host accepts P2P from one IP only.
- A dead VPS costs nothing.

**Cons:**
- A second machine to run.
- Two hops of gossip latency, which is irrelevant for syncing.
- Provider policy: memory note 2026-09-07 says Oracle's AUP bans crypto mining with no PoA carve-out (grey zone); GCP explicitly supports blockchain nodes.

**Recommendation:** start with Phase 1 on-host, because the host has headroom and the IP is already public. Move to the VPS form if any of these happen:
- sustained abuse,
- a sync-bandwidth bill,
- more than ~40 community nodes.

---

## 5. Owner runbook — ทำตามลำดับ (copy-paste)

> Run as `tpixadmin` with sudo on 123.253.62.252. Avoid **18:45–20:00 UTC**, the backup window (cron 19:17 UTC = 02:17 Thai time).
> Phase 1 never runs `docker compose` in `/opt/tpix`.

### Phase 0 — optional but recommended before Step 6 (touches validators)

```bash
# 0a. make the repo compose match live first (live blockscout-db mem_limit is 2g, repo says 1g)
sudo diff <(sed 's/\r$//' ~/TPIX-Coin/infrastructure/single-host/docker-compose.yml) /opt/tpix/docker-compose.yml
#     → only intended lines may differ. Commit the 2g fix in the repo before continuing.
# 0b. in the repo x-cmd: --grpc-address 127.0.0.1:10000 ; drop the four "127.0.0.1:10…0:10000" ports; commit; then:
cd ~/TPIX-Coin && git pull
sudo cp /opt/tpix/docker-compose.yml /opt/tpix/docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)
sudo cp infrastructure/single-host/docker-compose.yml /opt/tpix/docker-compose.yml
sudo flock -w 900 /run/tpix-chain-maint.lock bash infrastructure/single-host/apply-rolling.sh
```

**Verify:**

```bash
ss -ltn | grep -E ':100[0-3]0\b' || echo "host gRPC mappings gone"
for i in 1 2 3 4; do sudo docker exec tpix-validator-$i polygon-edge status --grpc-address 127.0.0.1:10000 | grep 'Block Number'; done
sudo docker ps --format '{{.Names}} {{.Status}}' | grep validator    # all (healthy)
```

### Step 1 — Pre-flight (read-only)

```bash
date -u                                                    # not within 18:45–20:00 UTC
for p in 8545 8546 8547 8548; do curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"net_peerCount","params":[]}' http://127.0.0.1:$p; echo; done   # 0x3 each
ss -ltn | grep -E ':(30301|8549)\b' || echo "30301/8549 free"
sudo docker network inspect tpix_tpix -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'   # 172.18.0.0/16
df -h /opt                                                  # ≥ 5 GB free
```

### Step 2 — Keys and peer ID

```bash
sudo install -d -m 700 /opt/tpix-bootnode /opt/tpix-bootnode/data
sudo docker run --rm -v /opt/tpix-bootnode/data:/data 0xpolygon/polygon-edge:0.9.0 secrets init --data-dir /data --insecure
sudo docker run --rm -v /opt/tpix-bootnode/data:/data 0xpolygon/polygon-edge:0.9.0 secrets output --data-dir /data --node-id
```

**Verify:**
- The output is a single `16Uiu2HAm…` ID. Write down `/ip4/123.253.62.252/tcp/30301/p2p/<that ID>`.
- `sudo ls /opt/tpix-bootnode/data` shows `consensus libp2p`, and nothing was copied from a validator.

### Step 3 — Compose, stage 1 (P2P on loopback only)

```bash
sudoedit /opt/tpix-bootnode/docker-compose.yml        # paste §3.1 as-is (ports = 127.0.0.1:30301)
cd /opt/tpix-bootnode && sudo docker compose config -q && echo "compose OK"
```

**Verify:** `compose OK`, and `sudo docker compose config | grep -E 'published|host_ip'` shows `127.0.0.1` for both ports.

### Step 4 — Start and let it sync from the validators (watch the chain while it does)

```bash
cd /opt/tpix-bootnode && sudo docker compose up -d
sudo docker logs --tail 20 tpix-bootnode | grep -E 'LibP2P server running|error' 
```

**Verify every few minutes until the lag is ≤ 2 blocks:**

```bash
bn() { curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:$1 | grep -o '0x[0-9a-f]*'; }
echo "validator=$((16#$(bn 8545 | cut -c3-))) bootnode=$((16#$(bn 8549 | cut -c3-)))"
sudo docker exec tpix-validator-1 polygon-edge peers list --grpc-address 127.0.0.1:10000 | grep 'Number of peers'   # 4 (3 + bootnode)
sudo docker stats --no-stream tpix-bootnode tpix-validator-1 tpix-validator-2 tpix-validator-3 tpix-validator-4
tail -5 /var/log/tpix-watchdog.log                       # no "RESTARTING chain"
```

- **If the validators' block time degrades, or the watchdog logs a stall:** run `sudo docker stop tpix-bootnode` and retry later, with `cpus: 1.0`.
- The `peers list` command works the same with or without Phase 0, because it runs inside the container against its loopback gRPC.

### Step 5 — Firewall rules (before going public)

```bash
sudoedit /usr/local/sbin/tpix-p2p-firewall && sudo chmod 755 /usr/local/sbin/tpix-p2p-firewall   # §3.3
sudoedit /etc/systemd/system/tpix-p2p-firewall.service                                         # §3.3
sudo systemctl daemon-reload && sudo systemctl enable --now tpix-p2p-firewall
```

**Verify:**

```bash
sudo /usr/local/sbin/tpix-p2p-firewall status | grep -c 'tpix-p2p-'          # 4
sudo docker exec tpix-bootnode sh -c 'wget -q -O /dev/null -T 8 https://binaries.soliditylang.org/linux-amd64/list.json && echo "https egress OK"'
sudo docker exec tpix-bootnode sh -c 'nc -z -w 3 1.1.1.1 853 && echo "LEAK: egress open" || echo "non-web egress blocked"'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/api/v2/stats    # explorer backend still 200
```

### Step 6 — Go public (stage 2)

```bash
sudo sed -i 's|- "127.0.0.1:30301:30301/tcp"|- "0.0.0.0:30301:30301/tcp"|' /opt/tpix-bootnode/docker-compose.yml
grep -n '30301:30301' /opt/tpix-bootnode/docker-compose.yml     # the "- " list entry now reads 0.0.0.0
cd /opt/tpix-bootnode && sudo docker compose up -d          # recreates ONLY tpix-bootnode; data persists
```

**Verify on the server:**

```bash
ss -ltn | grep ':30301 '                                     # 0.0.0.0:30301 (docker-proxy)
sudo docker exec tpix-bootnode polygon-edge status --grpc-address 127.0.0.1:10000 | grep 'Libp2p Address'
#   → /ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>
```

**Verify from outside (owner's PC, PowerShell):**

```powershell
Test-NetConnection 123.253.62.252 -Port 30301 | Select TcpTestSucceeded   # True
Test-NetConnection 123.253.62.252 -Port 10001 | Select TcpTestSucceeded   # False (validators stay private)
Test-NetConnection 123.253.62.252 -Port 8549  | Select TcpTestSucceeded   # False (RPC loopback only)
```

### Step 7 — End-to-end with a throwaway community node (any Linux box with Docker, not the chain host)

```bash
mkdir -p ~/tpix-e2e && cd ~/tpix-e2e
# take the app's bundled genesis (same chain), set bootnodes to the new multiaddr only
python3 - <<'PY'
import json
g = json.load(open('genesis.json'))          # copy TPIX-Masternode/chain/genesis.json here first
g['bootnodes'] = ['/ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>']
json.dump(g, open('genesis.json', 'w'), indent=4)
PY
docker run -d --name tpix-e2e -v "$PWD:/w" 0xpolygon/polygon-edge:0.9.0 server --data-dir /w/data \
  --chain /w/genesis.json --libp2p 0.0.0.0:30303 --seal=false \
  --jsonrpc 127.0.0.1:8545 --grpc-address 127.0.0.1:9632
sleep 60; docker exec tpix-e2e polygon-edge status --grpc-address 127.0.0.1:9632   # block number rising
```

**Verify:**
- `Current Block Number` keeps increasing toward the chain head.
- On the chain host: `curl … net_peerCount` against `127.0.0.1:8549` shows ≥ 5.

**Clean up:** `docker rm -f tpix-e2e && rm -rf ~/tpix-e2e`.

### Step 8 — App release

Hand `/ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>` to the TPIX-Masternode maintainers and ship the §3.5 changes. The `--bootnode` removal is mandatory: without it, full-node mode cannot start.

**Verify:** the app's log shows `ต่อ bootnode ได้ 1 ตัว — เริ่มโหนดจริง` followed by imported blocks.

### Step 9 — Stop drift

Commit `/opt/tpix-bootnode/docker-compose.yml` and the firewall script/unit to `infrastructure/single-host/bootnode/`.

Add one line each to `single-host/README.md` and `CHAIN_HOST`: a public bootnode exists, it is not a validator, and its kill switch is `docker stop tpix-bootnode`.

### Ongoing checks

| What | Command |
|---|---|
| Peers | `curl … net_peerCount @127.0.0.1:8549` |
| Lag vs validators | `bn 8545` vs `bn 8549` |
| Inbound connection count | `sudo docker exec tpix-bootnode netstat -tn \| grep -c ':30301 .*ESTABLISHED'` |
| Rule hit counters | `sudo /usr/local/sbin/tpix-p2p-firewall status` |
| CPU / memory / network | `sudo docker stats --no-stream tpix-bootnode` |

---

## 6. Open items

1. **Secrets init (§3.5):** confirm on the app's bundled binary that `secrets init` without `--insecure` fails in 0.9.0.
2. **Bandwidth:** the owner checks the VM's egress allowance (each new community node ≈ 2 GB to sync).
3. **Out of scope, noticed during this work:**
   - `CHAIN_HOST` still says this host runs the chain only, but GpuxMine.Relay (8443 to anywhere) also runs on it.
   - `/var/backups/tpix` is 19 GB with R2 upload not configured.
   - The repo compose has drifted from live: `blockscout-db` mem_limit 1g in the repo vs 2g live.
4. **Phase 2 hardening:**
   - validator-specific egress block via static IPs or a dedicated p2p network (needs a planned recreate),
   - an alert-only bootnode check in the watchdog,
   - a second, VPS-hosted bootnode for redundancy.
