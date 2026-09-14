# Public-readiness audit

Updated: 2026-09-14. Scope: source, published Git history, releases, repository
settings, CI, packaging and local integration. This is a maintainer review, not an
independent penetration test or legal clearance. The initial findings remain in
[Git history](https://github.com/jakubswierczek/brave-container-adapter/blob/f98b889a52c69875664ea0295a39110de13dfcdd/docs/public-readiness.md).

**Keep private until the remaining publication steps below are complete.** The
engineering findings have fixes and regression coverage. External verification and
public-account settings must not be reported as complete without evidence.

## Remediation

| Finding | Change and evidence |
| --- | --- |
| Repository controls | `main` requires a pull request, resolved conversations and the strict `checks` status, including for admins. Force pushes/deletion are blocked. Active version-tag rules block updates/deletion while allowing new tags. |
| Missing license | Owner confirmed publication rights, including employer-related rights. [MIT](../LICENSE) covers code, documentation and project-owned artwork; contribution and asset terms updated. |
| Unbounded receiver queue | Maximum 32 pending batches/1 MiB; each batch accepts 128 URLs/128 KiB, with 64 KiB per URL. Rejects the newest batch atomically; preserves accepted duplicates and FIFO. Unit tests and a real event during an alert passed. |
| Blocking signing/registration | Async native helpers, 15-second timeout and cancellation. Setup stays available to cancel. Tests verify timeout, cancellation and preservation of unrelated processes/apps. |
| Unbounded file reads | Regular-file-only reads, memory caps, inode/size/timestamp checks, symlink and special-file rejection. Oversized file, icon and configuration tests pass. |
| Browser ownership/activation | Unknown, malformed and foreign locks fail closed. Uses Chromium's POSIX hostname, fixing a real mismatch found in vendor-Brave testing. Process/executable and activation-policy regression tests pass. |
| Update recovery | Injected signing, rename, swap and rollback failures verify preservation and retry. Hidden abandoned stages are ignored, not deleted blindly. Explicit unlock fixes a race found by parallel CI. |
| CLI contracts | Real process tests cover flag combinations, discovery, safe errors, generation, customization, signatures and unchanged fixture hashes. |
| UI responsiveness/editing | Metadata resolution moved off the UI thread; previews render one small image. Added Cancel and standard Edit-menu shortcuts. Inspected native labels, previews, name editing and installation. Full VoiceOver testing remains separate. |
| Runtime coverage | CI matrix exercises synthetic adapter behavior on macOS 14, macOS 15 and Intel macOS 15. Required aggregate check: `checks`. Browser GUI coverage is stated separately. |
| Actual switcher/vendor handoff | Choosy 2.5.2 delivered links to unmodified Brave 1.95.101 cold and running. Profile labels, badges, query/fragment and activation checked. Multiple profiles, batches, temporary mode, rename and deletion also checked. See [1.4.0 verification](verification-1.4.0.md). |
| Release provenance | Clean-source signing requirement; embedded source commit/tree, toolchain, build OS and dependency inventory. Final DMG checksum, Developer ID and notarization checks remain mandatory. No claim of reproducible bytes. |
| Artwork | Removed SF Symbols from generated icons in 1.3.1. Letter tiles and the recorded AI-generated setup artwork remain. MIT excludes third-party marks and user imports. |
| Maintenance | Named maintainer, latest-release policy, Brave compatibility procedure, CI runner retirement and release controls in [maintenance](maintenance.md). |

## Remaining publication steps

| Step | Current state |
| --- | --- |
| Public publisher identity | The existing Developer ID leaf certificate was inspected: no email address or email subject/SAN field. Signatures expose the publisher name and Team ID. The owner asked for advice; recommendation is to retain this personal identity. Final public disclosure remains part of publication approval. |
| Second-Mac distribution | Owner agreed to test. Still needs a normal browser download, first open, generated app and actual switcher handoff. No result is claimed. |
| Private vulnerability reporting | GitHub's endpoint is unavailable while this repo is private. Enable and verify the reporting form immediately when publication is authorized. Until then, [SECURITY.md](../SECURITY.md) states the private-access contact procedure. |
| Public security settings | Verify secret scanning and push protection availability after the visibility change. No null/unavailable API field counts as enabled. |
| Visibility change | Not authorized by this remediation request. Repo stays private until explicit owner approval. |

Full VoiceOver testing and browser GUI checks on Intel/minimum macOS are additional
compatibility work. Public wording must retain those limits. CI coverage is evidence
of adapter runtime logic on those systems, not evidence of all browser behavior.

## Privacy and repository surfaces

The final pre-release scan covered 19 remote commits and 138 unique blobs through
`a6e486737ac887d66acf3c6a79e8d0f4d00e88a8`: Gitleaks and targeted private-path/key/mail
checks reported zero findings. The positive control was rerun successfully. The
exact v1.4.0 DMG payload also passed both scans, and its clean-source build manifest
and MIT license were checked. Signatures intentionally retain publisher identity.

Live GitHub inventory at release preparation: private repository, one collaborator
(the owner), no issues/PRs yet, no Actions artifacts, secrets, variables, environments,
webhooks or deploy keys, no Pages, discussions or forks. The unused wiki was disabled.
REST package details required a missing scope, but the permitted GraphQL
`repository.packages.totalCount` query returned **0**. No token scope was widened.
The later documentation pull request contains only public-safe release evidence.


The initial audit scanned a fresh remote bare clone and all five then-published ZIP
release payloads. Gitleaks 8.30.1 was verified against its official SHA-256 and tested
with a synthetic-token positive control. History and payload scans reported no
findings. A targeted all-blob scan found no concrete user-home/external-volume paths,
private-key headers or personal mailbox patterns. Author/committer addresses used
GitHub noreply addresses. These checks do not prove that every secret format is absent.

The five old ZIP releases were removed at the owner's request. Source tags remain
for traceability. v1.3.1 introduced the signed DMG; withdrawn binaries containing
SF Symbols must not be republished. The current [v1.4.0 DMG](https://github.com/jakubswierczek/brave-container-adapter/releases/tag/v1.4.0) passed Developer ID, Apple notarization, staple, Gatekeeper, mount/copy and local first-launch checks. See [verification](verification-1.4.0.md) and the [signing guide](signing.md).

Before publication, re-scan the final remote refs and exact DMG, and inspect Actions
logs/artifacts, issues, pull requests, wiki, packages, releases, collaborators,
secrets/variables, environments, webhooks and deploy keys. Scan reports, signing
credentials, real browser data and generated destination configuration stay outside
Git. `.gitignore` is not secret protection. Do not mirror local checkpoint refs.

## Limits that remain by design

- Named routing resolves an ID from saved preferences, then passes its name to Brave.
  Browser memory can differ from disk before the request is processed. Brave itself
  may open an ordinary tab after a racing rename/deletion. There is no supported
  final-tab acknowledgment. This adapter is not an isolation security boundary.
- Temporary containers follow Brave's retention/session-restoration rules. They do
  not promise incognito behavior or erase-on-close.
- Configuration and installation overrides are trusted local input. A managed-app
  marker does not authenticate an app supplied by another person. Generate apps on
  each Mac; do not distribute real destination bundles.
- URLs are not logged by the adapter, but OS process inspection can see command-line
  arguments. Diagnostic profile names and IDs also need review before sharing.
- Rename plus replacement is not one crash-safe transaction. Recovery behavior and
  cancellation after installation are documented; no stronger guarantee is claimed.

The full launch contract and source references are in [architecture](architecture.md).
The publication sequence and repository-control policy are in [maintenance](maintenance.md).
