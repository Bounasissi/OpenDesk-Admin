# Plan 02 — Clean-Room ARD Decomposition

> Binding instruction document. Read `/AGENTS.md`, `docs/clean-room/POLICY.md`, and `docs/clean-room/IMPLEMENTATION_SEPARATION.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 02
- **Prerequisites:** 01
- **Blocks:** 03 (behavioral contracts feed architecture), 06–11 (behavioral specs)

---

## 1. Goal

Produce a behavioral specification of Apple Remote Desktop without copying proprietary implementation.

---

## 2. Non-Negotiable Boundary

Allowed:

```text
public Apple documentation
public protocol specifications
interoperability testing
bundle metadata inspection
runtime observations
network metadata
behavioral black-box experiments
published open-source interoperability implementations
```

Do **not**:

```text
circumvent DRM
defeat FairPlay
redistribute Apple binaries
copy Apple implementation code
translate Apple machine code into OpenDesk source
copy Apple graphical assets
copy substantial proprietary resources
```

Store **derived observations only**, never proprietary binaries (see `docs/clean-room/IMPLEMENTATION_SEPARATION.md`).

---

## 3. Required Outputs

### 3.1 Decomposition harness

Build a harness that inventories an installed, lawfully obtained ARD application and emits:

```text
bundle tree
Info.plist
architectures
linked libraries
entitlements
XPC services
helpers
public selectors/symbol metadata
resource types
preference identifiers
network endpoints
```

Harness output is stored as derived observations under `docs/clean-room/` (or a data directory it owns). The harness lives in `scripts/` and runs only on operator-provided local ARD installs.

### 3.2 Behavioral corpus

Define experiments for every material ARD behavior (experiment template in `docs/clean-room/ARD_BEHAVIOR_MATRIX.md`):

```text
discover
authenticate
observe
control
clipboard
copy
install
command
wake
restart
shutdown
reports
scheduled task
offline task
multi-observe
failure/reconnect
```

Each experiment records:

```text
preconditions
input
visible behavior
network behavior
OS side effects
result states
failure states
timing
```

### 3.3 Compatibility matrix

For every ARD capability, classify it in `docs/product/COMPATIBILITY_MATRIX.md`:

```text
A — standard protocol directly interoperable
B — functionality reproducible with public macOS APIs
C — optional ARD wire compatibility useful
D — replace with OpenDesk-native implementation
E — defer from v1
```

---

## 4. Engineering Rules Specific to This Plan

- Network observations use passive capture plus controlled lab traffic only. No adversarial probing of machines the operator does not own.
- Every claim in the behavior matrix must cite its evidence source (experiment ID, Apple documentation URL, or RFC).
- Facts established by public documentation go into `docs/clean-room/PROTOCOL_OBSERVATIONS.md` (seeded with: ARD traffic on TCP/UDP 5900, TCP/UDP 3283, SSH/22; RFB security type 30 for ARD; LibVNCClient supports Apple ARD security type 30; SMAppService registers LaunchAgents/LaunchDaemons on macOS 13+; ScreenCaptureKit supports persistent capture for VNC applications with user-granted screen-capture permission).

---

## 5. Tests Required

- The harness itself has unit tests for parsing/emitting derived observations.
- Every experiment definition validates against the template schema (automated check where feasible).

---

## 6. Exit Gate

No v1 requirement exists solely as "figure out how Apple did it." Every v1 requirement has an independently implementable behavioral contract (a row in the compatibility matrix with classification A–E and a behavioral spec).

---

## 7. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `03-ARCHITECTURE-FOUNDATION`).

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §2)

**Rule:** clean-room decomposition is NOT complete merely because a script exists. Conversation 2 produced `scripts/analyze-ard-bundle.sh`, `scripts/capture-experiment.sh`, behavior-spec YAMLs, and a compatibility matrix. Those artifacts are inputs. **Writing the harness is not equivalent to executing the decomposition program.**

### Required completion work (beyond the original plan)

1. Run the permitted clean-room analysis against a lawfully available ARD installation where possible; retain only derived observations.
2. Record, per observed component: bundle topology, Mach-O architectures, linked frameworks, entitlements, helpers, XPC services, public metadata, preference domains, observable network endpoints, observable task behavior, failure behavior, state transitions.
3. Behavioral experiments MUST cover at least (adds to the §3.2 list):

```text
logout
inventory
```

### Additional required outputs (beyond §3.2/§3.3)

```text
docs/clean-room/ARD_BEHAVIOR_MATRIX.md   (exists — extend, keep evidence citations)
docs/clean-room/ARD_FEATURE_PARITY.md    (NEW — required by addendum)
docs/clean-room/PROTOCOL_OBSERVATIONS.md (exists — extend)
```

### Hard rule

Do not translate proprietary implementation code into OpenDesk. Only derived observations cross the boundary (`docs/clean-room/IMPLEMENTATION_SEPARATION.md`).

Exit-gate addition: Plan 02 is complete only when every §3.2 + A1 experiment has been executed (or explicitly gated when no lawful ARD install is available) AND `ARD_FEATURE_PARITY.md` exists with per-capability classification.
