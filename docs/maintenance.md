# Maintenance and publication

Maintainer: [jakubswierczek](https://github.com/jakubswierczek). This is a personal
project. Fixes target the latest release; older releases receive no separate
maintenance. There is no response-time, service-level or bounty commitment.

## Compatibility policy

The deployment target is macOS 14. CI exercises adapter logic on macOS 14/15 and
Intel macOS 15. Universal binary slices do not certify browser handoff on every OS.
The current routing evidence and missing manual checks are in [testing](testing.md).

Named routing was inspected for Brave 1.92.140; temporary routing for 1.95.101.
These are minimum guards, not a promise that every future version works. Brave's
preference schema and command-line switches are internal. For each newly supported
Brave release, inspect the matching source tag and rerun the disposable-profile
matrix. If routing changes, document the failure and release a fix before claiming
support. Do not infer support from Brave's development branch.

GitHub retires its macOS 14 runner on 2026-11-02. Before then, move minimum-OS testing
to a maintained runner, or raise the deployment target and document the change.
Do not silently remove the oldest-OS check while retaining a tested-runtime claim.
See the [runner retirement notice](https://github.com/actions/runner-images/issues/13518).

## Change and release controls

Issues and pull requests are disabled at the owner's request. Maintainer changes
use a work branch: push it, run `gh workflow run ci.yml --ref BRANCH`, and wait for
the aggregate `checks` status on that exact commit. Fast-forward `main` only after
CI passes and the branch includes current `main`. Required CI also applies to
admins; do not bypass it. Force pushes and branch deletion remain blocked. Version
tags permit creation but block movement and deletion.

Keep Actions read-only and pin external actions by full commit SHA. Do not add
signing credentials to CI or use `pull_request_target` to run contribution code.
Review workflow and dependency changes explicitly. The package currently has no
external Swift dependencies. Build provenance rejects an unreviewed new dependency.

Release only a clean, reviewed source commit with passing CI. Increment the shared
version/build, follow [signing](signing.md), inspect the DMG and verify a fresh
uploaded download. Keep the asset name `Brave-Container-Adapter.dmg`. Release notes
must separate automated checks, GUI checks and outstanding checks. Never move a
published tag to fix a release; create a new version.

## Opening the repository

The engineering audit does not authorize a visibility change. Before publication:

1. Record the owner's source/artwork license and ownership decision. Add `LICENSE`
   and update contribution terms. Confirm public Developer ID identity disclosure.
2. Complete or explicitly limit the missing switcher/vendor-Brave and second-Mac
   evidence. Re-scan fresh remote history and the exact DMG. Review Actions logs,
   issues, wiki, packages and release assets.
3. Verify required CI and history protections. Record account-plan limitations;
   a workflow file alone is not branch protection.
4. Obtain explicit authorization to make the repository public.
5. Immediately enable GitHub private vulnerability reporting in Settings → Code
   security, then verify Security → Report a vulnerability. Update `SECURITY.md`
   to link the working form. Do not send a fake vulnerability report.
6. Enable supported secret scanning and push protection. Check the returned settings;
   do not infer success from an unavailable or null field.
7. Verify anonymous README, source and DMG access. Only then share the public link.

If private reporting cannot be enabled, arrange an approved private contact before
announcing the release. Do not publish the maintainer's email without permission.
