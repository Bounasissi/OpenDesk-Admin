# Plan 06A — RFB/ARD Compatibility Reconciliation

> Binding instruction document. Executes within Plan 06's window (before Plan 06 exit gate).
> Source requirement: Addendum §3. Conversation claims: see `docs/status/REPOSITORY_LINEAGE.md` §2 rulings.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 06A
- **Prerequisites:** 03 (architecture), 00A (lineage rulings)
- **Blocks:** 06 exit, 16A (license implications)

---

## 1. The Conflict

Two conversation histories describe two different protocol architectures:

| History | Architecture | License implication |
|---|---|---|
| Architecture/scaffold conversation | `LibVNCClient` + Apple ARD security type 30 + GPL-3.0 | GPL obligations if linked or distributed |
| Implementation conversation | custom Swift RFB + standard VNC DES challenge-response + MIT | no GPL linkage |

These are different products architecturally. **Both must not be carried accidentally.**

## 2. Required Decision

Audit the actual canonical dependency graph (`Package.swift`, Package.resolved, source imports, scripts) and rule exactly one:

```text
A. Pure/custom Swift RFB implementation          ← canonical state as of 2026-09-13
B. LibVNCClient linked implementation
C. Separate GPL helper process (isolation architecture)
D. Another verified implementation
```

**Default ruling (recorded, reversible by ADR):** Option A — pure Swift RFB. Evidence: canonical `Sources/OpenDeskCore/Protocol/*` (RFBConnection, FramebufferDecoder, HextileDecoder, KeysymMap, ScreenSession) with 92/92 passing tests including authenticated loopback RFB over real TCP; zero external dependencies in canonical `Package.swift`; scaffold's LibVNCClient path exists only in unmerged GPL code. If Option B or C is later chosen, it requires: license reconciliation in 16A, security review in Plan 16, and a new ADR.

## 3. Authentication Matrix (required)

Explicitly test, support, and document each row. **Do not call standard VNC password authentication "full ARD authentication" unless demonstrated end-to-end against a real ARD host.**

| Auth mechanism | v1 requirement | Status on canonical branch (2026-09-13) |
|---|---|---|
| RFB None (security type 1) | required | VERIFIED_CURRENT (loopback tests) |
| Standard VNC authentication (type 2, DES challenge-response) | required | VERIFIED_CURRENT (VNCAuthTests + loopback wrong-password rejection) |
| Apple Screen Sharing interoperability (RFB `003.889` banner) | required | PRESENT_BUT_UNVERIFIED (parsing + negotiation code exists; real-Apple-host verification gated on Plan 17A lab) |
| Apple ARD authentication / security extensions (type 30) | optional / deferred | PRESENT_BUT_UNVERIFIED (scaffold advertises type 30; canonical does not implement it) |
| SSH authentication (transport for tunnels) | required | VERIFIED_CURRENT (SSHTransport + TunnelManager; host-key policy = Plan 05 §4) |
| OpenDesk Agent authentication | required for Plan 11 | MISSING (agent not built) |

## 4. Wire Compatibility Matrix (required)

Each protocol surface receives exactly one classification — `required` / `optional` / `replaced by OpenDesk-native behavior` / `deferred` — with rationale, recorded in `docs/product/COMPATIBILITY_MATRIX.md`:

| Surface | Default ruling | Rationale |
|---|---|---|
| RFB on 5900 (Screen Sharing protocol) | required | Apple's shipped, publicly documented interop surface |
| ARD reporting/management on 3283 | deferred (v1); probe-only discovery | undocumented Apple wire protocol; clean-room policy forbids protocol translation; discovery probe only |
| ARD security type 30 | deferred; advertise-only where interoperable | requires live interop verification (17A) before any "supported" claim |
| Apple High Performance extensions | replaced by OpenDesk-native behavior | Plan 14 native path (ScreenCaptureKit/VideoToolbox) |

## 5. Tests Required

```text
version negotiation matrix (001.0016, 003.008, 003.889, malformed)
security-type negotiation (1, 2; type 30 advertise-only path)
DES challenge-response known-answer + live loopback
banner-parsing edge cases (truncated, non-RFB, 003.889 UInt8 safety)
```

## 6. Exit Gate

- [ ] Dependency audit recorded (what is actually linked today).
- [ ] Exactly one architecture option ruled (ADR if it changes from Option A).
- [ ] Authentication matrix documented with per-row status + tests where implementable.
- [ ] Wire-compatibility classifications recorded in `docs/product/COMPATIBILITY_MATRIX.md`.
- [ ] No code path links, embeds, or executes GPL library code on the canonical branch.
- [ ] No documentation claims ARD authentication beyond what is demonstrated.
