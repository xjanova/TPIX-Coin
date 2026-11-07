# TPIX Explorer — Blockscout 12 stack (`/opt/tpix-bs`)

explorer.tpix.online runs from this stack since 2026-11-06T17:49Z (upgraded from Blockscout 6.10.1).
The files here are byte-for-byte copies of what runs on the chain host `tpixserver` (123.253.62.252).

| file here | on the host |
|---|---|
| `docker-compose.yml` | `/opt/tpix-bs/docker-compose.yml` (compose project `tpixbs`) |
| `switch-nginx.sh` | `/opt/tpix-bs/switch-nginx.sh` (root, 0700) |
| `fetch-images.sh` | `/opt/tpix-bs/fetch-images.sh` |

| service | image | port (127.0.0.1) |
|---|---|---|
| bsn-backend | `tpix/blockscout:12.0.4` | 4200 |
| bsn-frontend | `tpix/blockscout-frontend:v2.12.1` | 3200 |
| bsn-stats | `ghcr.io/blockscout/stats:v2.19.1` | 8163 |
| bsn-verifier | `ghcr.io/blockscout/smart-contract-verifier:v1.11.1` | internal 8050 |
| bsn-db | `postgres:16-alpine` | internal |

The visualizer (8154) is still the `visualizer` service of `/opt/tpix/docker-compose.yml`
(`infrastructure/single-host/docker-compose.yml`), shared by both stacks.

## Images

Upstream stopped publishing public images after backend 9.0.2 / frontend v2.3.5, and building them on
the chain host is too heavy. [xjanova/tpix-blockscout-build](https://github.com/xjanova/tpix-blockscout-build)
builds the upstream tags unchanged on GitHub Actions; release `images-2026-11-07` holds backend
10.2.6 / 11.3.3 / 12.0.4 and frontend v2.12.1 as `docker save | gzip` files with `.sha256`.

```bash
sudo /opt/tpix-bs/fetch-images.sh <asset-file-name> ...   # TAG=images-YYYY-MM-DD to pick another release
```

New versions: edit `versions.env` in that repo and push.

## Run

Secrets come from `/opt/tpix/.env` (`BS_DB`, `BS_USER`, `BS_PASS`, `BS_SECRET_KEY_BASE`, `BS_SENSITIVE_KEY`);
the compose file refuses to start without them.

```bash
cd /opt/tpix-bs && sudo docker compose --env-file /opt/tpix/.env up -d
```

The explorer shares the host with the validators. Do not restart explorer services or validators
without the owner's OK.

## nginx

`switch-nginx.sh new|old` rewrites the upstream ports in `/etc/nginx/sites-enabled/tpix-explorer.conf`
and `/etc/nginx/snippets/tpix-verify-gate-locations.conf`, runs `nginx -t`, reloads, and restores the
backup if the test fails. It refuses to switch to a backend that does not answer.
Repo copies of those two files: `../single-host/nginx-explorer.conf`, `../blockscout/tpix-verify-gate-locations.conf`.

## Old stack and rollback

The 6.10.1 services (`blockscout-db/backend/sc-verifier/stats/frontend`) in `/opt/tpix/docker-compose.yml`
are stopped and carry `profiles: ["legacy-explorer"]`, so the chain watchdog's `compose up -d` does not start
them again. Images 6.10.1 and frontend v1.38.0 are kept on the host for rollback:

```bash
cd /opt/tpix && sudo docker compose --profile legacy-explorer up -d   # backend needs ~2 min
sudo /opt/tpix-bs/switch-nginx.sh old
```

Contracts verified on the old database after the 2026-11-06T16:05Z snapshot would need verifying again on
the new one; at the switch both sides had the same 19 verified contracts.
