# Public-readiness audit

Audit date: 2026-09-14. Baseline: `1f0280041c0b5edaf69d4c64c147814f208ef500`.
Scope: published Git history, five release archives, repository settings, Swift
source, fixtures, packaging scripts, documentation, signing and integration evidence.
This is a maintainer review, not an independent penetration test or legal clearance.

**Decision: keep private for now.** Source cleanup and a signed DMG do not settle
licensing, public reporting, or the missing end-to-end compatibility checks.

## Completed cleanup

- Renamed GitHub repository to `jakubswierczek/brave-container-adapter`; updated origin
  and documentation links. Visibility remains private.
- Preserved bundle IDs, configuration formats, CLI name and legacy install lookup.
- Reduced README to an overview. Split usage, architecture, development, diagnostics,
  testing, signing and this audit into separate guides.
- Added `AGENTS.md`, relative `CLAUDE.md` symlink, contribution and security policies.
- Added macOS CI with read-only permissions, pinned checkout, tests and DMG packaging.
  Signing credentials remain local, outside CI.
- Replaced SF Symbols in destination icons with letter tiles. Existing preset names
  and custom icons remain supported.
- Centralized release version/build number. Added a DMG packaging/signing workflow
  with the plain filename `Brave-Container-Adapter.dmg`.
- Prepared replacement of the five ZIP releases at the owner's request. Old source
  tags remain; deleting releases is not deleting their Git history.

Release execution and CI results are recorded separately in [verification](verification-1.3.1.md).

## Publication gates

These are recommendations for opening this project, not requirements imposed by GitHub.
The repository owner must explicitly authorize the eventual visibility change.

| Priority | Gate | Evidence and required action | Done when |
| --- | --- | --- | --- |
| P0 | License and ownership | No `LICENSE`; GitHub reports no detected license. Confirm the owner can license all code and artwork, including any employer-related rights. Choose the source and asset licenses. Recommendation: MIT for project-owned code if broad reuse is intended. | Owner approves terms and copyright attribution; license files and contribution terms are committed. |
| P0 | Public identity and privacy | Published commits use a GitHub noreply address. Developer ID signatures expose the personal publisher name and Team ID. Public Git history, tags and release files must be intentional. | Owner reviews that disclosure and the final history/artifact inventory; final scans pass. |
| P0 | Private security reports | No public reporting channel is verified. `SECURITY.md` states the current limitation. | A private report channel works and the policy names it. Enable and test GitHub private vulnerability reporting when visibility permits. |
| P0 | Actual switcher handoff | No third-party switcher integration was run. This is the main user-facing use case. | On a target Mac, an actual switcher sends a link to the generated app and the correct vendor Brave profile/container becomes active, cold and running. Record switcher/Brave/macOS versions. |
| P0 | Clean target-Mac distribution | Historical fresh downloads used `gh`; they did not reproduce browser quarantine. | Download the DMG in a browser on a second Mac, drag Setup into Applications, eject, open normally and generate a working destination. |
| P1 | Branch/release controls | At audit start, `main` was unprotected, with no rulesets or workflows. CI is now defined; branch protection is still an owner setup task. | CI passes on the pushed commit; require its check on `main`, block force pushes/deletion, and decide a release-tag policy. |
| P1 | Supported-platform claims | Universal slices exist, but Intel and macOS 14 runtime checks are missing. | Run the matrix on those systems, or narrow the stated supported runtime before broad release. |
| P1 | Artwork provenance and branding | Setup artwork has saved generation prompts. No official Brave logo was requested. This is evidence of origin, not clearance of rights. | Owner approves asset terms, reviews branding and confirms no employer or third-party assets were included without permission. |
| P1 | Maintenance contract | Brave preferences and container CLI flags are internal integration details. No upstream stability promise exists. | Name a maintainer, state a supported-version policy, and rerun routing checks for supported Brave changes. |

Public availability alone does not grant an open-source license. GitHub explains the
need for license terms in [Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).
Treat publication as durable: existing copies and forks may remain even after a
repository becomes private again. Review [visibility effects](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).

## History, secrets and repository surfaces

The initial audit used a fresh bare clone from GitHub, not local agent checkpoint
refs. It contained one branch, five version tags, 13 reachable commits and 65 unique
blobs. Local workspace refs, ignored build output and Keychain material were outside
the publication scope. No mirror push or history rewrite was performed.

