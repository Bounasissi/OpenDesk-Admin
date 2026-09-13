# HOTFIX_RUNBOOK — OpenDesk (Plan 23)

---

## 1. Severity

```text
P0 — security compromise, destructive behavior, credential exposure
P1 — major function unavailable/crash loop
P2 — material degraded behavior
P3 — ordinary defect
```

Security hotfixes bypass normal feature cadence.

---

## 2. Flow (all severities use the same disciplined path)

```text
reproduce → regression test → fix → full relevant suite → version bump
→ signing → notarization → staged update → stable update
```

---

## 3. Rules

- No fix without a failing reproduction (test or scripted evidence).
- The full relevant suite runs — not just the fixed area (`make verify` minimum).
- Update goes **staged** (appcast-staged rollout) before stable where the mechanism allows.
- P0 additionally triggers `docs/runbooks/ROLLBACK.md` §3 if a compromised artifact/key is involved.
- Every hotfix appends a phase-gate-style report to `docs/status/PROGRAM_STATUS.md`.

---

## 4. Evidence Retention

Reproduction script/test, fix commit range, suite results, staged/stable rollout timestamps — recorded against the hotfix release entry.
