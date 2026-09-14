# Choosy Brave Containers

Generate standalone macOS apps that send HTTP and HTTPS links to one Brave installation, user data directory, profile, and either a saved container or a fresh temporary container. Add those apps to **your existing Choosy picker**.

Each app contains the same native Swift receiver and its own destination configuration, icon, label, and stable bundle ID. It invokes Brave's executable directly with `Process`; there is no shell, backend, separate picker, rules engine, or remote-debugging port.

## Requirements and tested status

- macOS 14 or later. Built and tested on macOS 26.6.2, Apple silicon.
- The downloadable setup app includes Apple silicon and Intel binaries. No Swift or Xcode installation is needed to run it. Intel and macOS 14 runtime behavior have not been tested.
- Building from source requires Swift 6.0+; tests require Xcode with Swift Testing. Tested with Swift 6.3.3.
- Brave with working Containers support. Named routing requires **1.92.140+**. Temporary routing requires **1.95.101+** and was tested against the installed `153.1.95.101` macOS bundle. The original named-routing checks used 1.92.140. Repeat live routing checks after upgrades.
- Containers enabled in **Brave Settings > Content > Containers**, with enablement saved to disk. Named destinations also require a saved container list. Create/edit containers only in Brave's UI.
- Choosy for the picker. No changes to the system default browser are made by this project.

The local environment had no discoverable Choosy installation and reported Safari as its HTTPS default. Choosy delivery has **not** been verified. See [the integration record](docs/integration.md) for exactly what was tested and what remains manual.

## Use on another Mac

