#!/usr/bin/env python3
"""Prepare and install a fixed local package. Native quit/permissions stay in the UI."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEST = Path('/Applications/LibreShot.app')
BUNDLE = 'com.allensong.LibreShot'


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def info(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        return plistlib.load(stream)


def tree(app):
    result = {}
    for p in app.rglob('*'):
        key = str(p.relative_to(app))
        if p.is_symlink():
            result[key] = ['link', os.readlink(p)]
        elif p.is_file():
            result[key] = ['file', hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mode & 0o777]
    return result


def record(directory, name, value):
    (directory / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def running():
    output = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
    # App main processes only; never inspect argv containing private user data.
    return [line.strip() for line in output.splitlines()
            if line.rstrip().endswith('/Contents/MacOS/LibreShot')]


def package(path):
    if path.exists():
        raise RuntimeError('Output already exists; use a fresh directory or install this fixed package.')
    path.parent.mkdir(parents=True, exist_ok=True)
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    diff = subprocess.check_output(['git', '-C', str(ROOT), 'diff', 'HEAD', '--binary'])
    untracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '--others', '--exclude-standard'], text=True)
    if untracked.strip():
        raise RuntimeError('Commit or remove untracked source files before packaging; no unrecorded inputs allowed.')
    # The release builder creates this directory; keep logs beside it on failure too.
    log = path.parent / (path.name + '.build.log')
    with log.open('x') as stream:
        run('bash', ROOT / 'build_release.sh', '--ad-hoc', path, stdout=stream, stderr=subprocess.STDOUT, cwd=ROOT)
    shutil.copy2(log, path / 'build.log')
    (path / 'source.patch').write_bytes(diff)
    data = info(path / 'LibreShot.app')
    record(path, 'SOURCE.json', {'commit': commit, 'dirty': bool(diff),
                               'version': data['CFBundleShortVersionString'], 'build': data['CFBundleVersion']})
    print(f'Package fixed at {path}\nQuit LibreShot normally, then run:')
    print(f'python3 scripts/upgrade_local.py install "{path}"')


def install(path, plan):
    path = path.resolve()
    if running():
        raise RuntimeError('LibreShot/Preview main process is still running. Quit through the app menu first.\n' + '\n'.join(running()))
    candidate = path / 'LibreShot.app'
    data = info(candidate)
    if data['CFBundleIdentifier'] != BUNDLE:
        raise RuntimeError('Candidate bundle identity mismatch.')
    dmg = path / f"LibreShot-{data['CFBundleShortVersionString']}-{data['CFBundleVersion']}.dmg"
    actual = hashlib.sha256(dmg.read_bytes()).hexdigest()
    # Require the expected exact filename, not an arbitrary checksum file command.
    lines = (path / 'SHA256SUMS').read_text().splitlines()
    if not any(line.split(maxsplit=1) == [actual, dmg.name] for line in lines):
        raise RuntimeError('DMG checksum mismatch or missing expected filename.')
    run('hdiutil', 'verify', dmg, '-quiet')
    run('bash', ROOT / 'scripts/verify_release_signing.sh', '--allow-ad-hoc', candidate)
    old = [DEST] + list((ROOT / 'dist').glob('*/LibreShot.app')) + list((ROOT / 'dist').glob('*/LibreShot.xcarchive/Products/Applications/LibreShot.app'))
    old = [p for p in old if p.exists() and path not in p.resolve().parents and info(p).get('CFBundleIdentifier') == BUNDLE]
    record_data = {'version': data['CFBundleShortVersionString'], 'build': data['CFBundleVersion'],
                   'sha256': actual, 'package': str(path), 'destination': str(DEST), 'retire': [str(p) for p in old]}
    if plan:
        print(json.dumps(record_data, ensure_ascii=False, indent=2)); return
    if (path / 'INSTALL.json').exists():
        raise RuntimeError('This package already has an installation record; inspect it instead of reinstalling silently.')
    # Mount and compare before touching installed files.
    with tempfile.TemporaryDirectory(prefix='libreshot-mount-') as mount:
        run('hdiutil', 'attach', dmg, '-mountpoint', mount, '-nobrowse', '-quiet')
        try:
            mounted = Path(mount) / 'LibreShot.app'
            run('bash', ROOT / 'scripts/verify_release_signing.sh', '--allow-ad-hoc', mounted)
            if tree(candidate) != tree(mounted):
                raise RuntimeError('Mounted DMG differs from candidate app.')
            prefs = Path.home() / 'Library/Containers' / BUNDLE / 'Data/Library/Preferences' / (BUNDLE + '.plist')
            if prefs.exists():
                shutil.copy2(prefs, path / 'pre-upgrade-preferences.plist')
            staging = Path(tempfile.mkdtemp(prefix='.LibreShot-upgrade-', dir=DEST.parent))
            retired = []
            installed = False
            try:
                staged_app = staging / 'LibreShot.app'
                run('ditto', mounted, staged_app)
                if tree(staged_app) != tree(candidate):
                    raise RuntimeError('Staged install differs from candidate.')
                if running():
                    raise RuntimeError('LibreShot restarted during preparation. Quit and retry.')
                trash = Path.home() / '.Trash'
                trash.mkdir(exist_ok=True)
                for index, original in enumerate(old):
                    target = trash / f'LibreShot-retired-{dt.datetime.now():%Y%m%d-%H%M%S-%f}-{index}.app'
                    if target.exists():
                        raise RuntimeError('Trash target collision.')
                    shutil.move(str(original), target)
                    retired.append({'original': str(original), 'trash': str(target)})
                    record(path, 'retired-apps.json', retired)
                staged_app.rename(DEST); installed = True
                run('bash', ROOT / 'scripts/verify_release_signing.sh', '--allow-ad-hoc', DEST)
                if tree(DEST) != tree(candidate):
                    raise RuntimeError('Final install differs from candidate.')
                record_data.update({'installed_at': dt.datetime.now().astimezone().isoformat(),
                                    'permissions': 'pending UI check/refresh', 'actual_validation': 'pending',
                                    'retired': retired})
                record(path, 'INSTALL.json', record_data)
            except Exception:
                # Remove only our staged/new copy, and recover all retired files.
                if installed and DEST.exists():
                    shutil.move(str(DEST), staging / 'failed-new.app')
                for item in reversed(retired):
                    original = Path(item['original'])
                    if not original.exists():
                        shutil.move(item['trash'], original)
                record(path, 'rollback.json', {'restored': retired, 'validation': 'pending after rollback'})
                raise
            finally:
                shutil.rmtree(staging)
        finally:
            run('hdiutil', 'detach', mount, '-quiet')
    print(f'Installed {record_data["version"]} build {record_data["build"]} at {DEST}')
    print('Next: open that exact path through Finder/native UI, refresh only failed permission entries, restart.')
    print('Installation is not permission/capture acceptance. Follow docs/operations/install-and-permissions.md.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('package'); p.add_argument('output', type=Path)
    p = sub.add_parser('install'); p.add_argument('package', type=Path); p.add_argument('--plan', action='store_true')
    sub.add_parser('status')
    args = parser.parse_args()
    if args.action == 'package':
        package(args.output.resolve())
    elif args.action == 'install':
        install(args.package.resolve(), args.plan)
    else:
        data = info(DEST) if DEST.exists() else {}
        print('Installed:', data.get('CFBundleShortVersionString', 'none'), 'build', data.get('CFBundleVersion', 'none'))
        print('Running main processes:', '\n'.join(running()) or 'none')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, KeyError, ValueError) as error:
        raise SystemExit(str(error))
