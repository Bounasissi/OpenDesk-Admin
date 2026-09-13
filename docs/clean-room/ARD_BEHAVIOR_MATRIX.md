# ARD_BEHAVIOR_MATRIX — OpenDesk

**Owner:** Plan 02. Template + experiment index. Each experiment's full record lives in `PROTOCOL_OBSERVATIONS.md` (or its linked observation file) with evidence.

---

## 1. Experiment Record Template

Every behavioral experiment records:

```text
id:              ARD-EXP-### (sequential)
behavior:        discover | authenticate | observe | control | clipboard | copy | install |
                 command | wake | restart | shutdown | reports | scheduled task |
                 offline task | multi-observe | failure/reconnect
preconditions:   endpoint state, credentials, network, macOS version
input:           exact stimulus applied
visible behavior: what the operator observes
network behavior: ports/protocols/metadata observed (no payloads with PII)
OS side effects: logs, preferences, files changed
result states:   success outcomes
failure states:  error outcomes
timing:          latency/threshold observations
evidence:        capture reference / Apple doc URL / RFC
classification:  A | B | C | D | E  (per COMPATIBILITY_MATRIX.md §1)
openDesk plan:   implementing plan
```

---

## 2. Required Experiment Index (from Plan 02)

| # | Behavior | Experiment focus |
|---:|---|---|
| 1 | discover | Bonjour/3283 advertisement semantics; network visibility |
| 2 | authenticate | RFB security type 30 flow; credential handling (no secret capture) |
| 3 | observe | framebuffer updates, resize, scaling |
| 4 | control | input event semantics, modifiers, multi-display coordinates |
| 5 | clipboard | sync directions, content types, truncation |
| 6 | copy | push/pull semantics, overwrite behavior |
| 7 | install | package copy + install reporting |
| 8 | command | command dispatch behavior |
| 9 | wake | WoL/remote wake behavior |
| 10 | restart / shutdown | power task semantics, session teardown |
| 11 | sleep | sleep trigger + wake propagation behavior |
| 12 | logout | user-session logout semantics + confirmation policy |
| 13 | inventory | inventory data shape (classification B candidates) |
| 14 | reports | report data shape (classification B candidates) |
| 15 | scheduled task | scheduling model observed (classification D target) |
| 16 | offline task | queued behavior when endpoint offline |
| 17 | multi-observe | concurrent observation behavior |
| 18 | failure/reconnect | disconnect behavior, reconnect semantics |

---

## 3. Status Tracking

| Experiment | Status | Evidence | Classification |
|---|---|---|---|
| 1–9 | PENDING-GATED (live ARD admin required) | bundle observations recorded (ARD-BUNDLE-001..003) | — |
| 10–18 | PENDING-GATED (live ARD admin required) | — | — |

Rules:

- All 18 experiments must reach `RECORDED` (or explicitly GATED with the admin-app install action) before the Plan 02 exit gate. Static bundle observations are complete and recorded (`reverse-engineering/protocol-observations/CLIENT-BUNDLE-FACTS.md`); live behavioral experiments are externally gated on a lawfully obtained ARD admin installation.
- Classification changes after Plan 02 require an ADR.
- No experiment may record secret material (passwords, keys) — redaction policy applies.
