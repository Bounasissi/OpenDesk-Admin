# Clean-Room Policy — OpenDesk

**Applies to:** Plan 02 and every plan that touches ARD behavior/protocol knowledge.
**Governing rule:** OpenDesk covers ARD's *practical administrative outcomes* via independent implementation, public protocols, public documentation, and clean-room behavioral analysis.

---

## 1. Allowed Inputs

```text
public Apple documentation
public protocol specifications (RFB/VNC, SSH, etc.)
interoperability testing
bundle metadata inspection
runtime observations
network metadata
behavioral black-box experiments
published open-source interoperability implementations
```

---

## 2. Prohibited Actions

```text
circumvent DRM
defeat FairPlay
redistribute Apple binaries
copy Apple implementation code
translate Apple machine code into OpenDesk source
copy Apple graphical assets
copy substantial proprietary resources
```

---

## 3. Observation Discipline

- Store **derived observations only** — never proprietary binaries or assets (`docs/clean-room/IMPLEMENTATION_SEPARATION.md`).
- Every behavioral claim cites evidence: experiment ID, Apple documentation URL, RFC, or public project reference.
- Behavioral experiments run only against machines the operator lawfully owns/controls.
- Findings are recorded in `docs/clean-room/ARD_BEHAVIOR_MATRIX.md` and `docs/clean-room/PROTOCOL_OBSERVATIONS.md`.

---

## 4. Interoperability Target Facts (public)

```text
ARD traffic: TCP/UDP 5900 (RFB), TCP/UDP 3283 (ARD reporting), TCP 22 (SSH)
RFB security type 30 = Apple Remote Desktop authentication
LibVNCClient supports Apple ARD security type 30
macOS Remote Management can be targeted via standard VNC flows once authentication is handled
```

---

## 5. Exit Obligation

No OpenDesk v1 requirement may depend on proprietary knowledge ("figure out how Apple did it"). Every requirement needs an independently implementable behavioral contract (Plan 02 exit gate). Disputes resolve via `AGENTS.md` §2.1; material rulings become ADRs.
