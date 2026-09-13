# Security Policy — OpenDesk

## Reporting a vulnerability

Report privately to the maintainers via GitHub Security Advisories
("Report a vulnerability" on the repository). Do not open public issues for
exploitable defects.

Include: affected component, reproduction steps, impact assessment, and
(suggested) remediation. Reports are acknowledged within 7 days.

## Supported versions

Security fixes land on the latest tagged release and the canonical branch
(`canonical-091326`). Prerelease tags (alpha/beta) receive fixes at the
project's discretion.

## Security posture

- Secrets are stored only in macOS Keychain; the database stores references.
- Update artifacts are Developer ID-signed, notarized, and Ed25519-update-signed (Plan 20).
- Dependency policy: native-first, zero runtime dependencies verified in CI (`scripts/license-check.sh`).
- Threat model: `docs/security/THREAT_MODEL.md`.
- Secret scanning runs in CI; secret material must never be committed.

## Hard rules for contributors

- Never log or export secret material (key-based redaction is enforced in the
  diagnostic bundle; see `Sources/OpenDeskCore/Diagnostics/Observability.swift`).
- Never bypass macOS privacy consent (Screen Recording, Accessibility).
- See `docs/clean-room/POLICY.md` for the proprietary-material boundary.
