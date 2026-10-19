#!/usr/bin/env python3
"""Synthetic updater configuration, appcast and release-gate tests. No Keychain access."""
import base64
import sys
sys.dont_write_bytecode = True
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

import updater

spec = importlib.util.spec_from_file_location('release_appcast', Path(__file__).with_name('release-appcast.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
KEY = base64.b64encode(bytes(range(32))).decode()
SIGNATURE = base64.b64encode(bytes(range(64))).decode()
INFO = {'CFBundleShortVersionString': '1.6.0', 'CFBundleVersion': '10', 'LSMinimumSystemVersion': '14.0'}


class UpdaterTests(unittest.TestCase):
    def test_public_key_validation(self):
        self.assertEqual(updater.validate_key(KEY + '\n'), KEY)
        for value in ('', 'YOUR_PUBLIC_KEY', base64.b64encode(bytes(32)).decode(), KEY[:-1], SIGNATURE):
            with self.subTest(value=value), self.assertRaises(ValueError):
                updater.validate_key(value)

    def test_missing_configuration_stays_unconfigured_and_blocks_release(self):
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / 'absent.txt'
            plist = Path(directory) / 'Info.plist'
            plist.write_bytes(plistlib.dumps({'SUPublicEDKey': KEY}))
            with patch.object(updater, 'PUBLIC_KEY', key):
                updater.configure(plist)
                info = plistlib.loads(plist.read_bytes())
                self.assertNotIn('SUPublicEDKey', info)
                self.assertEqual(info['SUFeedURL'], updater.FEED)
                self.assertIs(info['SUEnableAutomaticChecks'], False)
                self.assertIs(info['SUAllowsAutomaticUpdates'], False)
                self.assertIs(info['SUAutomaticallyUpdate'], False)
                with self.assertRaises(ValueError):
                    updater.configure(plist, required=True)

    def test_configured_key_reaches_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            key, plist = Path(directory) / 'public.txt', Path(directory) / 'Info.plist'
            key.write_text(KEY + '\n')
            plist.write_bytes(plistlib.dumps({'CFBundleVersion': '10'}))
            with patch.object(updater, 'PUBLIC_KEY', key):
                updater.configure(plist, required=True)
            info = plistlib.loads(plist.read_bytes())
            self.assertEqual(info['SUPublicEDKey'], KEY)
            self.assertEqual(info['CFBundleVersion'], '10')

    def test_appcast_enclosure_and_versions(self):
        rss = ET.fromstring(updater.appcast(INFO, SIGNATURE, 12345))
        item = rss.find('./channel/item')
        ns = {'s': updater.NAMESPACE}
        self.assertEqual(item.findtext('s:version', namespaces=ns), '10')
        self.assertEqual(item.findtext('s:shortVersionString', namespaces=ns), '1.6.0')
        self.assertEqual(item.findtext('s:minimumSystemVersion', namespaces=ns), '14.0.0')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('url'), updater.REPOSITORY + '/releases/download/v1.6.0/Brave-Container-Adapter.dmg')
        self.assertEqual(enclosure.get(f'{{{updater.NAMESPACE}}}edSignature'), SIGNATURE)
        self.assertEqual(enclosure.get('length'), '12345')

    def test_reject_bad_metadata_and_signature(self):
        for info, sig, size in [(dict(INFO, CFBundleVersion='main'), SIGNATURE, 1),
                                (dict(INFO, CFBundleShortVersionString='../bad'), SIGNATURE, 1),
                                (dict(INFO, LSMinimumSystemVersion='13.0'), SIGNATURE, 1),
                                (INFO, KEY, 1), (INFO, SIGNATURE, 0)]:
            with self.subTest(info=info), self.assertRaises(ValueError):
                updater.appcast(info, sig, size)

    def test_changed_dmg_never_reaches_notarization_or_signing(self):
        with tempfile.TemporaryDirectory() as directory:
            attempt = Path(directory)
            (attempt / 'Brave-Container-Adapter.dmg').write_bytes(b'changed')
            (attempt / 'Brave-Container-Adapter.dmg.sha256').write_text('stale checksum')
            with patch.object(release, 'run') as run, self.assertRaises(ValueError):
                release.verify_archive(attempt)
            run.assert_not_called()

    def test_wrong_keychain_account_key_never_signs(self):
        info = dict(INFO, SUPublicEDKey=KEY, SUFeedURL=updater.FEED)
        with patch.object(release, 'read_key', return_value=KEY), patch.object(release, 'run', return_value=b'other-key') as run:
            with self.assertRaises(ValueError):
                release.sign_archive(Path('/unused.dmg'), info)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[1:], ('--account', 'brave-container-adapter', '-p'))

    def test_mismatched_bundle_key_never_accesses_keychain(self):
        with patch.object(release, 'read_key', return_value=KEY), patch.object(release, 'run') as run:
            with self.assertRaises(ValueError):
                release.sign_archive(Path('/unused.dmg'), dict(INFO, SUPublicEDKey='wrong'))
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