1. On the target Mac, sign into the GitHub account that can access this private repository. Download `Brave-Container-Setup-notarized.zip` from [Releases](https://github.com/jakubswierczek/choosy-brave-containers/releases/latest). It includes Apple silicon and Intel binaries. The older v1.1.0 release uses the ad-hoc signed `Brave-Container-Setup-universal.zip` instead.
2. Extract the ZIP, move **Brave Container Setup.app** to Applications, and open it. Requires macOS 14 or later.
3. Install and initialize Brave and Choosy on that Mac. Enable Containers in Brave Settings > Content and let Brave save its settings. For named destinations, also add or edit a container.
4. In the setup app, click **Refresh**, select a named container or **Temporary** for the desired profile, then **Install destination**. Repeat for each destination. For nonstandard locations, use **Choose Brave…** and **Choose data folder…**; select the data folder containing `Local State`.
5. Finder reveals the generated app in `~/Applications/Choosy Brave Containers/`. Drag it into **Choosy > Browsers**, or use Choosy's **+** application picker. Keep Choosy as the default browser.
6. Open an external `https://example.com` link. Select the destination in Choosy and check the profile and container badge in Brave.

The setup ZIP contains code and documentation, with no browser data or destination configuration. It discovers paths and containers on the Mac where it runs. **Transfer the setup app, not destination apps generated on another Mac.** You can quit or remove the setup app after installation; destination apps are standalone.

The `-notarized.zip` distribution contains a Developer ID signed setup app with Apple's notarization ticket attached. A normal first-open confirmation may still appear. The older v1.1.0 download and default local package builds are ad-hoc signed; those may need [Apple's Open Anyway procedure](https://support.apple.com/en-us/102445). Only approve artifacts obtained from this repository. Do not disable Gatekeeper globally.

For release signing, see [signing and notarization](docs/signing.md). The release script requires a local company or individual signing identity and saved notarization credentials. Destination apps generated on your Mac retain local ad-hoc signatures; they do not inherit the setup app's notarization ticket.

To update, download the newer setup app, quit the relevant destination receiver in Activity Monitor, and install the same destination again. Its bundle identity and existing filename stay stable. Container renames need no update for routing; reinstall to refresh the label.

## Build and test

```bash
scripts/test.sh
scripts/build.sh
dist/bin/cbc help
# Optional: package the portable GUI for both Mac architectures
scripts/package-setup.sh
```

The scripts select `/Applications/Xcode.app` for that invocation if `DEVELOPER_DIR` is unset. They do not change `xcode-select`. Apple's standalone Command Line Tools can build the executables but may omit the `Testing` module. For a different Xcode installation:

```bash
DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer scripts/test.sh
```

The build places `cbc` and `ContainerReceiver` together in `dist/bin`. Keep them together when moving the CLI, or specify `--receiver /absolute/path/to/ContainerReceiver`. Generated apps copy the receiver into `Contents/MacOS`; they do not depend on `dist`, `.build`, or this checkout. Runtime dependencies are system frameworks and Swift libraries.

## Discover profiles and containers

```bash
dist/bin/cbc list
dist/bin/cbc list --profile 'Profile 1'
dist/bin/cbc doctor
```

Standard locations:

- Installation: `/Applications/Brave Browser.app`
- Data: `~/Library/Application Support/BraveSoftware/Brave-Browser`

Every discovery/generation command accepts overrides:

```bash
dist/bin/cbc list \
  --brave '/Applications/Brave Browser.app' \
  --user-data-dir "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"
```

`Local State` → `profile.info_cache` supplies the profile **directory key** and display name. Pass `Default` or `Profile 1` to `--profile`, not a display name such as `Personal`.

The selected profile's `Preferences` contains nested `brave.containers` data:

| Key | Meaning |
| --- | --- |
| `enabled` | Explicit saved enablement; this adapter requires `true` |
| `list` | Configured containers, each with `id`, `name`, integer `icon` and `background_color` |
| `used` | Dictionary keyed by ID; retained local snapshots, including potentially deleted containers |

Only configured entries become named destinations. Temporary mode creates a fresh container; retained temporary IDs are never offered as reusable destinations. Retained entries are counted separately. A retained-only ID is rejected. Brave searches configured names before retained names, so a retained name does not shadow a configured destination. Duplicate **configured** names block that name's launch; duplicate IDs or malformed records block discovery.

### Built-in containers and delayed saves

Brave may show its built-in Personal/Work/Social/School containers while `list` is absent from the file. These are localized runtime defaults, not evidence that `used` is the configured list. **Add a container or edit and save one in Brave's UI**, then wait until `cbc list` shows the configured entries. The adapter does not guess localized names or synthesize default records. Temporary mode does not need a saved `list`. Both modes require explicit saved `enabled: true`, even if a Brave experiment enables the UI by default.

Brave writes preferences asynchronously. `cbc list` shows the saved state, which can lag the UI. After changing container settings, wait for the new state to appear before opening links. Close/reopen the test browser if a save does not appear. The reader retries failed, partial, or changing file reads three times; it never writes these files.

## Generate and install

Copy a container ID from `list`:

```bash
dist/bin/cbc install --profile Default --container-id CONTAINER_ID
```

Or install all enabled, saved **named** destinations (`--all` does not add Temporary):

```bash
dist/bin/cbc install --all
dist/bin/cbc install --all --profile 'Profile 1'
```

Apps go into `~/Applications/Choosy Brave Containers/`. Labels include the container, profile display name, and directory key, for example `Brave — Work (Personal · Default)`. Filenames include a short destination hash to avoid collisions. Use `--name 'Brave — RMPL (Work profile)'` for a custom single-destination label.

To package without installing/registering:

```bash
dist/bin/cbc generate \
  --profile Default --container-id CONTAINER_ID \
  --output ./dist/apps
```

`install` registers each app with Launch Services but does not set it as a default handler. Bundles are ad-hoc signed locally, not Developer ID signed or notarized for distribution. Configuration is local plaintext with owner-only file permissions; do not upload generated bundles. Run the portable setup app on each target Mac, or build the CLI there, and generate apps for its own paths.

## Temporary containers

In the setup app, choose **Brave — Temporary (profile · directory)** and install it. Add that generated app to Choosy like any named destination. Requires Brave **1.95.101 or later**.

CLI equivalents:

```bash
dist/bin/cbc install --profile Default --temporary
dist/bin/cbc doctor --profile Default --temporary
dist/bin/cbc generate --profile Default --temporary --output ./dist/apps
```

Each incoming URL event creates a **fresh temporary container** in the selected profile. URLs received together in one batch share that container. Separate events get separate containers, even while the receiver and Brave remain open. A sender can split several links into individual events: macOS `open -a RECEIVER URL1 URL2` did so in testing. The adapter does not merge events or reuse a previous temporary container.

Brave chooses the container's random display name and manages its data. **Temporary does not mean incognito or erase-on-tab-close.** Brave can retain temporary records and data for session/tab restoration. Its startup cleanup removes containers without references from open tabs, the last session, or tab restore entries. The adapter neither deletes this data nor promises a cleanup deadline.

The generated app stores the temporary mode, installation, data path, and profile. It stores no ephemeral container ID or name. Saved enablement, metadata, and the installed Brave version are checked again before every request. A missing configured list is allowed; malformed metadata, disabled containers, missing profiles, or an unsupported version stop the request.

## Add apps to Choosy

1. Open Choosy settings and select **Browsers**.
2. In Finder, open `~/Applications/Choosy Brave Containers/`.
3. Drag the desired `.app` files into Choosy's browser list. Alternatively click **+**, choose the option to browse for an application, and select each generated app.
4. Keep Choosy as your default browser. Do not select a generated destination as the system default.
5. Open an external test link, select the destination, and verify both the Brave profile and container badge.

These steps follow [Choosy's application-picker documentation](https://choosy.app/help/settings/browsers). The generated app is an application entry; it is not added through Choosy's Brave profile submenu.

The adapter handles **links routed through Choosy**. Ordinary navigation, page links, address-bar input, and new tabs inside an existing browser do not automatically pass through Choosy.

## URL delivery and errors

The app declares HTTP/HTTPS URL handling and runs as an AppKit accessory app. It has no normal window or persistent Dock icon. It stays resident until quit/logout so an idle timeout cannot discard a late URL event. Multiple events and batched URLs are supported; repeated URLs are not deduplicated. Incoming events received during an error alert are queued.

The receiver validates the entire incoming batch, loads its destination, and reads the latest saved preferences. For a named destination, it resolves the configured ID to its current name and constructs:

```text
/path/to/Brave.app/Contents/MacOS/Brave Browser
  --user-data-dir=/path/to/data
  --profile-directory=Default
  --container=Current Name
  --
  https://example.com/...
```

For Temporary, `--temporary-container` replaces `--container=Current Name`. It never sends both switches; a container name would make Brave reuse a named temporary container.

These are separate `Process.arguments` elements, not a shell command. `open -a Brave --args` is not used. Brave handles its existing-instance handoff. The adapter also checks the data directory's singleton owner and rejects a different running installation. Activation targets that browser process after the handoff; a live check must still confirm the intended profile window.

HTTP/HTTPS text from raw URL Apple events is passed unchanged after validation, including percent escapes, Unicode, queries and fragments. AppKit-batched URLs use the representation AppKit supplies; the adapter cannot undo normalization already performed by a sender or macOS. Unsupported schemes, invalid escapes, whitespace/control characters, and empty hosts are rejected. Batches larger than the conservative 128 KiB argument budget are rejected with an error; split them into smaller batches.

Errors appear in a native alert. The CLI prints metadata diagnostics to the terminal. Neither logs incoming URLs or query values. Brave stdout/stderr are suppressed. `list` and `doctor` intentionally display local profile/container names and IDs; review those before sharing diagnostics. Normal OS process inspection can see command-line arguments, and Brave itself handles the URLs as usual.

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
6. Test delivery to the app independently of Choosy:

   ```bash
   open -a '/path/to/generated.app' 'https://example.com/?check=one#part'
   ```

   This sends a URL event to the **receiver**, which then invokes Brave directly. Verify the profile and badge in Brave. A successful `open`, `Process.run`, or zero process exit status alone does not prove correct routing.

## Update and uninstall

Rebuild, quit the destination's `ContainerReceiver` process in Activity Monitor, then repeat the original `install` command. Select the process whose executable is inside that destination app if several receivers run. The generator refuses to replace a running receiver. It locks the output directory, stages and verifies the new bundle, then swaps it atomically. Unrelated apps and symlinks are not overwritten.

Named destination identity is a SHA-256 digest of the canonical installation path, data path, profile directory, and container ID. Temporary identity uses the same paths/profile plus a separate temporary-mode identity. Existing named configuration (format 1) and bundle IDs are unchanged; temporary apps use format 2. Old receivers reject the new format. Changing only a container or profile display name preserves identity. Launches follow a renamed container without regeneration after its new name is saved; regenerate to refresh the label. Existing app filenames are preserved during updates so Choosy's application reference remains usable. A moved installation/data directory or recreated container is a new destination; remove the old Choosy entry and app.

To uninstall, remove the entry from Choosy's Browsers list, quit its receiver in Activity Monitor, and move the generated app to Trash. Remove `dist/bin` if you no longer need the CLI. The adapter installs no login item, daemon, backend, or browser extension. Uninstalling an app does not delete its Brave profile or container.

## Limits and guarantees

- Discovery depends on **Brave's internal preference storage format**, not a supported external API. Future Brave changes may require an adapter update.
- Named routing currently relies on **container names**, even though destination configuration stores an ID. Temporary routing uses the bare `--temporary-container` switch. The inspected implementation compares names exactly and uses the first matching configured record.
- There is an unavoidable gap between saved-file validation and Brave processing the request. In-memory state can differ from disk; flags, profile selection, container names, deletion, or enablement can change during that gap. A missed name can cause Brave itself to open an ordinary tab or use a retained record. The adapter never intentionally selects a fallback, but **cannot guarantee isolation across this race or verify the final tab**. This is not a security boundary. After changes, wait for saved state; verify badges before sensitive browsing.
- Temporary containers follow Brave's retention and restoration rules. Closing their last tab does not guarantee that data is erased.
- Effective feature rollout/command-line overrides cannot be fully inferred from saved files. Explicit `containers@2` is rejected, but a contradictory running-process flag or future rollout change still needs a GUI check.
- Browser startup/onboarding, a profile picker, crash recovery, a locked profile, or a broken Brave process can interrupt handoff. Initialize each profile manually before generating apps. The CLI does not read cookies, history, or internal Mojo settings interfaces.
- Native UI tests used an isolated copy of the installed Brave binary with a distinct bundle identifier and ad-hoc signature, because the GUI tool otherwise selected the personal instance. See the integration record for this test boundary.

## Source references

The original named integration used the **1.92.140 tag**. Temporary support was checked against the installed **1.95.101 tag**, not `main`:

- [Startup command-line container handling](https://github.com/brave/brave-core/blob/v1.92.140/browser/ui/startup/brave_startup_tab_provider_impl.cc)
- [Preference keys](https://github.com/brave/brave-core/blob/v1.92.140/components/containers/core/browser/pref_names.h) and [serialization](https://github.com/brave/brave-core/blob/v1.92.140/components/containers/core/browser/prefs.cc)
- [Configured-first runtime lookup](https://github.com/brave/brave-core/blob/v1.92.140/components/containers/core/browser/containers_service.cc)
- [Preference defaults](https://github.com/brave/brave-core/blob/v1.92.140/components/containers/core/browser/prefs_registration.cc) and [localized default containers](https://github.com/brave/brave-core/blob/v1.92.140/components/containers/core/browser/default_containers_list.cc)

- [Temporary command-line contract](https://github.com/brave/brave-core/blob/v1.95.101/components/containers/core/browser/command_line_container.h) and [implementation](https://github.com/brave/brave-core/blob/v1.95.101/components/containers/core/browser/command_line_container.cc)
- [Temporary container lifecycle](https://github.com/brave/brave-core/blob/v1.95.101/components/containers/core/browser/containers_service.cc) and [tab/session references used for cleanup](https://github.com/brave/brave-core/blob/v1.95.101/browser/containers/containers_service_delegate.cc)
