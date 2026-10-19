#!/usr/bin/env python3
"""Sign nested Setup code inside out, or verify its signatures and universal payload."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess

MACHO = {bytes.fromhex(value) for value in ('cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca',
                                          'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe')}


def code_paths(app):
    binaries, bundles = [], []
    for path in app.rglob('*'):
        if path.is_symlink():
            if not path.resolve().is_relative_to(app.resolve()) or not path.exists():
                raise ValueError('Broken or escaping symlink in Setup')
            continue
        if path.is_dir() and path.suffix in ('.app', '.xpc', '.framework'):
            bundles.append(path)
        elif path.is_file():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO:
                    binaries.append(path)
    return binaries, sorted(bundles, key=lambda path: len(path.parts), reverse=True)


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def verify(app):
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    for relative in ('Versions/Current', 'Sparkle', 'Resources', 'Updater.app', 'XPCServices'):
        if not (framework / relative).is_symlink():
            raise ValueError(f'Sparkle framework symlink missing: {relative}')
    binaries, bundles = code_paths(app)
    if not binaries or framework not in bundles:
        raise ValueError('Missing Setup or Sparkle code')
    for path in [*binaries, *bundles, app]:
        run('codesign', '--verify', '--strict', path)
    run('codesign', '--verify', '--deep', '--strict', app)
    for binary in binaries:
        for arch in ('arm64', 'x86_64'):
            run('lipo', binary, '-verify_arch', arch)
    setup = app / 'Contents/MacOS/ContainerSetup'
    linked = subprocess.check_output(['otool', '-L', str(setup)], text=True)
    if '@rpath/Sparkle.framework/Versions/B/Sparkle' not in linked:
        raise ValueError('Setup does not link embedded Sparkle')
    loads = subprocess.check_output(['otool', '-l', str(setup)], text=True)
    if 'path @executable_path/../Frameworks (offset' not in loads:
        raise ValueError('Missing standalone Sparkle rpath')
    if any('/.build/' in line for line in loads.splitlines() if 'path ' in line):
        raise ValueError('Setup contains a build-folder rpath')
    receiver = app / 'Contents/Resources/ContainerReceiver'
    if 'Sparkle.framework' in subprocess.check_output(['otool', '-L', str(receiver)], text=True):
        raise ValueError('Receiver must not link Sparkle')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    for key in ('SUEnableAutomaticChecks', 'SUAutomaticallyUpdate', 'SUAllowsAutomaticUpdates', 'SUEnableSystemProfiling'):
        if info.get(key) is not False:
            raise ValueError(f'Unsafe updater default: {key}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--prepare-rpaths', action='store_true', help='Remove checkout-specific SwiftPM rpaths before signing')
    parser.add_argument('--identity', help='Developer ID SHA1, or - for ad-hoc signing')
    args = parser.parse_args()
    try:
        if args.prepare_rpaths:
            setup = args.app / 'Contents/MacOS/ContainerSetup'
            loads = subprocess.check_output(['otool', '-l', str(setup)], text=True)
            paths = re.findall(r'cmd LC_RPATH\s+cmdsize [0-9]+\s+path (.*?) \(offset', loads)
            for path in dict.fromkeys(paths):
                if '/.build/' in path:
                    run('install_name_tool', '-delete_rpath', path, setup)
        if args.identity:
            binaries, bundles = code_paths(args.app)
            options = ['--force', '--sign', args.identity, '--preserve-metadata=entitlements']
            if args.identity != '-':
                options += ['--options', 'runtime', '--timestamp']
            for path in [*binaries, *bundles, args.app]:
                run('codesign', *options, path)
        verify(args.app)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')
