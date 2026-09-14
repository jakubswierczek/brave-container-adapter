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

The artwork is included in local 1.1.2 packages. The existing 1.1.1 notarization
submission is unchanged. A release that includes the icon needs its own signing
and notarization pass.
