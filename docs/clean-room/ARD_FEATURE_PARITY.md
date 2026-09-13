# ARD_FEATURE_PARITY — OpenDesk vs Apple Remote Desktop

> Owner: Plan 02 (Addendum §2 required output). Classification scheme per `docs/product/COMPATIBILITY_MATRIX.md` §1 (A–E).
> Evidence: public documentation facts (F1–F7 in `PROTOCOL_OBSERVATIONS.md`), lawful bundle observations (ARD-BUNDLE-001..003), and OpenDesk capability audit (`docs/status/CAPABILITY_AUDIT.md`).
> Refined by Plan 02 execution as evidence accrues; classification changes after Plan 02 require an ADR.

---

## 1. Parity Verdict (2026-09-13)

OpenDesk's target is **practical administrative outcome parity** with ARD — not pixel-for-pixel or wire-for-wire duplication (Charter §6). The table below states, per ARD administrative outcome, how OpenDesk reaches or exceeds it and where parity stands on the canonical branch.

| ARD administrative outcome | Class | OpenDesk path | Canonical parity status (2026-09-13) |
|---|:---:|---|---|
| Observe/control remote screen (RFB 5900, Screen Sharing auth) | A | custom Swift RFB (06A ruling): handshake, VNC auth, Raw/Hextile, keys/pointer/clipboard | **FUNCTIONAL** (92/92 tests; real-Apple-host interop gated → 17A) |
| Apple ARD security type 30 authentication | C | advertise-only; deferred pending live interop evidence | **DEFERRED** (not claimed as supported) |
| Multi-observe windows | B/D | session manager + quality tiers + 2/4/8/16 grid | **BELOW PARITY** — current tiled view 1–4 columns, no central session manager → Plan 10 A1 |
| Send UNIX commands | A/B | SSH transport + typed task engine | **FUNCTIONAL** |
| Copy items (push/pull) | A/B | SFTP/rsync with policy + checksums | **PARTIAL** — checksums/progress/cancellation/resume missing → Plan 07 A1.2 |
| Install packages | B | `installer -pkg` staged pipeline | **PARTIAL** — checksum verification + per-device outcome recorded → Plan 07 A1.2 |
| Wake | B | Wake-on-LAN magic packet | **FUNCTIONAL** (packet layout verified) |
| Restart/shutdown/sleep/logout | B | typed power tasks via SSH/agent | **PARTIAL** — power ops spec exists; task wiring on canonical is engine-level → Plan 07 A1 |
| Inventory (hardware/software/reports) | B | public-API collectors + CSV/JSON export | **PARTIAL** — 4 collectors verified; 12-collector target → Plan 09 |
| Historical snapshots/diffs/comparison | B | snapshot store + drift | **MISSING** → Plan 09 A1.1 |
| Scheduled tasks | D | OpenDesk scheduler (run-now/once/RRULE/on-reconnect/on-predicate) | **PARTIAL** — interval+daily verified; RRULE/predicate from scaffold reference → Plan 08 |
| Offline tasks / durable queue | D | durable task server (WAITING_FOR_TARGET, retry, idempotency) | **MISSING** → Plan 08 A1.1 |
| Computer groups / Smart groups | D | static groups verified; predicate smart groups | **BELOW PARITY** — smart groups MISSING on canonical → Plan 04 A1.3 |
| Saved tasks | D | versioned TaskStore | **FUNCTIONAL** |
| Client roster / persistence | B | JSON + SQLite backends | **FUNCTIONAL** |
| Endpoint agent (admin without SSH) | D | OpenDesk Agent (LaunchDaemon/Agent, XPC, TLS, enrollment) | **MISSING** → Plan 11 |
| MDM-assisted provisioning | B | generic/Jamf/Kandji/Mosyle/Intune guidance | **MISSING** → Plan 13 |
| CLI/API/Shortcuts automation | B | CLI verified; `--json` everywhere, UDS API, App Intents | **PARTIAL** → Plan 12 |
| Task Server private wire protocol | E | not duplicated — OpenDesk task model replaces | CLOSED (ruling) |
| Every historical ARD report | E | core report set only | CLOSED for v1 (post-v1 roadmap) |
| Remote Directory / tagging UI | E | roster + groups cover core need | POST_V1 |
| Homebrew/Docker fleet mgmt | E | out of scope (Charter §6) | POST_V1 |

## 2. Parity Accounting

```text
FUNCTIONAL on canonical:      9 outcomes (verify rows above)
PARTIAL / BELOW PARITY:       8 outcomes → plans 04, 07, 08, 09, 10, 12
MISSING (v1 required):        3 outcomes → plans 11, 13 (+ 04 smart groups counted above)
DEFERRED/CLOSED by ruling:    3 outcomes (06A, 08-E, 09-E)
GATED on external resource:   real-host interop (17A), admin-app live analysis (Plan 02 gate)
```

v1 parity definition (Plan 22 acceptance): every row marked PARTIAL/MISSING reaches FUNCTIONAL (or is explicitly class E), verified from the signed public artifact.

## 3. Sources

- Apple public documentation (ports, remote management, installer, power APIs)
- RFC 6143 (RFB), SSH transport specs
- Lawful bundle observations: `reverse-engineering/protocol-observations/CLIENT-BUNDLE-FACTS.md` (ARD-BUNDLE-001..003)
- Canonical capability audit: `docs/status/CAPABILITY_AUDIT.md`
