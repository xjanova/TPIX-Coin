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

## Old stack: removed 2026-11-20, no rollback

The 6.10.1 stack was kept stopped for 13 days after the switch and then removed from the chain host:

- containers `blockscout-db/backend/sc-verifier/stats/frontend`
- volumes `tpix_blockscout-db-data` (4.0 GB) and `tpix_sc-verifier-compilers`
- images `blockscout/blockscout:6.10.1`, `frontend:v1.38.0`, and the unpinned `sig-provider`,
  `smart-contract-verifier:latest`, `stats:latest`
- the five services and the `volumes:` block in `/opt/tpix/docker-compose.yml`
  (host backup: `docker-compose.yml.bak-20261120-pre-bs6-removal`)

`blockscout-visualizer` still runs from `/opt/tpix/docker-compose.yml`: nginx `/visualize-api/` proxies to
`127.0.0.1:8154`. Removing those services did not change the compose config hash of the validators or the
visualizer, so `compose up -d` there recreates nothing.

`switch-nginx.sh old` has nothing to switch to any more and refuses. A rollback would mean restoring a
Postgres dump into a fresh 6.10.1 stack; there is no such dump on the host.