Gitleaks 8.30.1 was downloaded from its official release and checked against the
GitHub asset SHA-256. A synthetic GitHub-token positive control produced a finding
before the history scan. The complete remote history produced **zero findings**.
The positive control matters: it checks that the actual scanner executable and rule
configuration can detect a known input, rather than trusting an empty report alone.

A separate targeted byte scan of all 65 blobs found no matches for concrete user-home
or external-volume private paths, private-key PEM headers, or personal mailbox
patterns. The only author/committer email found was the owner's GitHub noreply address.
The fixture files were inspected as synthetic data. No real browser preferences,
generated destination configuration, certificate exports or browser databases were tracked.

All five existing ZIP releases were downloaded; their published checksums matched.
Targeted payload scans found no private-path/key/email matches or browser configuration
filenames. This does not prove that arbitrary binary data, unrecognized secrets or
all forms of personal information are absent. Scanner reports stay outside Git.

Initial GitHub API inventory:

| Surface | Observed state |
| --- | --- |
| Visibility / owner | Private / personal `jakubswierczek` account |
| Collaborators | Owner only |
| Issues and pull requests | Zero items across all states |
| Discussions / Pages / forks | Disabled / absent / zero |
| Wiki | Enabled as a setting; wiki Git endpoint returned repository not found |
| Packages | Unverified: API rejected the request because the token lacks `read:packages` |
| Actions workflows / runs | None before this cleanup |
| Actions secrets / variables / environments | Zero names returned |
| Webhooks / deploy keys | None returned |
| Branches / rulesets | `main`, unprotected; no rulesets |
| Releases | Five published ZIP releases, v1.1.0 through v1.3.0 |
| License / security analysis | No detected license; security-analysis configuration not exposed as enabled |

The API inventory is scoped to accessible repository settings. It is not an audit of
account-wide credentials, private Keychain items, organization policies or other repos.
Recheck archived/closed issues, discussions, wiki content, Actions logs/artifacts,
packages, releases and security settings immediately before opening. Those surfaces
can change after this snapshot. Do not treat `.gitignore` as secret protection.

## Architecture and security findings

### Existing protections

- No shell interpolation. URLs, names and paths become separate `Process.arguments`.
- HTTP/HTTPS input validation preserves accepted text, including percent encoding.
- All URLs in a batch are validated before launch; a 128 KiB argument budget applies.
- Destination identity includes installation, data directory, profile directory and ID
  or temporary mode. Display-name edits do not change identity.
- Named launches require an enabled, configured ID and an unambiguous current name.
  Retained/deleted container records are not offered as saved destinations.
- The reader retries partial/changing files. Browser preference access is read-only.
- Receiver errors omit URL contents; Brave output is suppressed. No telemetry, backend,
  cookie/history reading or production debugging port is part of the implementation.
- App generation checks ownership, rejects unrelated collisions and symlinks, stages
  bundles, verifies local signatures and uses exclusive rename/atomic replacement.

### Limits that must remain explicit

**Named routing is not a security boundary.** `Preferences.swift` resolves an ID to a
saved name; `Launch.swift` passes that name to Brave. The browser's in-memory state can
change or differ from disk before processing it. Brave may then choose an ordinary
tab or a retained name. Process success cannot confirm the final tab. Stronger
guarantees need a supported upstream ID-based launch/acknowledgment mechanism; reading
cookies or enabling a production debugging port is not an acceptable workaround.

**Temporary is not erase-on-close.** Brave manages temporary records and may retain
data for open tabs, sessions or tab restoration. Do not market it as incognito or
promise a deletion deadline.

**Trusted local configuration is a boundary.** Installation overrides are checked by
bundle executable/version metadata, not vendor signature. Managed-app markers can be
copied. A configuration supplied by another person can point to another executable.
Generate apps locally and do not describe marker validation as app authentication.

**Process arguments are visible locally.** The adapter does not log URLs, but operating
system process inspection can reveal launch arguments. Diagnostics also intentionally
print destination metadata. The docs must keep the redaction guidance.

### Follow-up engineering work

