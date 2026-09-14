# Repository instructions

## Scope

Build standalone macOS destinations for Brave profiles and containers. Support
browser switchers that accept custom applications. Keep the architecture small:
shared Swift code, an AppKit receiver, a setup app, and a CLI. No backend or picker.

Read [architecture](docs/architecture.md) before changing routing or identity.
Read [testing](docs/testing.md) before claiming integration coverage.

## Invariants

- Brave preferences are read-only. Use synthetic fixtures or disposable profiles.
- Never read personal cookies/history or use a production remote-debugging port.
- Store container IDs. Resolve the current configured name immediately before launch.
- Reject disabled, deleted, malformed or ambiguous destinations. No intentional fallback.
- Invoke an executable with `Process.arguments`; never build a shell command from input.
- Preserve HTTP/HTTPS URL text. Never log complete URLs or query parameters.
- Do not change the default browser. No browser-data writes to create containers.
- Preserve configuration formats, bundle IDs and the legacy install-folder lookup.
  The `app.choosy-brave-containers` prefix is a compatibility contract.
- Generated apps must work without the checkout or build folder. Preserve unrelated apps.
- Keep custom icons self-contained. Do not use SF Symbols in application icons.

## Work and checks

- Use Swift 6 and macOS 14-compatible APIs. No dependency without a concrete need.
- Keep pure validation separate from filesystem, process and UI effects.
- Add meaningful tests for changed behavior. Use fixtures under `Tests/`.
- Run `scripts/check-repo.py`, `scripts/test.sh`, and `scripts/build.sh`.
- For packaging changes, run `scripts/package-setup.sh`; mount and inspect the DMG.
- For UI changes, inspect the actual UI. Do not label unperformed GUI checks as passed.
- Update the relevant guide. README stays short; detailed records go in `docs/`.
- Use concise lowercase commits: `type: what changed`.

## Release and privacy

- Version source: `Sources/BraveDestinations/ReleaseVersion.swift`.
- Follow [signing](docs/signing.md). Release asset: `Brave-Container-Adapter.dmg`.
- Keep credentials, private keys, notarization attempts, generated apps and real
  destination configuration out of Git. Never put passwords in command arguments.
- Local builds are ad-hoc signed. Do not call them notarized releases.
- Check signatures, both architectures, tickets, Gatekeeper and a fresh download.
- Record automated checks separately from manual checks and test-copy limitations.
- Repository visibility, history rewrites and credential revocation require explicit
  user authorization. A public-readiness audit does not authorize publication.
- Keep `CLAUDE.md` as a relative symlink to this file; do not create a second rule copy.
