# Plan 00B — Conversation-Claims-to-Evidence Audit

> Binding instruction document. Executes after `00A` and **before any existing Plan 01–23**.
> Source requirement: Addendum §0, §00B.
> Central rule: **conversation claims are historical evidence, not current repository truth.**

- **Plan ID:** 00B
- **Type:** One-time audit
- **Prerequisites:** 00A (lineage reconciliation)
- **Blocks:** 01–23

---

## 1. Goal

Convert every historical "done" statement from the three development conversations into exactly one of:

```text
VERIFIED_CURRENT          — proven by current canonical-branch execution and artifacts
PRESENT_BUT_UNVERIFIED    — artifact exists in repo, no current execution/artifact proof
MISSING                   — not found in the canonical tree
SUPERSEDED                — stronger replacement exists / ruling recorded
CONFLICTING               — two histories claim incompatible states for the same subsystem
EXTERNAL_GATE             — cannot be verified without an externally controlled resource
POST_V1                   — deliberately deferred beyond v1 scope
```

## 2. Never Accept as Proof

These transcript statements are not authoritative:

```text
"Phase complete"
"everything implementable is complete"
"complete ARD feature surface"
"final state"
"last remaining gap"
```

## 3. Evidence Hierarchy

A feature is `VERIFIED_CURRENT` only when **all** applicable evidence exists:

```text
source exists
+ current build succeeds
+ tests exist
+ tests pass now
+ integration wiring exists
+ documentation matches behavior
```

For release requirements, additionally require the **real release artifact**.

Historical passing-test counts (22, 45, 54, 67, 80, 88, 92) are not release evidence. Only the current canonical branch's current test result counts.

## 4. Audit Method

For every capability claimed in the conversations (the "conversation-derived regression invariants", all capability tables in both conversation READMEs, all module status rows, release claims):

1. Locate the implementing source in `canonical-091326`.
2. Run `swift build && swift test` on the canonical branch — record exit code, test count, date, toolchain.
3. Check integration wiring (CLI/GUI/TaskEngine wiring, CI workflow, docs).
4. Assign exactly one status from §1.
5. Record the evidence pointer (file path / test name / command) per capability.

## 5. Produce

```text
docs/status/CAPABILITY_AUDIT.md      — human-readable audit with evidence pointers
docs/status/capability-audit.json    — machine-readable ledger (consumable by the orchestrator)
```

## 6. Regressions That Must Remain Permanent Tests (Addendum §1)

If the corresponding code survives lineage reconciliation, permanent regression tests MUST exist for:

- RFB `003.889` version handling (no UInt8 overflow, safe pseudo-version parse, interoperable negotiation, clean rejection of malformed banners)
- DES correctness (standard known-answer vector; never regress `reverse(initialPermutation)` to Final Permutation)
- `FramebufferUpdateRequest` wire format (both X and Y positions; 10-byte structure)
- Network-framework threading (no synchronous dispatch onto a queue already executing the callback; discovery state changes asserted)
- Partial socket reads (fragmented reads, single-byte remainder, multiple frames per read, EOF, short reads)
- RFB loopback integration server (version handshake, no-auth, VNC auth, wrong-password rejection, framebuffer update, keyboard, pointer, clipboard)

## 7. Exit Gate

- [x] Every capability claim mapped to exactly one status with an evidence pointer.
- [x] `docs/status/CAPABILITY_AUDIT.md` + `docs/status/capability-audit.json` committed.
- [x] Canonical branch build/test executed on record (command, exit code, count, date).
- [x] Conflicting claims resolved with rulings recorded in `docs/status/REPOSITORY_LINEAGE.md`.
- [x] Audit conclusions consumed by the plan amendments (02, 04, 05, 06, 07, 08, 09, 10, 12, 13, 15, 16, 18, 20, 21) — each amendment cites the audit rows it addresses.
