# Use the adapter

## Install on a Mac

1. Download `Brave-Container-Adapter.dmg` from [Releases](https://github.com/jakubswierczek/brave-container-adapter/releases/latest). While the repository is private, sign into an account with access.
2. Open the DMG. Drag **Brave Container Setup** into **Applications**. Eject the disk image, then open the app from Applications.
3. Initialize Brave and each profile you want to use. Enable **Settings > Content > Containers**. For named destinations, add or edit a container so Brave saves the configured list.
4. In Setup, click **Refresh**. Select a destination, enter an **App name**, choose an icon, then click **Install destination**.
5. Add the app revealed in Finder to your browser switcher. New apps are installed in `~/Applications/Brave Destinations/`.

Use **Choose Brave…** and **Choose data folder…** for nonstandard paths. The data folder must contain `Local State`. Do not select an individual profile folder.

Generate destination apps on each target Mac. They contain that Mac's paths and local destination configuration. The setup app contains no browser data and can be removed after generation. Generated apps work without the checkout or setup app.

The release DMG and setup app have Developer ID signatures and notarization tickets. A normal first-open confirmation can still appear. Locally built DMGs and generated destination apps use ad-hoc signing. See [signing](signing.md) and [troubleshooting](troubleshooting.md).

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

New apps go into `~/Applications/Brave Destinations/`. The setup picker shows the profile name and directory separately from the editable app name. The CLI includes profile information in its default label; use `--name 'Brave — Work'` to choose a shorter one. Filenames use that label without an automatic hash suffix. If a filename is taken, choose another name; unrelated apps are never overwritten. Apps from older releases update in their original folder.

To package without installing/registering:

```bash
dist/bin/cbc generate \
  --profile Default --container-id CONTAINER_ID \
  --output ./dist/apps
```

`install` registers each app with Launch Services but does not set it as a default handler. Bundles are ad-hoc signed locally, not Developer ID signed or notarized for distribution. Configuration is local plaintext with owner-only file permissions; do not upload generated bundles. Run the portable setup app on each target Mac, or build the CLI there, and generate apps for its own paths.

## Temporary containers

In the setup app, choose **Brave — Temporary (profile · directory)** and install it. Add that generated app to your browser switcher like any named destination. Requires Brave **1.95.101 or later**.

CLI equivalents:

```bash
dist/bin/cbc install --profile Default --temporary
dist/bin/cbc doctor --profile Default --temporary
dist/bin/cbc generate --profile Default --temporary --output ./dist/apps
```

Each incoming URL event creates a **fresh temporary container** in the selected profile. URLs received together in one batch share that container. Separate events get separate containers, even while the receiver and Brave remain open. A sender can split several links into individual events: macOS `open -a RECEIVER URL1 URL2` did so in testing. The adapter does not merge events or reuse a previous temporary container.

Brave chooses the container's random display name and manages its data. **Temporary does not mean incognito or erase-on-tab-close.** Brave can retain temporary records and data for session/tab restoration. Its startup cleanup removes containers without references from open tabs, the last session, or tab restore entries. The adapter neither deletes this data nor promises a cleanup deadline.

The generated app stores the temporary mode, installation, data path, and profile. It stores no ephemeral container ID or name. Saved enablement, metadata, and the installed Brave version are checked again before every request. A missing configured list is allowed; malformed metadata, disabled containers, missing profiles, or an unsupported version stop the request.

## Names and icons

The setup app lets you customize new or installed destination apps:

1. Select a destination, or click **Edit installed app…** and select an existing generated app.
2. Enter the desired **App name**. **Short name** uses the current container name without profile text. Saving removes old filename hashes; it does not rename the container in Brave.
3. Choose one of six locally generated icons: **Monogram**, **Work**, **Personal**, **Web**, **Layers**, or **Temporary**. The preview shows your choice. Monogram uses the first two letters of the app name after the standard Brave prefix.
4. Or click **Choose image…** to import PNG, JPEG, HEIC, TIFF, or ICNS. Images must be at most 32 MB and 16384 pixels per side. The image is fitted within a square without cropping. The app stores a normalized icon, not the source path or its metadata; the original image is no longer needed.
5. Click **Install destination** or **Save app**. Re-add the app to the switcher if its entry still shows the old name or icon.

CLI examples:

```bash
dist/bin/cbc install --profile Default --container-id CONTAINER_ID \
  --name 'Brave — Work' --icon work

dist/bin/cbc customize --app '/path/to/generated.app' \
  --name 'Brave — Personal' --icon personal

dist/bin/cbc customize --app '/path/to/generated.app' \
  --icon-file '/path/to/icon.png'
```

Use `--icon` or `--icon-file`, not both. When neither is supplied, updates keep the saved icon. Name-only changes also preserve custom icons. CLI updates keep the current filename unless `--name` is supplied; the setup app always applies the visible name when saving. Two different destinations can share a display name in different folders, but cannot use the same filename in one folder.

Appearance changes keep the installation, data directory, profile directory, container ID or temporary mode, and bundle identifier. Editing an installed app does not require its Brave installation to be available; the receiver validates routing when a URL arrives. All operations on Brave preferences remain read-only.

## Add apps to a browser switcher

1. Open the switcher's browser/application settings.
2. Use its application picker to select the generated `.app` in `~/Applications/Brave Destinations/`. If supported, drag the app from Finder into that list.
3. Add it as a custom application, rather than through a built-in Brave profile submenu.
4. Keep the switcher as your default browser. Do not make a generated destination the system default.
5. Open an external test link, select the destination, and verify the Brave profile and container badge.

The sender must support custom macOS apps and deliver standard HTTP/HTTPS URL events. A switcher that only accepts its own fixed browser list may need support from its developer. The adapter supplies no picker or routing rules of its own.

The adapter handles **links sent to its destination apps**. Ordinary navigation, page links, address-bar input, and new tabs inside an existing browser do not automatically pass through a system browser switcher.

## Update and uninstall

Rebuild, quit the destination's `ContainerReceiver` process in Activity Monitor, then repeat the original `install` command. Select the process whose executable is inside that destination app if several receivers run. The generator refuses to replace a running receiver. Older generated apps are recognized by their unchanged bundle IDs and can be selected with **Edit installed app…**. It locks the output directory, stages and verifies the new bundle, then swaps it atomically. Unrelated apps and symlinks are not overwritten.

Named destination identity is a SHA-256 digest of the canonical installation path, data path, profile directory, and container ID. Temporary identity uses the same paths/profile plus a separate temporary-mode identity. Existing named configuration (format 1) and bundle IDs are unchanged; temporary apps use format 2. Old receivers reject the new format. Changing only a container or profile display name preserves identity. Launches follow a renamed container without regeneration after its new name is saved; regenerate to refresh the label. CLI updates preserve filenames unless `--name` is supplied. Setup saves use the visible app name, without a hash suffix. A switcher may need its app entry refreshed after a filename or icon change. A moved installation/data directory or recreated container is a new destination; remove the old switcher entry and app.

To uninstall, remove the entry from the switcher's application list, quit its receiver in Activity Monitor, and move the generated app to Trash. Remove `dist/bin` if you no longer need the CLI. The adapter installs no login item, daemon, backend, or browser extension. Uninstalling an app does not delete its Brave profile or container.
