#!/usr/bin/env python3
"""Keep recent local archives; prune only copies verified on locked private R2.

An archive whose upload never got a receipt is dropped once newer verified
archives cover it, so one failed night cannot block pruning forever.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess

PATTERN = re.compile(r'tpix-chain-\d{8}-\d{6}\.tar\.gz\.gpg')
MAX_REMOTE_AGE = 29 * 86400  # one day of margin within the 30-day bucket lock


def timestamp(value):
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Timestamp must include timezone')
    return parsed.timestamp()


def rclone(args):
    result = subprocess.run(['rclone', *args, '--retries', '1', '--low-level-retries', '1',
                             '--contimeout', '10s', '--timeout', '20s'],
                            check=True, capture_output=True, text=True, timeout=45)
    return result.stdout


def verify_remote(name, size, digest, bucket, now):
    remote = f'R2:{bucket}/{name}'
    manifest = rclone(['cat', remote + '.sha256'])
    if manifest != f'{digest}  {name}\n':
        raise ValueError(f'{name}: remote manifest mismatch')
    info = json.loads(rclone(['lsjson', remote, '--stat', '--use-server-modtime']))
    age = now - timestamp(info['ModTime'])
    if info.get('IsDir') or info['Size'] != size or not -300 <= age <= MAX_REMOTE_AGE:
        raise ValueError(f'{name}: remote object size/age is unsafe for local removal')


def archives(directory):
    # Include matching symlinks so they cause validation failure, never disappear
    # from a plan silently. Keep the two latest by the timestamp in their names.
    return sorted(p for p in directory.iterdir() if PATTERN.fullmatch(p.name))


def receipt_digest(path, size, bucket, now):
    """Return the receipt's digest, or None when no receipt was ever written.

    A missing receipt means the upload or its read-back failed that night. A
    receipt that exists but is malformed, stale, loosely permissioned or points
    elsewhere still fails closed: that is tampering or corruption, not a retry.
    """
    receipt_path = Path(str(path) + '.r2-verified')
    try:
        receipt_stat = receipt_path.lstat()
    except FileNotFoundError:
        return None
    if (not stat.S_ISREG(receipt_stat.st_mode)
            or receipt_stat.st_uid != os.geteuid()
            or stat.S_IMODE(receipt_stat.st_mode) & 0o077):
        raise ValueError(f'{path.name}: untrusted receipt permissions/type')
    fields = dict(line.split('=', 1) for line in receipt_path.read_text().splitlines())
    digest = fields['sha256']
    if (not re.fullmatch(r'[a-f0-9]{64}', digest)
            or fields['bytes'] != str(size)
            or fields['remote'] != f'R2:{bucket}/{path.name}'
            or not -300 <= now - timestamp(fields['verified_at']) <= MAX_REMOTE_AGE):
        raise ValueError(f'{path.name}: invalid, stale or wrong-destination receipt')
    return digest


def entry(path, info, digest):
    result = {'name': path.name, 'bytes': info.st_size, 'sha256': digest,
              'inode': info.st_ino, 'mtime_ns': info.st_mtime_ns}
    if digest is None:
        result['unverified'] = True
    return result


def build_plan(directory, keep, bucket, now, check_remote=verify_remote):
    if keep < 2:
        raise ValueError('At least two local archives must be kept')
    files = archives(directory)
    if any(p.is_symlink() or not p.is_file() for p in files):
        raise ValueError('Archive paths must be regular files, not symlinks')
    # Every archive that has a receipt is checked in full, retained ones too. A
    # corrupt newest file must never cause an older healthy copy to be removed.
    infos, digests = {}, {}
    for path in files:
        before = path.stat()
        infos[path] = before
        digest = receipt_digest(path, before.st_size, bucket, now)
        if digest is None:
            continue
        with path.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        after = path.stat()
        if actual != digest or (before.st_ino, before.st_size, before.st_mtime_ns) != (
                after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError(f'{path.name}: local archive changed after verification')
        check_remote(path.name, before.st_size, digest, bucket, now)
        digests[path] = digest
    verified = [p for p in files if p in digests]
    retained = verified[-keep:]
    result = {'directory': str(directory), 'keep': keep, 'bucket': bucket,
              'retained': [p.name for p in retained], 'unverified_kept': [],
              'remove': [], 'bytes': 0}
    for path in files:
        if path in retained:
            continue
        if path in digests:
            removable = True
        else:
            # One failed read-back used to block pruning forever (2026-11-18) and
            # the disk grew by one archive a night. An archive without a receipt
            # is a leftover once `keep` verified archives exist and a newer one
            # is among them. A receipt-less archive newer than every verified one
            # may be the only copy of the latest state, so it always stays.
            removable = len(retained) == keep and path.name < retained[-1].name
        if removable:
            result['remove'].append(entry(path, infos[path], digests.get(path)))
            result['bytes'] += infos[path].st_size
        else:
            result['unverified_kept'].append(path.name)
    return result


def apply_plan(directory, plan):
    expected = sorted([item['name'] for item in plan['remove']] + plan['retained']
                      + plan.get('unverified_kept', []))
    if [p.name for p in archives(directory)] != expected:
        raise ValueError('Archive set changed; create a fresh plan')
    # Recheck every candidate before deleting any, while holding all upload locks.
    handles = []
    try:
        for item in plan['remove']:
            path = directory / item['name']
            descriptor = os.open(str(path) + '.r2-upload.lock', os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
            handle = os.fdopen(descriptor, 'w')
            handles.append(handle)
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            info = path.lstat()
            if (not stat.S_ISREG(info.st_mode) or info.st_ino != item['inode']
                    or info.st_size != item['bytes'] or info.st_mtime_ns != item['mtime_ns']):
                raise ValueError('Archive changed after plan validation')
            # A retry may have verified a leftover since the plan was made. It is
            # then an ordinary verified archive: make a fresh plan instead.
            if item.get('unverified') and os.path.lexists(str(path) + '.r2-verified'):
                raise ValueError('Archive was verified after plan validation')
        for item in plan['remove']:
            path = directory / item['name']
            path.unlink()
            if not item.get('unverified'):
                Path(str(path) + '.r2-verified').unlink()
            # Keep the tiny lock inode: deleting an active lock path permits a
            # second process to acquire a new inode and bypass serialization.
    finally:
        for handle in handles:
            handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(os.environ.get('TPIX_BACKUP_DIR', '/var/backups/tpix')))
    parser.add_argument('--keep', type=int, default=2)
    parser.add_argument('--apply', action='store_true', help='Remove validated local copies; default is dry-run')
    parser.add_argument('--plan-output', type=Path)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit('Must run as root')
    os.umask(0o077)
    directory = args.directory.resolve(strict=True)
    if args.directory.is_symlink() or directory == Path('/'):
        raise SystemExit('Unsafe backup directory')
    bucket = os.environ.get('TPIX_R2_BUCKET', 'tpix-chain-backup')
    account = os.environ['TPIX_R2_ACCOUNT_ID']
    if not re.fullmatch(r'[a-fA-F0-9]{32}', account) or not re.fullmatch(r'[a-z0-9][a-z0-9.-]*[a-z0-9]', bucket):
        raise SystemExit('Invalid R2 destination')
    os.environ.update(RCLONE_CONFIG_R2_TYPE='s3', RCLONE_CONFIG_R2_PROVIDER='Cloudflare',
                      RCLONE_CONFIG_R2_ACCESS_KEY_ID=os.environ['TPIX_R2_ACCESS_KEY_ID'],
                      RCLONE_CONFIG_R2_SECRET_ACCESS_KEY=os.environ['TPIX_R2_SECRET_ACCESS_KEY'],
                      RCLONE_CONFIG_R2_ENDPOINT=f'https://{account}.r2.cloudflarestorage.com',
                      RCLONE_S3_NO_CHECK_BUCKET='true')
    with open(directory / '.retention.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        plan = build_plan(directory, args.keep, bucket, datetime.now(timezone.utc).timestamp())
        if args.plan_output:
            args.plan_output.write_text(json.dumps(plan, indent=2))
        if args.apply:
            apply_plan(directory, plan)
        print(json.dumps({'applied': args.apply, **plan}, indent=2))


if __name__ == '__main__':
    main()
