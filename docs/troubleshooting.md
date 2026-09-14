# Troubleshooting

## Diagnose routing

```bash
dist/bin/cbc doctor --profile Default --container-id CONTAINER_ID
dist/bin/cbc doctor --app '/path/to/generated.app'
```

`doctor` is read-only. It validates installation, metadata, feature-disable flag, and identity, and reports the current HTTPS default. It does **not** send a URL or certify GUI routing.

Check these in order:

1. Installation and data paths still exist; the chosen profile was already initialized in Brave.
2. Containers is enabled in Settings. If `brave://flags/#containers` explicitly disables the feature, enable it there and relaunch Brave. The adapter does not change flags or force-enable features on a running process.
3. For a named destination, `list` contains the ID and its current name. For Temporary, Brave is at least 1.95.101 and saved enablement is true. Wait for UI edits to reach disk.
4. For a named destination, no two configured containers in the profile have that name.
5. No other Brave installation owns the same user data directory.
6. Test delivery to the app independently of the browser switcher:

   ```bash
   open -a '/path/to/generated.app' 'https://example.com/?check=one#part'
   ```

   This sends a URL event to the **receiver**, which then invokes Brave directly. Verify the profile and badge in Brave. A successful `open`, `Process.run`, or zero process exit status alone does not prove correct routing.


## Common failures

| Symptom | Action |
| --- | --- |
| No named destinations | Enable Containers, then add/edit one in Brave. Wait for saved preferences. Runtime defaults alone are not enough. |
| Temporary is unavailable | Requires Brave 1.95.101+, initialized profile, and explicitly saved container enablement. |
| Container deleted or duplicate name | Fix the configuration in Brave's UI. The adapter cannot choose an ambiguous target. |
| Wrong installation owns data | Quit the other test instance or choose its matching installation. Do not run two installations against one data directory. |
| Receiver is running | Quit the matching destination's `ContainerReceiver` in Activity Monitor before updating. |
| Old name/icon in switcher | Remove its cached entry and add the generated app again. |
| Setup is blocked by Gatekeeper | Use the current release DMG and check its checksum. Report the exact macOS dialog and version. Do not disable Gatekeeper globally. |
| `Testing` module missing | Run [tests with full Xcode](development.md). Do not change global `xcode-select` for this project. |

For a trusted local build, Apple's [Open Anyway procedure](https://support.apple.com/en-us/102445) may be needed. This is not a substitute for verifying a downloaded release.

Do not paste full URLs, query parameters, browser preference files, or private paths into an issue. `list` and `doctor` show profile/container metadata; redact it before sharing. Provide app version, macOS version, Brave version, destination mode, and a neutral `example.com` reproduction.

A successful process exit does not prove container routing. Check the profile path locally and inspect the container badge. See [routing limits](architecture.md#limits-and-guarantees).
