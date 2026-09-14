# Security policy

## Report a vulnerability

Use GitHub's private [Report a vulnerability](https://github.com/jakubswierczek/brave-container-adapter/security/advisories/new)
form. Sign in to GitHub to submit a report. Private vulnerability reporting is
enabled; issues and pull requests are disabled.

Do not publish exploit details, private URLs, browser data or credentials.
The private form is for security vulnerabilities, not general support requests.

Include affected versions, impact, a minimal synthetic reproduction and suggested
fix if available. No response-time or bounty commitment is currently offered.

## Support and boundaries

Fixes target the latest release. Older releases receive no separate maintenance.
Notarization checks distribution artifacts; it does not prove correct routing.

The adapter is not an isolation security boundary. It validates saved preferences,
but cannot prove Brave's in-memory container selection or verify the final tab.
Named routing has a validation-to-launch race. Temporary containers follow Brave's
retention rules. See [architecture](docs/architecture.md#limits-and-guarantees).

Configuration and custom application paths are trusted local input. Managed-app
markers are ownership checks, not proof that an app from someone else is safe.
Generated bundles contain private local destination data and must not be uploaded.
