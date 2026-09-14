# Contributing

Read the [development guide](docs/development.md) and [repository instructions](AGENTS.md).
The repository is private and has no open-source license yet. Public contribution
terms must be settled before it is opened; do not assume a license grant.

Keep changes focused. Explain the problem, changed behavior, checks performed and
remaining limitations. Use synthetic fixtures. Never attach browser preferences,
real destination apps, complete URLs, signing credentials or personal profile data.

Before a pull request:

```bash
scripts/check-repo.py
scripts/test.sh
scripts/build.sh
```

For packaging changes, also run `scripts/package-setup.sh`. For routing or UI
changes, follow the [manual matrix](docs/testing.md) using disposable profiles.
State which checks were actually run. A process exit is not proof of routing.

Bug reports should include macOS, Brave and adapter versions, the destination
mode, steps using a neutral URL, and the exact error with private data removed.
Use the [security policy](SECURITY.md) for security issues.
