# Integration record

Date: 2026-09-11. macOS 26.6.2, arm64, Swift 6.3.3, Brave 1.92.140 (Chromium 150.0.7871.125).

## Test boundary

The initial direct `Process` probe used `/Applications/Brave Browser.app` and a new isolated user data directory. The GUI automation tool selected the existing personal Brave process when two instances shared a bundle identifier. To inspect routing without closing or changing that personal instance, the GUI tests used a copy of the installed application with a different bundle identifier and an ad-hoc signature. No newer Brave build was downloaded. The test copy was not an unmodified vendor-signed installation.

All container creation, enablement, renaming, and deletion occurred through Brave's UI in isolated test profiles. Preferences were only read by the adapter. No production remote-debugging port, cookies, or browsing history were read. Neutral `example.com` URLs were used. Routing evidence is the address bar, container badge, and profile window label; it is not a test of network page content or cookie isolation.

The GUI tool occasionally retained a stale settings-menu accessibility tree after a container edit. The disposable browser also did not exit after quit/SIGTERM attempts. Its process alone was stopped with SIGKILL for cold checks. The personal Brave process was left running. This is a **cold process-start test**, not proof of graceful shutdown/session restoration.

## Automated checks

`scripts/test.sh`: 24 Swift Testing tests, including parameterized URL, disabled-state, malformed-data, and installation-version cases. Coverage includes profile directory/display-name separation, configured vs retained records, ID resolution, rename, deletion, duplicate names/IDs, missing/default metadata, malformed files, deterministic recovery from a partial file replaced between read attempts, unsafe profile paths, all four identity dimensions, argument construction, URL preservation/rejection, redacted launch failure, standalone bundle structure/signing, atomic idempotent updates, and unrelated-app preservation.

`scripts/build.sh`: debug/test and optimized release builds succeeded. `codesign --verify --strict` succeeded for generated/installed bundles. `otool -L` on the receiver showed system framework/Swift dependencies, with no checkout/build-directory library dependency.

The final installed Work app also launched its bundled receiver while the release, debug, and `dist/bin` receiver binaries were temporarily hidden. Process inspection confirmed that it activated the standard Brave executable. The source binaries were restored after this check. Repeating installation preserved the two app paths and identities.

## Live checks performed

| Check | Result and evidence |
| --- | --- |
| `Process` direct invocation | Passed on installed 1.92.140 binary; separate executable path and argument array, no shell construction |
| Cold process → named container | Passed in the isolated test copy: `example.com` address and Work badge |
| Already-running Brave → named container | Passed: a later `Process` invocation opened a Work tab in the same test instance |
| Multiple profiles open | Passed: `Default` window labeled Personal and `Profile 1` window labeled Person 1 each received Work when explicitly selected |
| Same site, different containers | Passed: `example.com` had a Work badge and, in a separate tab, a Personal badge |
| Generated app → Brave | Passed through macOS URL delivery to a release receiver app, then direct `Process` to the test copy |
| Multiple URLs | Passed: one `open -a RECEIVER_APP URL1 URL2` produced both tabs; addresses `?cbc=one#first` and `?cbc=two#second` were inspected |
| Receiver already running | Passed: another URL event produced `?cbc=resident#third` with Work badge |
| Container renamed, same app | Passed after preferences saved: app created for Adapter Test opened Adapter Renamed, with the renamed badge verified after restarting only the test browser |
| Container deleted, same app | Passed after preferences saved: native receiver alert stated the container was deleted/no longer configured; it did not intentionally launch a fallback |
| Window visibility/profile | Passed for the above test-copy GUI cases; requested profile window and badge were visible |
| Final installed apps | Work and Personal test apps installed under `~/Applications/Choosy Brave Containers/`; signature and saved destination resolution checked. Native process inspection confirmed the standard `/Applications/Brave Browser.app` executable owned the persistent isolated data directory and became active after delivery |
| Final standard-installation badge | Not GUI-verified: the automation tool again selected the existing personal process. Do not equate registration/process creation with a badge assertion |
| Choosy → generated app → Brave | **Not run.** Choosy was absent from standard app directories, user Applications, preference panes, Spotlight, and available UI apps. HTTPS default was Safari and was left unchanged |

No personal destinations were invented. The normal profile had no explicit enabled/container list preferences. The two installed demonstration apps use isolated test data at `~/Library/Application Support/Choosy Brave Containers/Integration Data`. They do not use personal browser sessions. To remove that test environment later, quit its Brave instance and receivers, trash the two test apps, and trash this isolated data directory. Do not remove Brave's standard data directory.

## Remaining manual verification

