# Security policy

## Report a vulnerability

Do not put exploit details, private URLs, browser data or credentials in an issue.
While this repository is private, use the private channel through which you were
given access to contact the maintainer. If you have no such channel, open an issue
asking for a private contact without disclosing the vulnerability.

Before public launch, the maintainer must enable GitHub private vulnerability
reporting and verify its **Report a vulnerability** form. That channel is not
claimed to be available yet. See the [publication checklist](docs/public-readiness.md).

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
