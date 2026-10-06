"""Filesystem transaction checks; no real apps or macOS permissions are changed."""
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('upgrade', Path(__file__).resolve().parents[1] / 'scripts/upgrade_local.py')
u = importlib.util.module_from_spec(spec); spec.loader.exec_module(u)


def app(path, build):
    (path / 'Contents').mkdir(parents=True)
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': u.BUNDLE,
        'CFBundleVersion': build, 'CFBundleShortVersionString': '1.3.6'}))
    (path / 'Contents/payload').write_text(build)


class UpgradeChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        (self.root / 'home').mkdir()
        self.dest = self.root / 'Applications/LibreShot.app'; app(self.dest, 'old')
        self.old = self.root / 'dist/old/LibreShot.app'; app(self.old, 'old')
        self.package = self.root / 'dist/new'; app(self.package / 'LibreShot.app', 'new')
        dmg = self.package / 'LibreShot-1.3.6-new.dmg'; dmg.write_bytes(b'fixed image')
        self.package.joinpath('SHA256SUMS').write_text(hashlib.sha256(dmg.read_bytes()).hexdigest() + '  ' + dmg.name + '\n')
        self.fail_final = False; self.fail_mounted = False
        for target, name, value in [(u, 'ROOT', self.root), (u, 'DEST', self.dest)]:
            ctx = patch.object(target, name, value); ctx.start(); self.addCleanup(ctx.stop)
        for ctx in [patch.object(u, 'running', return_value=[]), patch.object(u, 'run', side_effect=self.fake_run),
                    patch.object(Path, 'home', return_value=self.root / 'home')]:
            ctx.start(); self.addCleanup(ctx.stop)

    def fake_run(self, *args, **kwargs):
        argv = [str(a) for a in args]
        if argv[:2] == ['hdiutil', 'attach']:
            mounted = Path(argv[argv.index('-mountpoint') + 1]) / 'LibreShot.app'
            shutil.copytree(self.package / 'LibreShot.app', mounted)
            if self.fail_mounted: (mounted / 'Contents/payload').write_text('corrupt')
        elif argv[0] == 'ditto': shutil.copytree(argv[1], argv[2])
        elif argv[0] == 'bash' and argv[-1] == str(self.dest) and self.fail_final:
            raise RuntimeError('forced final signature failure')

    def test_success_retires_old_keeps_candidate_and_records_pending_permissions(self):
        u.install(self.package, False)
        self.assertEqual(u.info(self.dest)['CFBundleVersion'], 'new')
        self.assertFalse(self.old.exists())
        self.assertTrue((self.package / 'LibreShot.app').exists())
        self.assertEqual(len(list((self.root / 'home/.Trash').glob('*.app'))), 2)
        self.assertIn('pending UI check', (self.package / 'INSTALL.json').read_text())

    def test_bad_checksum_does_not_touch_old(self):
        (self.package / 'SHA256SUMS').write_text('wrong checksum')
        with self.assertRaisesRegex(RuntimeError, 'checksum'): u.install(self.package, False)
        self.assertEqual(u.info(self.dest)['CFBundleVersion'], 'old')
        self.assertTrue(self.old.exists())

    def test_running_app_blocks_replacement(self):
        with patch.object(u, 'running', return_value=['123 /Applications/LibreShot.app/Contents/MacOS/LibreShot']):
            with self.assertRaisesRegex(RuntimeError, 'still running'): u.install(self.package, False)
        self.assertEqual(u.info(self.dest)['CFBundleVersion'], 'old')

    def test_mounted_mismatch_does_not_touch_old(self):
        self.fail_mounted = True
        with self.assertRaisesRegex(RuntimeError, 'Mounted'): u.install(self.package, False)
        self.assertTrue(self.old.exists()); self.assertEqual(u.info(self.dest)['CFBundleVersion'], 'old')

    def test_failure_after_replacement_restores_all_old_apps(self):
        self.fail_final = True
        with self.assertRaisesRegex(RuntimeError, 'forced'): u.install(self.package, False)
        self.assertTrue(self.old.exists()); self.assertEqual(u.info(self.dest)['CFBundleVersion'], 'old')
        self.assertFalse((self.package / 'INSTALL.json').exists())
        self.assertTrue((self.package / 'rollback.json').exists())

    def test_plan_is_read_only(self):
        before = u.tree(self.dest); u.install(self.package, True)
        self.assertEqual(before, u.tree(self.dest)); self.assertTrue(self.old.exists())
        self.assertFalse((self.package / 'INSTALL.json').exists())


if __name__ == '__main__': unittest.main()