| Priority | Location | Risk | Smallest useful follow-up |
| --- | --- | --- | --- |
| P1 | `ContainerReceiver/main.swift` | Event queue is unbounded; a local burst or repeated events during modal errors can consume memory. | Define queue and batch limits with a clear rejection policy; test events during alerts without dropping accepted requests. |
| P1 | `AppGenerator.runTool` and Setup | Signing/registration wait synchronously without a timeout. A hung tool can freeze Setup. | Move process work off the UI thread; add timeout/error handling that preserves the existing app. |
| P1 | `PreferenceReader` and saved icon reads | Size checks are uneven; preferences and saved ICNS bytes can be loaded before a limit. Malformed local files can stall discovery or consume memory. | Bound reads at the filesystem boundary; add oversized-file and replacement-during-read cases. |
| P1 | `BraveLauncher` | Singleton-owner lookup is best-effort; activation is timed and has no final-profile acknowledgment. | Add deterministic ownership/activation tests and an explicit diagnostic when the running owner cannot be established. Keep routing limits visible. |
| P2 | App generation | Rename plus swap has multiple failure points and incomplete crash-transaction coverage. | Inject filesystem failures; test rollback, interrupted updates and subsequent recovery. |
| P2 | CLI | Parser/error combinations and `doctor` contracts have little direct automated coverage. | Add process-level tests with synthetic data, asserting safe errors and no unintended writes. |
| P2 | Setup accessibility/performance | No current VoiceOver/keyboard pass; icon rendering and discovery run on the main actor. | Check keyboard order, labels, contrast and large profile sets; cache previews only if measured latency warrants it. |
| P2 | Release reproducibility | Toolchains are selected locally. Signing timestamps/tickets make byte-identical DMGs impractical. | Record Xcode/Swift versions, source commit, checksums and dependency inventory for each release. Do not claim reproducible bytes. |

These are review findings, not demonstrated remote exploits. Address P1 before a
broad stable launch; a narrowly labeled preview can retain documented P2 work.

## Asset and dependency review

The Swift package declares no third-party dependencies. Runtime imports are Apple
frameworks. No copied Brave source was found; tagged upstream source is referenced to
explain the integration contract. New CI uses one pinned third-party action and no
signing secret. Review action updates before changing the pin.

Version 1.3.0 rendered SF Symbols into destination app icons. Apple's guidance
explicitly excludes [app-icon use of SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols).
Version 1.3.1 removes those symbols from the renderer. Presets now use ordinary letter
tiles. Resave existing generated apps to refresh them; imported custom icons are not
silently replaced. Historical source tags retain the old implementation and are not
recommended release builds. The withdrawn binary assets must not be republished.

Setup artwork is AI-generated and prompts are recorded in [assets](../assets/README.md).
Review the final artwork and applicable generation terms before choosing asset terms.
Do not imply Brave endorsement or claim a third-party trademark as project property.

## Release and repository operations

The release script signs inside-out, notarizes the app, staples it, packages the DMG,
then signs/notarizes/staples the image. Distribution checks cover signatures, both
architecture slices, tickets, Gatekeeper and a fresh GitHub download. A checksum
detects changed bytes; it does not replace signature or publisher checks.

Keep notarization credentials in local Keychain. Do not place signing identities in
pull-request CI. Prefer a reviewed source commit and a locally controlled release
step. CI should use read-only permissions and never run untrusted pull-request code
with publication secrets. No `pull_request_target` workflow was introduced.

GitHub redirects old repository links after a rename. Do not recreate a new repo at
the old name because that removes the redirect. See [GitHub's rename guidance](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository).
Existing app bundle IDs must remain unchanged regardless of repository branding.

GitHub supports [private vulnerability reporting for public repositories](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability).
When opening the repo, enable it and test the reporting entry point. Review secret
scanning/push protection availability for the account and enable supported features;
do not claim them enabled from a null API field. Set branch rules after CI is green.

## Final publication checklist

1. Approve source/asset licensing, ownership and public publisher identity.
2. Complete the switcher and target-Mac checks; resolve or narrow platform claims.
3. Address the P1 hardening items or explicitly label and document a limited preview.
4. Require green CI on `main`; protect history and decide who can publish release tags.
5. Re-scan a fresh remote clone, all refs and the exact final DMG. Review all other
   GitHub surfaces and confirm no sensitive artifact or log will become public.
6. Prepare the private reporting channel, support policy and final README wording.
7. Obtain explicit owner authorization to change visibility. Then enable public
   security features, verify anonymous docs/download access, and test reporting.
8. Announce only the platform/switcher combinations actually verified. Keep the
   routing race and temporary-data retention limitations in user documentation.

Do not rewrite history merely to remove the old repository name. If a real secret is
found later, revoke it first, then plan cleanup of history, tags, releases and copies
with the owner. Deleting a release or making the repository private is not revocation.
