# Version 1.4.0 verification

Date: 2026-09-14. Local host: Apple silicon, macOS 26.6.2 (25G83),
Xcode 26.6 (17F113), Swift 6.3.3. Browser: unmodified vendor Brave 1.95.101,
Chromium 153.0.8010.37. Switcher: Choosy 2.5.2 official trial.

## Automated checks

49 Swift tests and process-level CLI checks pass locally. Coverage includes profile
and container discovery, rename/deletion, URL preservation, queue limits, special
and oversized files, running-owner validation, tool timeout/cancellation, failed
updates and recovery. Release builds pass. Repository links, shell syntax, file
hygiene and the instruction symlink pass.

CI runs the same checks on macOS 14, macOS 15 and Intel macOS 15. macOS 14 selects
Xcode 16.2 because the runner's default Xcode still provides Swift 5.10. The stable
`checks` job depends on all three jobs. CI also packages a universal DMG on macOS 15.
Passing synthetic tests on those runners does not certify Brave routing there.

The first matrix run exposed delayed directory-lock release during parallel process
starts. The fix explicitly unlocks before closing the descriptor, so a child in the
fork-to-exec interval cannot prolong ownership. The existing repeated-update tests
exercise that failure. All three matrix jobs and the aggregate check passed in [run 34857596300](https://github.com/jakubswierczek/brave-container-adapter/actions/runs/34857596300) for `b3f3a05fd9b36353cc09a47d772853e495d8bf6b`. The final release notes also identify the packaging source commit.

## GUI and browser integration actually performed

Used a new disposable user-data directory. Created a second profile and enabled,
created, renamed and deleted containers only through Brave's UI. The owner approved
briefly quitting personal Brave. It was reopened after the checks. No personal
profile was used as a fixture; no cookies/history were read. HTTP/HTTPS defaults
were Safari before and after. Choosy's explicit prompt API exercised the picker
without changing the default browser or buying a license.

| Check | Result |
| --- | --- |
| Vendor build and profile | `brave://version` showed Official Build 1.95.101 and the disposable `Default` path |
| Choosy application discovery | The generated app appeared in Browsers → + and in the actual picker |
| Cold handoff through Choosy | With no Brave process running, the picker opened the neutral URL with the `Adapter Alpha` badge; query/fragment survived and Brave became active |
| Running handoff through Choosy | A second picker request opened the same container while Brave and the receiver were running |
| Multiple profiles | Named apps selected `Personal`/`Default` and `Adapter Second`/`Profile 1`; returning to the first app selected its original profile |
| Same site, different containers | `example.com` opened with `Adapter Alpha`, `Work` and second-profile `Adapter Beta` badges |
| Explicit two-URL batch | Both neutral URLs appeared as separate tabs in `Adapter Alpha`; inspected each address |
| Temporary mode | Separate events displayed different generated names; two URLs in one event displayed the same new container name |
| Saved rename | The original shortcut followed the same ID to `Adapter Renamed`; the browser was restarted after the saved edit |
| Saved deletion | The original shortcut showed the deleted-container error; retained records did not permit a launch |
| Event during modal error | A two-URL event sent while a disabled-fixture alert was open was processed after dismissal, producing its own resolution error |
| Setup UI | Synthetic two-profile discovery, name editing, preset selection/preview, installation, status and accessibility labels inspected |
| Keyboard editing | Found and fixed missing Edit menu; Cmd+A then typing correctly replaced the app name |
| Test cleanup | Removed the generated test apps and picker entries; reopened personal Brave |

The vendor check exposed a hostname mismatch: Foundation's DNS name differed from
Chromium's POSIX hostname. The owner probe now uses `gethostname`; a system-level
regression test verifies a Chromium-format lock resolves the current process.

GUI checks used the 1.4.0 candidate before the later directory-unlock change. That
change affects packaging synchronization, not routing. Tests and release packaging
cover it separately. The UI tool returned stale settings-menu trees after Brave
saved container edits; restarting only the disposable instance restored inspection.
No final-tab check was inferred from process exit status or from stale UI output.

## Still required

- Second Mac: browser-download quarantine, normal first open, generation and switcher
  handoff. The owner agreed to perform this check; no result has been supplied yet.
- Actual browser handoff on Intel and minimum macOS. CI verifies adapter runtime logic
  there, not browser UI.
- Full VoiceOver and keyboard-only navigation pass. Standard editing shortcuts and
  accessibility labels were checked, but this is not a complete accessibility audit.
- The final package's acceptance, tickets, checksum and fresh download belong in the
  release notes. Do not infer notarization from the version number or filename.

The adapter still has the documented saved-preferences/name-routing race. It cannot
verify cookie isolation or Brave's final tab through a supported public acknowledgment.
