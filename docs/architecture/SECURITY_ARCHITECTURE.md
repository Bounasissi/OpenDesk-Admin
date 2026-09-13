# SECURITY_ARCHITECTURE — OpenDesk

**Authority:** Decision-precedence level 4. Binding rules for Plans 05, 11, 13, 16, 18, 20.

---

## 1. Threat Model (from Plan 16)

| Threat | Primary control |
|---|---|
| Malicious remote endpoint | Host/certificate identity validation, bounded parsers |
| MITM | Transport authentication (SSH host keys, TLS mutual identity) |
| Stolen admin Mac | Keychain protection, no plaintext secrets, local auth posture |
| Compromised OpenDesk agent | Least privilege split (daemon vs user agent), signed updates, allowlisted operations |
| Local unprivileged attacker | Authenticated XPC only; no arbitrary privileged shell; interface restrictions |
| Malicious package | Checksum verification, staging + remote verify, typed pipeline |
| Command injection | Structured RemoteCommandService (no shell concatenation), parameterization |
| Path traversal | Path validation on every file operation |
| Credential theft | Keychain-only storage; redaction |
| Replay | Nonce/protocol controls on agent channel; idempotency keys |
| Privilege escalation | Authorization service (RBAC privileges), parameter validation |
| Update compromise | Ed25519-signed HTTPS update feed; Developer ID + notarization |
| Supply-chain compromise | Dependency/license inventory, SBOM, vulnerability scans |
| Log secret leakage | Redaction layer at every sink |

---

## 2. Credential Rule (binding)

```text
SQLite → CredentialID (reference)
Keychain → secret
```

Never store in SQLite: password, private key material, agent enrollment secret, VNC credential. Never log secrets.

---

## 3. Host Identity Policy

- SSH host-key checking is mandatory; global validation disabling is forbidden.
- TOFU acceptable only on **first explicit enrollment**, recorded with fingerprint + audit event.
- Subsequent mismatch = hard security event (blocked operation, typed error, audit event, user-visible alert).
- Agent channel: TLS with standard primitives; mutual identity when practical; no invented cryptography.

---

## 4. Authorization (RBAC)

Privileges (from Plan 05):

```text
observe control clipboard files.read files.write install execute power message inventory configuration administration
```

v1 is mostly single-operator, but the privilege enum + authorization service are built now; every capability enforces through the service, not ad-hoc checks.

---

## 5. Audit Trail

Every administrative action records: `actor, action, targets, timestamp, parameters with secrets removed, result, correlation ID`. Applied at the services layer; redaction-before-persistence.

---

## 6. Required Controls Checklist (from Plan 16)

```text
[x] Keychain-backed secrets
[x] transport authentication
[x] certificate/host identity validation
[x] signed updates
[x] secure temporary files
[x] path validation
[x] command parameterization
[x] audit trails
[x] redaction
[x] least privilege
[x] bounded parser inputs
[x] network timeouts
[x] rate limits
```

Verified by Plan 16 with the exit gate: no unresolved Critical/High finding; accepted Medium findings require documented rationale + owner/version.

---

## 7. Privileged Helper Review Criteria (from Plan 16)

```text
who can invoke it
what operations are exposed
parameter validation
authorization
XPC/interface restrictions
filesystem permissions
code signing requirements
```

---

## 8. Supply-Chain Security

Dependency inventory + license inventory + SBOM + vulnerability scan (automated in CI from Plan 16 onward). Secrets scan against current tree, Git history where practical, and release artifacts. Update signing keys (Ed25519) never stored on public web infrastructure.

---

## 9. Privacy Boundaries

- Logs/audit prohibit: passwords, private keys, tokens, clipboard contents (default), remote file contents, package contents (Plan 18).
- macOS consent prompts (Screen Recording, Accessibility, background items) are never bypassed; missing consent is surfaced with deep links (Plan 13/15).
- Remote crash/telemetry: local always; remote opt-in by default.
