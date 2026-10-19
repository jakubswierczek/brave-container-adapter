#!/usr/bin/env python3
"""Public updater configuration and appcast formatting. No private key handling."""
import argparse
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
FEED = 'https://github.com/jakubswierczek/brave-container-adapter/releases/latest/download/appcast.xml'
REPOSITORY = 'https://github.com/jakubswierczek/brave-container-adapter'
PUBLIC_KEY = ROOT / 'config/updater-public-key.txt'
NAMESPACE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NAMESPACE)


def validate_key(value):
    value = value.strip()
    try:
        decoded = base64.b64decode(value, validate=True)
    except ValueError as error:
        raise ValueError('Invalid updater public key encoding') from error
    if len(decoded) != 32 or not any(decoded) or base64.b64encode(decoded).decode() != value:
        raise ValueError('Updater public key must be a canonical base64 Ed25519 public key')
    return value


def read_key(required=False):
    if not PUBLIC_KEY.exists():
        if required:
            raise ValueError('Missing config/updater-public-key.txt; provision the public key before release')
        return None
    return validate_key(PUBLIC_KEY.read_text())


def configure(plist, required=False):
    key = read_key(required)
    data = plistlib.loads(plist.read_bytes())
    data.update(SUFeedURL=FEED, SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
                SUAllowsAutomaticUpdates=False, SUEnableSystemProfiling=False,
                SUVerifyUpdateBeforeExtraction=True)
    data.pop('SUPublicEDKey', None)
    if key:
        data['SUPublicEDKey'] = key
    plist.write_bytes(plistlib.dumps(data))


def appcast(info, signature, length):
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version) or not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Invalid release version/build number')
    if info.get('LSMinimumSystemVersion') not in ('14.0', '14.0.0'):
        raise ValueError('Expected minimum macOS 14')
    if len(base64.b64decode(signature, validate=True)) != 64 or length <= 0:
        raise ValueError('Invalid signature or archive size')
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Brave Container Setup'
    ET.SubElement(channel, 'link').text = REPOSITORY
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Version {version}'
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
    for name, value in [('version', build), ('shortVersionString', version), ('minimumSystemVersion', '14.0.0')]:
        ET.SubElement(item, f'{{{NAMESPACE}}}{name}').text = value
    ET.SubElement(item, 'enclosure', {
        'url': f'{REPOSITORY}/releases/download/v{version}/Brave-Container-Adapter.dmg',
        f'{{{NAMESPACE}}}edSignature': signature, 'length': str(length), 'type': 'application/octet-stream',
    })
    ET.indent(rss)
    return ET.tostring(rss, encoding='utf-8', xml_declaration=True) + b'\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['configure', 'require-key'])
    parser.add_argument('plist', nargs='?', type=Path)
    parser.add_argument('--require-key', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'require-key':
            read_key(required=True)
        elif args.plist:
            configure(args.plist, args.require_key)
        else:
            parser.error('configure requires a plist')
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
