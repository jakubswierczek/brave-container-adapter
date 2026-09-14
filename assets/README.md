# Icons and provenance

`SetupIcon.png` is the source artwork for Brave Container Setup. Orange, violet and
teal browser cards represent containers; the white chain represents links. The
artwork was generated with the built-in image generation tool. The recorded prompts
are in [icon-prompts.md](icon-prompts.md). No official Brave logo was requested.

`scripts/package-setup.sh` uses macOS `sips` and `iconutil` to generate 16, 32, 128,
256 and 512 point representations at 1x and 2x. It embeds `SetupIcon.icns` before
signing. Open the generated DMG to inspect the packaged app.

Destination presets are rendered locally as colored letter tiles by
`DestinationIcons.swift`: a destination monogram, WK, ME, WEB, LYR or NEW. They use
no SF Symbols. Version 1.3.0 used SF Symbols in destination icons; v1.3.1 replaces
those presets because [Apple prohibits their use in app icons](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).
Existing generated apps get the new preset artwork when saved with the new setup app.
Custom imports remain unchanged unless the user chooses another icon.

Imported images are rasterized into a self-contained ICNS file with transparent
padding and no source path. Users must have permission to use their chosen artwork.
No imported user artwork is part of this repository.

The owner confirmed publication rights for code and project-owned artwork on
2026-09-14. Project-owned artwork is covered by the [MIT license](../LICENSE).
This grant does not include third-party trademarks or user-imported images.
