# Security Model

## Secrets

**Never store passwords in SQLite.**

```
SQLite:  credentials.credential_reference = UUID
Keychain: UUID → secret
```

Supported secret kinds: `password | ssh_key | certificate | agent_token | vnc`.

## Permission model (RBAC)

Separate permissions mirroring ARD's granular privileges:

```
observe · control · clipboard · files_read · files_write · install
execute · power · lock · message · inventory · configuration · admin
```

Objects: `users · roles · devices · groups · permissions · audit log`.

## Audit

Every admin-initiated action writes an `audit_events` row: who, what, target, payload, when. Power actions and package installs are high-sensitivity and always audited.

## Transport security

- SSH for all management traffic (v1).
- RFB with ARD auth (type 30) / TLS / VeNCrypt for remote control.
- No plaintext credential transmission.

## Clean-room security boundary

No Apple binaries, assets, or decompiled logic in the repo. See [CLEAN-ROOM-POLICY.md](../CLEAN-ROOM-POLICY.md).

## Build/distribution

Developer ID signed + notarized. Reproducible open-source builds. GPL-3.0-or-later.
