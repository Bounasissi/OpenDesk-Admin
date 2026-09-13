# PROTOCOL_OBSERVATIONS — OpenDesk

**Owner:** Plan 02 (living document). Holds established public facts and derived observations. Every entry cites evidence.

---

## 1. Established Public Facts

| # | Fact | Evidence |
|---|---|---|
| F1 | ARD traffic uses TCP/UDP 5900 (RFB), TCP/UDP 3283 (ARD reporting), TCP 22 (SSH) | Apple documentation (public ports list) |
| F2 | RFB security type 30 is the Apple Remote Desktop authentication type | IETF VNC community documentation; LibVNCClient sources |
| F3 | LibVNCClient supports Apple ARD security type 30 | Public LibVNCClient implementation/docs |
| F4 | `SMAppService` registers LaunchAgents/LaunchDaemons on macOS 13+ | Apple documentation |
| F5 | ScreenCaptureKit includes persistent capture support for VNC applications while requiring user-granted screen-capture permission | Apple documentation |
| F6 | Developer ID-distributed software requires signing, Hardened Runtime, secure timestamps, and notarization; sandboxing is recommended, not mandatory, outside the App Store | Apple documentation |
| F7 | Sparkle 2 supports SPM integration, HTTPS distribution, Developer ID/notarization, and Ed25519-signed updates | Sparkle project documentation |

Rules: facts are seeded from public documentation only; observations from experiments (ARD-EXP-###) are appended with capture references and must pass the redaction policy.

---

## 2. Open Questions / Pending Observations

| ID | Question | Blocking plan |
|---|---|---|
| (none seeded) | Filled by Plan 02/06 as encountered | — |

---

## 3. Maintenance

- Append-only per fact/observation; superseded facts are marked, not deleted.
- Plan 17/23 compatibility monitoring updates this file when macOS releases change behavior (ScreenCaptureKit, TCC, background items, notarization).
- No proprietary payload content ever appears here (see `IMPLEMENTATION_SEPARATION.md`).
