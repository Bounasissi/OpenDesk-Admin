# Plan 05 — Identity, Credentials, RBAC and Security Foundation

> Binding instruction document. Read `/AGENTS.md`, `docs/architecture/SECURITY_ARCHITECTURE.md`, and `docs/architecture/DATA_MODEL.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 05
- **Prerequisites:** 03, 04
- **Blocks:** 06–13, 16

---

## 1. Goal

Ensure remote administration is secure before transport capabilities expand.

---

## 2. Keychain Rule

Implement credentials as:

```text
SQLite → CredentialID (reference only)
Keychain → secret
```

Never log secrets. Never store in SQLite:

```text
password
private key material
agent enrollment secret
VNC credential
```

---

## 3. Credential Types

Support:

```text
ARD/VNC
SSH password
SSH key
OpenDesk Agent identity
```

Prefer SSH keys.

---

## 4. Host Identity

Implement SSH host-key checking:

- Unknown host identity must not silently become trusted after a mismatch.
- TOFU (Trust On First Use) is acceptable on first explicit enrollment if recorded.
- Subsequent mismatch = hard security event (typed `AuthenticationError`/`AuthorizationError`, audit event, user-visible block).

---

## 5. Application Authorization (RBAC)

Privileges:

```text
observe
control
clipboard
files.read
files.write
install
execute
power
message
inventory
configuration
administration
```

Architect for RBAC even if v1 is mostly single-operator (privilege enum + authorization service seam; enforcement points land with each capability).

---

## 6. Audit Trail

Every administrative action records:

```text
actor
action
targets
timestamp
parameters with secrets removed
result
correlation ID
```

---

## 7. Agent Sequence

1. Implement Keychain-backed secret store behind the Plan 03 seam (keychain-only storage, reference IDs in SQLite).
2. Implement credential CRUD UI/service for the four credential types.
3. Implement privilege model + authorization service.
4. Implement host-key verification policy engine (TOFU recording, mismatch handling).
5. Wire audit event emission into every administrative action path that exists so far.
6. Add secret-redaction filter to the logging pipeline established in Plan 01.

---

## 8. Tests Required

- Keychain round-trip tests (test keychain where CI lacks one).
- Redaction tests: no secret value appears in logs/audit under any enumerated path.
- Host-key policy tests: TOFU record, mismatch rejection, re-enrollment flow.
- Authorization tests: each privilege gate.

---

## 9. Exit Gate

No plaintext credential exists outside process memory/Keychain, and sensitive actions generate redacted audit trails.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `06-RFB-REMOTE-CONTROL`).
