#!/usr/bin/env python3
"""Create appcast.xml only from a final notarized/stapled release DMG. Never publish."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import subprocess
import tempfile
import sys
sys.dont_write_bytecode = True

from updater import ROOT, FEED, appcast, read_key

ACCOUNT = 'brave-container-adapter'
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'


def run(*args, capture=False):
    return subprocess.run([str(arg) for arg in args], check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def digest(path):
    with path.open('rb') as stream:
        hasher = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(block)
        return hasher.hexdigest()


def verify_archive(attempt):
    image = attempt / 'Brave-Container-Adapter.dmg'
    if image.is_symlink() or not image.is_file():
        raise ValueError('Expected a regular final release DMG')
    checksum = attempt / 'Brave-Container-Adapter.dmg.sha256'
    expected = f'{digest(image)}  {image.name}\n'
    if checksum.read_text() != expected:
        raise ValueError('Final DMG checksum is missing or does not match')
    run('codesign', '--verify', '--strict', image)
    run('xcrun', 'stapler', 'validate', image)
    run('hdiutil', 'verify', '-quiet', image)
    run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', image)
    return image, expected


def verify_signing_key(key):
    # -p only looks up an existing public key. Never generate or export private keys.
    actual = run(TOOLS / 'generate_keys', '--account', ACCOUNT, '-p', capture=True).decode().strip()
    if actual != key:
        raise ValueError('Keychain public key does not match the bundled/tracked updater key')


def sign_archive(image, info):
    key = read_key(required=True)
    if info.get('SUPublicEDKey') != key or info.get('SUFeedURL') != FEED:
        raise ValueError('Bundled updater key/feed differs from tracked release configuration')
    verify_signing_key(key)
    signature = run(TOOLS / 'sign_update', '--account', ACCOUNT, '-p', image, capture=True).decode().strip()
    result = appcast(info, signature, image.stat().st_size)
    run(TOOLS / 'sign_update', '--account', ACCOUNT, '--verify', image, signature)
    return result


def release(attempt):
    attempt = attempt.resolve()
    target = attempt / 'appcast.xml'
    if target.exists() or target.is_symlink():
        raise ValueError('appcast.xml already exists; inspect it before replacing it')
    read_key(required=True)
    image, checksum = verify_archive(attempt)
    with tempfile.TemporaryDirectory(prefix='cbc-appcast-') as stage:
        mount = Path(stage) / 'mounted'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, image)
        try:
            app = mount / 'Brave Container Setup.app'
            run('python3', ROOT / 'scripts/sign-setup.py', app)
            run('xcrun', 'stapler', 'validate', app)
            run('spctl', '--assess', '--type', 'execute', app)
            info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
            if info.get('CFBundleIdentifier') != 'app.choosy-brave-containers.setup':
                raise ValueError('Unexpected application identity')
            data = sign_archive(image, info)
        finally:
            run('hdiutil', 'detach', mount)
    if (attempt / 'Brave-Container-Adapter.dmg.sha256').read_text() != checksum or checksum != f'{digest(image)}  {image.name}\n':
        raise ValueError('DMG changed while generating the appcast')
    # Exclusive creation prevents accidentally overwriting an existing release feed.
    with target.open('xb') as stream:
        stream.write(data)
    print(f'Created {target}. Publish with the unchanged DMG and checksum under v{info["CFBundleShortVersionString"]}.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attempt', type=Path, nargs='?', help='completed notarization directory')
    parser.add_argument('--check-key', action='store_true', help='Only compare tracked and existing Keychain public keys')
    args = parser.parse_args()
    try:
        if args.check_key:
            verify_signing_key(read_key(required=True))
        elif args.attempt:
            release(args.attempt)
        else:
            parser.error('provide an attempt directory or --check-key')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')
