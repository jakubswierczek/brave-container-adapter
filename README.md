# Brave Container Adapter

Open links in a specific Brave profile and container through your preferred browser switcher.

The setup app creates standalone macOS destination apps such as **Brave — Work**, **Brave — Personal**, or **Brave — Temporary**. Give each app a name and a generated or custom icon. Add it to a switcher that supports custom applications and HTTP/HTTPS URL events.

## Get started

1. Download [**Brave-Container-Adapter.dmg**](https://github.com/jakubswierczek/brave-container-adapter/releases/latest).
2. Open the DMG. Drag **Brave Container Setup** into Applications, then open it there.
3. Enable Containers in Brave. In Setup, select a profile/container, name and icon, then click **Install destination**.
4. Add the generated app from `~/Applications/Brave Destinations/` to your switcher. Keep the switcher as your default browser.

For a temporary shortcut, select **Temporary** for the desired profile. Each incoming URL batch gets a fresh container. Temporary does not mean incognito or immediate data deletion.

Generate destination apps on each Mac. They contain local paths and configuration. The setup app is portable; generated destination apps are not.

## Requirements and limits

- macOS 14+. The DMG includes Apple silicon and Intel binaries. No Xcode is needed to run it.
- Brave Containers: named routing requires 1.92.140+; temporary routing requires 1.95.101+.
- Tested on Apple silicon, macOS 26.6.2, with Brave 1.92.140 and 1.95.101. Intel and macOS 14 runtime checks remain open.
- Third-party switcher delivery has not yet been tested. GUI routing checks used an isolated copy of Brave. See the [test record](docs/testing.md).

Discovery reads Brave's internal preference format. Named routing resolves a saved container ID to its current name before invoking Brave directly. A rename/delete race between saved preferences and Brave's in-memory state can still cause incorrect routing. **This adapter is not an isolation security boundary.** Check the container badge before sensitive browsing.

Only links sent to a generated app pass through the adapter. Normal navigation inside a browser does not automatically pass through a switcher.

## Documentation

- [Use the app and CLI](docs/usage.md): profiles, temporary containers, names, icons, updates and removal.
- [Troubleshooting](docs/troubleshooting.md): `doctor`, routing failures and safe diagnostics.
- [Development](docs/development.md): build, tests and DMG packaging.
- [Architecture](docs/architecture.md): discovery, identity and launch guarantees.
- [Testing](docs/testing.md): automated coverage and manual verification.
- [Signing and releases](docs/signing.md): Developer ID, notarization and release checks.
- [Public-readiness audit](docs/public-readiness.md): findings and the publication checklist.
- [Maintenance](docs/maintenance.md), [contributing](CONTRIBUTING.md) and [security reporting](SECURITY.md).

## Build from source

Requires Swift 6.0+ and Xcode with Swift Testing.

```bash
scripts/test.sh
scripts/build.sh
dist/bin/cbc list
dist/bin/cbc install --profile Default --temporary
```

This is an independent utility, not an official Brave product. Code, documentation and project-owned artwork use the [MIT license](LICENSE). No rights to third-party trademarks are granted. The repository remains private while release checks are completed.
