# Testing and verification

## Automated checks

Run the commands in [development](development.md). Swift Testing uses synthetic
`Local State` and `Preferences` fixtures. Coverage includes:

- Profile display names versus directory keys; configured versus retained containers.
- Missing, malformed and changing files; retries after a partial write.
- ID lookup, rename, deletion, duplicate IDs/names and disabled features.
- URL preservation, unsupported schemes, argument budgets and argument arrays.
- Temporary mode, version guards, legacy configuration and stable identity.
- Standalone bundles, idempotent updates, name collisions, symlinks and icon imports.
- Queue count/byte limits, FIFO, duplicate events and atomic batch rejection.
- Bounded reads, oversized files, symlinks and special-file rejection.
- Browser ownership, stale/foreign locks and safe activation selection.
- Signing timeout/cancellation, failed swaps, rollback failures and retry recovery.
- Real CLI parsing, safe diagnostics, generation/customization and read-only fixture hashes.

`scripts/test.sh` runs Swift tests and the process-level CLI checks. CI runs tests
and release builds on `macos-14`, `macos-15` and `macos-15-intel`; macOS 15 also
packages both architectures. The `checks` job succeeds only if every matrix job passes.
Runtime tests exercise synthetic adapter behavior; they do not launch Brave.

Tests do not open Brave or use personal browser data. Packaging tests use a harmless
system executable. Passing them does not certify browser routing.

## Recorded integration coverage

The [historical record](integration.md) contains dates and exact evidence. Named
routing was checked on Brave 1.92.140; temporary and appearance checks used 1.95.101.
The host was Apple silicon on macOS 26.6.2 with Swift 6.3.3.

| Check | Recorded result |
| --- | --- |
| Direct `Process`, cold and running Brave | Passed; cold GUI checks used an isolated test copy |
| Multiple open profiles; same site in two named containers | Passed in the test copy |
| Generated receiver; subsequent URL events; URL batches | Passed in the test copy |
| Saved rename and deletion | Followed rename; showed deletion error |
| Temporary containers | Fresh per event; one shared container for an explicit URL batch |
| App names, generated/custom icons and stable identity | Passed for v1.3.0; current changes need their own record |
| Developer ID distribution | Older ZIP signatures/tickets and fresh CLI downloads passed |
| Unmodified vendor Brave, final profile/container GUI assertion | Still required |
| Third-party switcher to generated app to Brave | Still required |
| Second Mac and normal browser-download first-open flow | Still required |
| Intel and macOS 14 runtime | Still required |

GUI automation selected the personal instance when bundle IDs matched. Routing
checks therefore used a copied Brave installation with a distinct bundle ID and
ad-hoc signature. They verified address bars, profile labels and container badges,
not cookie isolation. Forced termination of only the disposable process was needed
for cold checks; graceful session-restoration behavior remains unverified.

## Manual release matrix

Use a separate test data directory. Initialize two profiles in Brave. Enable
Containers and create two disposable named containers through Brave's UI. Never
edit preference files or close personal sessions for a test. Wait for `cbc list`
to reflect each edit.

1. Download the release DMG through a browser on a second Mac. Verify the checksum,
   mount it, drag Setup into Applications, eject, and open Setup normally.
2. Generate a named destination and a Temporary destination for each test profile.
   Verify the app names and icon previews. Add them through the switcher's custom
   application picker, or drag and drop if supported. Keep the switcher as default.
3. With the disposable Brave instance closed, route `https://example.com/?test=one#part`
   to a named app. Check address, profile window, container badge and foreground activation.
4. Repeat with Brave and the receiver already running, then with both profiles open.
5. Open the same site in both named containers. Inspect both badges.
6. Send two URLs to the receiver. Verify neither is lost. Use
   `swift scripts/probe-url-batch.swift RUNNING_TEST_RECEIVER_APP HTTP_URL HTTP_URL`
   for an explicit Apple-event batch;
   separate temporary events must get fresh containers, while one batch shares one.
7. Rename the disposable container in Brave, wait for saved preferences, and reuse
   the same generated app. It must follow the ID to the new name.
8. Delete that container, wait for saved preferences, and send another URL. Expect
   an error and no intentional fallback. Repeat with containers disabled.
9. Rename an app, select each generated icon and import a custom image. Save, remove
   the source image, then repeat a name-only update. Check routing identity and icon.
10. Repeat external link delivery through an actual browser switcher. Record its
    name/version. Test duplicate events and a second URL while an error alert is open.

Repeat on Intel and the minimum supported macOS version before claiming those
runtimes verified. After Brave upgrades, rerun routing checks against the installed
version, not its development branch. Do not publish private profile paths as evidence.
