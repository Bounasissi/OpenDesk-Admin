# Plan 10 — Multi-Observe and Session Management

> Binding instruction document. Read `/AGENTS.md` and `docs/architecture/TRANSPORT_ARCHITECTURE.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.

- **Plan ID:** 10
- **Prerequisites:** 06, 08, 09
- **Blocks:** 15 (session UI), 17 (resource soak)

---

## 1. Goal

Allow administrators to monitor several machines without saturating CPU/network resources.

---

## 2. Session Manager

Centralize sessions. No SwiftUI view should independently own a raw transport connection.

---

## 3. Quality Tiers

Implement:

```text
focused
visible-thumbnail
background
suspended
```

Suggested starting rates:

```text
focused: up to server/session limit
thumbnail: approximately 2–5 FPS
background: heavily throttled
not visible: suspend or near-zero refresh
```

Measure rather than blindly optimize.

---

## 4. Grid

Support 2, 4, 8, 16 concurrent visible devices subject to resource limits.

---

## 5. Session Promotion

Selecting a thumbnail promotes that session without full reconnect where feasible.

---

## 6. Agent Sequence

1. Implement central `SessionManager` (owns all transport sessions; views subscribe).
2. Implement tier controller driven by visibility/focus signals.
3. Implement thumbnail renderer path (decimated framebuffer updates).
4. Implement 2/4/8/16 grid layouts with tier assignment.
5. Implement promotion without reconnect (frame-rate/stream-quality upgrade path).
6. Implement explicit resource guardrails (per-session cap; global cap; suspended state).

---

## 7. Tests Required

- Tier transition tests (focus/blur/visibility events drive tier correctly).
- Promotion tests (no socket teardown/reconnect on promote).
- Synthetic 16-session load harness measuring memory, CPU, threads, connections; assert no runaway growth (feeds Plan 17 soak gate).

---

## 8. Exit Gate

16-session synthetic load does not cause runaway memory, CPU, thread, or connection growth.

---

## 9. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json` (next: `11-OPENDESK-ENDPOINT-AGENT`).

---

## Amendment A1 — Three-Conversation Addendum (2026-09-13, Addendum §10)

The conversation-derived tiled observation is capped at 1–4 columns. The broader requirement is **resource-aware multi-observe**: §3 quality tiers + §4 grid (2/4/8/16) + §5 promotion-without-reconnect already encode the target. Add the verification requirement:

- Test up to 2, 4, 8, 16 simultaneous visible/synthetic sessions.
- Verify **bounded**: CPU, memory, threads, sockets, bandwidth at each tier (measurement harness in Plan 17 §5 style).
- Session manager is central (single orchestrating type); connections are not owned by individual views.
- Promotion must not require unnecessary reconnect ( renegotiate pixel format/refresh first).
