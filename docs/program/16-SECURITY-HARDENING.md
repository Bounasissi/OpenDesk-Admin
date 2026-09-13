# Plan 16 — Security Hardening

> Binding instruction document. Read `/AGENTS.md` and `docs/architecture/SECURITY_ARCHITECTURE.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 16
- **Prerequisites:** 04–15
- **Blocks:** 17 (gate), 19 (SECURITY.md evidence), 20 (signing prerequisites), 22 (launch gate)

---

## 1. Goal

Treat OpenDesk as privileged administrative infrastructure.

---

## 2. Threat Model

Analyze:

```text
malicious remote endpoint
MITM
stolen admin Mac
compromised OpenDesk agent
local unprivileged attacker
malicious package
command injection
path traversal
credential theft
replay
privilege escalation
update compromise
supply-chain compromise
log secret leakage
```

Document the model and each control's coverage in `docs/architecture/SECURITY_ARCHITECTURE.md` (living section).

---

## 3. Required Controls

At minimum:

```text
Keychain-backed secrets
transport authentication
certificate/host identity validation
signed updates
secure temporary files
path validation
command parameterization
audit trails
redaction
least privilege
bounded parser inputs
network timeouts
rate limits
```

---

## 4. Privileged Helper Review

Verify:

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

## 5. Dependency Security

Produce:

```text
dependency inventory
license inventory
SBOM
vulnerability scan
```

---

## 6. Secrets Scan

Run against:

```text
current tree
Git history where practical
release artifact
```

---

## 7. Agent Sequence

1. Write threat-model document with mitigations mapped to implemented controls; file ADRs for any gap consciously deferred.
2. Implement/verify each control of §3 against the codebase (audit all transports, temp files, parsers, timeouts, rate limits).
3. Privileged helper review per §4; remediate findings.
4. Generate dependency/license inventory + SBOM + vulnerability scan; automate in CI.
5. Secrets scan (tree, history where practical, artifact); remediate.
6. Manual review pass (specification-compliance + security review per AGENTS.md §6).

---

## 8. Tests Required

- Exploit-style tests for each threat class where automatable (injection, traversal, replay, unauth IPC).
- Redaction tests across all log/audit paths (no secret values).
- SBOM/license scan reproducible via `make verify` or CI job.

---

## 9. Exit Gate

No unresolved Critical/High security finding. Any accepted Medium finding requires documented rationale and remediation owner/version (record in `PROGRAM_STATUS.md`).

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `17-COMPATIBILITY-RELIABILITY-PERFORMANCE`).
