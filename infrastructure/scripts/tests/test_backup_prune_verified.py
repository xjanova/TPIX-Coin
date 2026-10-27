import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('prune', Path(__file__).parents[1] / 'backup-prune-verified.py')
prune = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prune)
NOW = prune.timestamp('2026-10-27T02:00:00Z')


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.files = []
        for day in range(23, 27):
            path = self.directory / f'tpix-chain-202610{day}-191701.tar.gz.gpg'
            path.write_bytes(f'archive-{day}'.encode())
            self.files.append(path)
            self.receipt(path)
        self.checked = []

    def tearDown(self):
        self.temp.cleanup()

    def receipt(self, path, **changes):
        fields = dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                      bytes=str(path.stat().st_size), remote=f'R2:tpix-chain-backup/{path.name}',
                      verified_at='2026-10-27T01:00:00Z')
        fields.update(changes)
        target = Path(str(path) + '.r2-verified')
        target.write_text(''.join(f'{key}={value}\n' for key, value in fields.items()))
        target.chmod(0o600)

    def remote(self, *args):
        self.checked.append(args[0])

    def plan(self):
        return prune.build_plan(self.directory, 2, 'tpix-chain-backup', NOW, self.remote)

    def test_dry_run_and_apply_keep_latest_two(self):
        plan = self.plan()
        self.assertEqual(len(prune.archives(self.directory)), 4)
        self.assertEqual(self.checked, [p.name for p in self.files])
        prune.apply_plan(self.directory, plan)
        self.assertEqual(prune.archives(self.directory), self.files[-2:])
        self.assertTrue(Path(str(self.files[0]) + '.r2-upload.lock').exists())

    def test_minimum_two_copies(self):
        with self.assertRaises(ValueError):
            prune.build_plan(self.directory, 1, 'tpix-chain-backup', NOW, self.remote)

    def test_corrupt_same_size_archive(self):
        self.files[0].write_bytes(b'x' * self.files[0].stat().st_size)
        with self.assertRaises(ValueError):
            self.plan()
        self.assertTrue(all(p.exists() for p in self.files))

    def test_corrupt_retained_copy_also_blocks_pruning(self):
        self.files[-1].write_bytes(b'broken latest copy')
        with self.assertRaises(ValueError):
            self.plan()
        self.assertTrue(all(p.exists() for p in self.files))

    def test_wrong_destination_and_stale_receipt(self):
        for changes in ({'remote': 'R2:other-bucket/object'},
                        {'verified_at': '2026-09-01T01:00:00Z'},
                        {'verified_at': '2026-10-28T01:00:00Z'}):
            self.receipt(self.files[0], **changes)
            with self.assertRaises(ValueError):
                self.plan()

    def test_missing_or_untrusted_receipt(self):
        receipt = Path(str(self.files[0]) + '.r2-verified')
        receipt.chmod(0o644)
        with self.assertRaises(ValueError):
            self.plan()
        receipt.unlink()
        with self.assertRaises(FileNotFoundError):
            self.plan()

    def test_symlink_archive_rejected(self):
        original = self.files[0]
        original.unlink()
        original.symlink_to(self.files[1])
        with self.assertRaises(ValueError):
            self.plan()

    def test_changed_file_or_set_rejected_before_any_deletion(self):
        plan = self.plan()
        self.files[1].write_bytes(b'changed')
        with self.assertRaises(ValueError):
            prune.apply_plan(self.directory, plan)
        self.assertTrue(all(p.exists() for p in self.files))
        plan = self.plan_after_reset()
        (self.directory / 'tpix-chain-20261027-191701.tar.gz.gpg').write_bytes(b'new')
        with self.assertRaises(ValueError):
            prune.apply_plan(self.directory, plan)

    def plan_after_reset(self):
        self.receipt(self.files[1])
        return self.plan()

    def test_active_upload_prevents_all_deletion(self):
        plan = self.plan()
        with open(str(self.files[1]) + '.r2-upload.lock', 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                prune.apply_plan(self.directory, plan)
        self.assertTrue(all(p.exists() for p in self.files))

    def test_remote_checks_size_age_and_manifest(self):
        name = self.files[0].name
        digest = hashlib.sha256(self.files[0].read_bytes()).hexdigest()
        info = {'Size': self.files[0].stat().st_size, 'IsDir': False, 'ModTime': '2026-10-27T01:00:00Z'}
        manifest = f'{digest}  {name}\n'
        with patch.object(prune, 'rclone', side_effect=[manifest, json.dumps(info)]) as call:
            prune.verify_remote(name, info['Size'], digest, 'tpix-chain-backup', NOW)
            self.assertIn('--use-server-modtime', call.call_args.args[0])
        for changed in ({'Size': 0}, {'ModTime': '2026-09-01T01:00:00Z'}):
            with patch.object(prune, 'rclone', side_effect=[manifest, json.dumps({**info, **changed})]):
                with self.assertRaises(ValueError):
                    prune.verify_remote(name, info['Size'], digest, 'tpix-chain-backup', NOW)
        with patch.object(prune, 'rclone', return_value='wrong'):
            with self.assertRaises(ValueError):
                prune.verify_remote(name, info['Size'], digest, 'tpix-chain-backup', NOW)

    def test_remote_failure_leaves_every_local_copy(self):
        def unavailable(*args):
            raise RuntimeError('R2 unavailable')
        with self.assertRaises(RuntimeError):
            prune.build_plan(self.directory, 2, 'tpix-chain-backup', NOW, unavailable)
        self.assertTrue(all(p.exists() for p in self.files))


if __name__ == '__main__':
    unittest.main()
