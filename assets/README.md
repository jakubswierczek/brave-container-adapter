# Setup app icon

`SetupIcon.png` is the source artwork for Brave Container Setup. Orange, violet,
and teal browser cards represent containers; the white chain represents links.
The artwork was generated with the built-in image generation tool. It uses no
official Brave logo. The prompts are recorded in `icon-prompts.md`.

`scripts/package-setup.sh` uses macOS `sips` and `iconutil` to generate the standard
16, 32, 128, 256, and 512 point icon representations at 1x and 2x. It embeds
`SetupIcon.icns` and declares `CFBundleIconFile` before signing the bundle.
Run that script to build an app containing the icon; extract the ZIP in `dist/`
to inspect the packaged resource. Destination apps retain their individual
generated labels and icons.

The artwork is included in the signed and notarized
[v1.1.2 release](https://github.com/jakubswierczek/choosy-brave-containers/releases/tag/v1.1.2).
It received a separate notarization approval; the v1.1.1 artifact is unchanged.

Destination icons are rendered locally by `DestinationIcons.swift`: a monogram
or one of five SF Symbols on a colored tile. No service or account is required.
Imported images are rasterized into a self-contained ICNS file with transparent
padding and no source path. The setup app previews either choice before saving.