1. Open each installed test app with a neutral URL. Verify the Work/Personal badge in the window using the isolated data directory. Use `brave://version` in that window to verify **Profile Path**, without sharing the whole page or private path.
2. In the real profile, enable Containers in Settings > Content and create/edit the desired containers in Brave's UI. Wait until `cbc list` reflects them, then run `cbc install --all --profile DIRECTORY` for that profile. Do not use the test apps as personal-session destinations.
3. Open Choosy > Browsers. Drag generated apps from `~/Applications/Choosy Brave Containers/`, or use **+** and browse for each application. Keep Choosy as the default browser on the machine where it is installed.
4. Open an external `https://example.com/?choosy=check#fragment` link. Select one destination in Choosy. Confirm the correct profile, the exact container badge, and the query/fragment. Repeat while that receiver is already running.
5. Repeat with two initialized profiles open and Work/Personal containers for the same site. Check each destination's badge and window.
6. For a complete rerun, use a separate test data directory and initialize it through Brave. The probe is `swift scripts/probe.swift BRAVE_APP TEST_DATA PROFILE_DIRECTORY CONTAINER_NAME`. Enable and configure containers only through the test UI. Test a cold process, a running process, a URL batch, then rename and delete a disposable container. Wait for `cbc list` after each edit. The old generated app must follow the saved rename and show an error after saved deletion.

After Brave/macOS/Choosy upgrades, repeat the routing checks. The gap between saved preference validation and Brave's in-memory launch handling remains unverified by design; see the README's limitations. macOS 14 and Intel hardware were not available for runtime testing.

## Portable setup app

The universal setup ZIP was extracted outside the checkout and launched on the Apple silicon test Mac. Its empty-state message and disabled install button were checked against the standard data location. Selecting the isolated test data folder discovered four configured destinations. Selecting Social and clicking Install destination generated a standalone app and revealed it in Finder. Its signature and both receiver architectures were verified. The temporary Social app was removed after this check.

Both setup and bundled receiver compile for arm64 and x86_64; packaging checks both slices and the app signature. The 24 automated tests pass with the setup target included. The artifact contains no destination configuration or browser preferences. No Intel runtime, second Mac, downloaded-file Gatekeeper approval, or Choosy interaction was available for testing. Follow the README's target-Mac steps to complete those checks.

## Developer ID release, 2026-09-14

The v1.1.1 setup app and embedded receiver were signed with a valid individual Developer ID Application identity. Both signatures have secure timestamps and Hardened Runtime enabled. Strict signature verification passed, and both executables contain arm64 and x86_64 slices. The 24 automated tests passed again. The build ZIP was checked for browser configuration and private build paths; none were found.

The signed setup app launched from a copy outside the checkout. Process inspection confirmed that executable's path. The native GUI discovered four configured destinations in the isolated test data and installed Social successfully. The generated destination's local signature was verified, then the temporary destination was removed. This does not replace the still-missing Choosy and second-Mac checks.

Notarization submission `931511ca-ffa1-4763-98d2-854823150a5e`, created at `2026-09-14T08:55:55Z`, was observed as `Accepted` about 57 minutes after submission. Apple's log reports `Ready for distribution` with no issues. The original script stopped waiting after 30 minutes; processing continued at Apple. The existing signed app was used to finish the same submission without rebuilding or re-signing.

Apple's ticket was attached and validated. Strict signature verification passed for the app and embedded receiver. Gatekeeper accepted the app as `Notarized Developer ID`. A fresh extraction of the final ZIP passed the same ticket and signature checks, verified version 1.1.1, and passed the browser-data/private-path archive scan. The notarized ZIP and SHA-256 file are published in [v1.1.1](https://github.com/jakubswierczek/choosy-brave-containers/releases/tag/v1.1.1), built from `cd0ee22ba8b3e379d82a956972401309f89373b8`.

The published assets were downloaded again with the GitHub CLI. The checksum,
attached ticket, both signatures, and Gatekeeper assessment passed. A CLI
download does not reproduce a browser download's first-open quarantine flow.

## Icon release v1.1.2, 2026-09-14

The setup icon was included in a new universal build from
`2fc88128590e48a72c6e7774286c1210a14454af`. Submission
`97a1c889-9a66-48de-a0fc-b7b361f0a2fc` was created at
`2026-09-14T10:52:27Z`; the wait command returned `Accepted` about 19 seconds
later. Apple's report contains no issues. This timing does not guarantee faster
processing for future releases.

The final ZIP passed ticket validation, strict signatures for both executables,
Gatekeeper acceptance as `Notarized Developer ID`, and the browser-data/private-
path archive scan. Both executables contain arm64 and x86_64 slices. Version
1.1.2/build 4 declares `SetupIcon`; the packaged icon decodes into ten standard
and Retina RGBA representations. The artwork was inspected at 32 and 128 pixels.
Routing code is unchanged from the v1.1.1 test run.

The ZIP and checksum are published in
[v1.1.2](https://github.com/jakubswierczek/choosy-brave-containers/releases/tag/v1.1.2).
Downloading those assets with the GitHub CLI reproduced the checksum, ticket,
signature, and Gatekeeper results, and confirmed the icon declaration and version.
First opening a downloaded app on another Mac, Choosy delivery, and Intel runtime
remain manual checks.
