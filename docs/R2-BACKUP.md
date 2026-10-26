# Private offsite chain backups

Use an R2 Standard bucket with public development URL and custom domains disabled.
Use an Object Read & Write token scoped to that bucket and the server egress IP.
The token must not have bucket administration privileges. Record expiry and rotate
before it expires. Credentials belong in a root-owned mode-600 environment file,
never Git, command arguments, CI logs or chat.

For `tpix-chain-backup`, the lock rule `tpix-backup-retain-30-days` protects objects
whose names start with `tpix-chain-` for 30 days. This includes `.sha256` manifests.
The lock prevents object deletion/overwrite during retention; a privileged account
administrator can still change bucket configuration. It is not protection against
compromise of the Cloudflare administrator account.

`backup-upload-r2.sh` uploads with immutable collision handling, streams the whole
remote archive through SHA-256, checks that the source did not change, uploads and
reads back a checksum manifest, then writes a local mode-600 `.r2-verified` receipt.
Same-size corrupt remote files fail verification and are never silently replaced.
Transfers default to 10 MiB/s (`TPIX_R2_BWLIMIT`) to limit validator-host load.
R2 does not implement S3 object ACL headers; leave the rclone ACL empty and enforce
privacy on the bucket. See [R2 compatibility](https://developers.cloudflare.com/r2/api/s3/api/).
With rclone 1.60, R2 can return a version ID after PUT that leads to an unsupported
versioned HEAD (501). `--s3-no-head` skips this post-upload metadata request;
the full content read-back still verifies every byte. Pre-upload collision checks
remain enabled. This was reproduced against the bucket during rollout.

The uploader never prunes R2. `TPIX_BACKUP_KEEP_DAYS` is local-only. Configure an R2
expiration lifecycle separately, after approval, with an age greater than or equal
to the lock period. A lock alone does not expire objects: storage continues growing
until lifecycle deletion or deliberate cleanup is configured.

## Enable safely

1. Create the private bucket and retention lock; issue a scoped token.
2. Install the uploader and run the offline tests below.
3. Run `setup-r2-backup.sh` as root for hidden credential entry and a disposable
   transport probe. It backs up and shell-quotes `/etc/tpix-backup.env` correctly.
4. Upload an existing encrypted archive. Read it back, verify its checksum,
   decrypt through GPG and validate its tar contents, including genesis and chain DB.
   Uploading an existing archive requires no validator stop.
5. Keep local retention unchanged until all candidates for local removal have
   verified remote copies and a separate isolated recovery drill has succeeded.
   A checksum/decryption check alone is not a full blockchain recovery drill.
6. Keep the backup encryption passphrase in a separate protected recovery location.
   An R2 access key cannot decrypt backups. Never start a copied validator with
   its production signing key on a connected network during a recovery drill.

Existing nightly cron creates a consistent encrypted snapshot by briefly stopping
one validator under the maintenance lock, then restarts it before uploading.
It currently holds the maintenance lock during verification/upload too; allow for
longer maintenance occupancy when sizing network limits and monitoring backups.

```sh
bash -n infrastructure/scripts/backup-upload-r2.sh
bash -n infrastructure/scripts/setup-r2-backup.sh
bash infrastructure/scripts/tests/backup-upload-r2.test.sh
bash infrastructure/scripts/tests/setup-r2-quoting.test.sh
```

The tests use temporary files and a fake rclone; they cannot reach R2 or validators.
