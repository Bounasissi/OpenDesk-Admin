# THREAT_MODEL — OpenDesk

> Plan 16 §2 living artifact (Addendum §23). Each threat maps to required
> controls in `docs/architecture/SECURITY_ARCHITECTURE.md` and to the plans
> implementing them. Status: living document, refined per plan execution.

## Threats and Coverage

| # | Threat | Primary controls | Implementing plan | Status (2026-09-13) |
|---:|---|---|---|---|
| 1 | Malicious managed endpoint (compromised target) | transport auth (SSH host-key TOFU, Plan 05 §4); least-privilege agent (Plan 11); audit trail | 05, 11 | TOFU IMPLEMENTED; agent MISSING |
| 2 | MITM | host-key verification; TLS for agent; signed updates | 05, 11, 20 | SSH policy IMPLEMENTED; agent TLS MISSING; updates EXTERNAL-GATED |
| 3 | Stolen admin Mac | Keychain secrets (device-only accessibility); audit trail; no plaintext secrets | 03, 05 | IMPLEMENTED (KeychainSecretStore + reference-only rows) |
| 4 | Compromised endpoint agent | versioned agent protocol; capability negotiation; signed updates | 11, 20 | PROTOCOL SPECIFIED; process isolation → 11 |
| 5 | Local unprivileged attacker | file permissions on DB/socket (0600); Keychain | 03, 12 | UDS 0600 IMPLEMENTED; DB perms → 16 sweep |
| 6 | Malicious package | checksum verify before install; installer result capture; staging cleanup | 07 | COMMAND SEQUENCE IMPLEMENTED; live verification → 17A |
| 7 | Command injection | typed command parameters; no shell interpolation of untrusted input | 07, 08 | DurableTaskRunner parameter JSON; sweep → 16 |
| 8 | Path traversal | path validation on transfers | 07 | Policy-level; enforcement sweep → 16 §3 |
| 9 | Credential theft | Keychain; redaction (key-based) before logs/bundles | 05, 18 | IMPLEMENTED (redactParameterKeys + bundle test) |
| 10 | Replay | TLS channels; idempotency keys prevent duplicate execution | 08, 11 | IDEMPOTENCY IMPLEMENTED; TLS → 11 |
| 11 | Privilege escalation | RBAC authorization service at every enforcement point | 05 | SEAM IMPLEMENTED; enforcement sweep → 16 |
| 12 | Update compromise | Sparkle 2 + Ed25519 + HTTPS + Developer ID | 20 | EXTERNAL-GATED (Apple credentials) |
| 13 | Dependency compromise | zero runtime dependencies; native-first policy (ADR-0003); SBOM at release | 01, 19, 20 | ZERO DEPENDENCIES VERIFIED |
| 14 | Log leakage | redaction filter; diagnostic bundle redaction test | 18 | IMPLEMENTED |

## Release Gate (Addendum §23)

No open Critical/High issue at release. Required artifacts: this document, SBOM, dependency + license inventory (16A), secret scan (`make verify` gate), privileged-helper audit (Plan 20 §6), release entitlement audit (Plan 20).
