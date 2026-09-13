# Plan 14 — High-Performance Streaming

> Binding instruction document. Read `/AGENTS.md` and `docs/architecture/TRANSPORT_ARCHITECTURE.md` first.
> Execute in an isolated worktree/branch per `AGENTS.md` §4.
> **Parallel-eligible after Plan 11.** Must not delay core v1 completion unless promoted into the v1 release gate by ADR.

- **Plan ID:** 14
- **Prerequisites:** 11 (agent capture surface)
- **Blocks:** None on the critical path; feeds 17 (performance evidence) and post-v1 default control path

---

## 1. Goal

Provide an OpenDesk-native high-performance remote-view transport independent from Apple's private implementation.

**This is post-parity-core.**

---

## 2. Capture

Use ScreenCaptureKit. Handle:

```text
display capture
dynamic resolution
multiple displays
frame metadata
audio where enabled
permission changes
capture interruption
```

---

## 3. Encode

Use VideoToolbox. Start with:

```text
H.264
```

Add HEVC where hardware/platform support and interoperability justify it.

---

## 4. Transport

Select a secure, congestion-aware transport. Preferred architecture:

```text
control channel
video channel
audio channel
input channel
telemetry
```

Do not design raw unreliable UDP from scratch without congestion/error-control semantics.

---

## 5. Decode/Render

Use VideoToolbox and Metal where useful.

---

## 6. Adaptive Quality

Inputs:

```text
RTT
packet loss
decoder pressure
encoder pressure
bandwidth
render backlog
```

Outputs:

```text
resolution
bitrate
FPS
keyframe behavior
```

---

## 7. Agent Sequence

1. Implement agent-side capture (ScreenCaptureKit, dynamic resolution, interruption handling).
2. Implement encode pipeline (VideoToolbox H.264; HEVC behind capability flag).
3. Implement secure channel multiplexing (control/video/audio/input/telemetry).
4. Implement decode/render path (VideoToolbox + Metal renderer in admin app).
5. Implement adaptive-quality controller (measure-driven; document thresholds).
6. Implement input injection path (mouse/keyboard over input channel, parity with RFB path requirements of Plan 06 §5).

---

## 8. Tests Required

- Capture/encode unit + fixture tests (frame metadata, dynamic resize).
- Channel integration tests with loopback transport.
- Adaptive controller tests (synthetic RTT/loss/pressure profiles).
- Degradation tests: bandwidth clamp/burst profile stability.

---

## 9. Exit Gate

LAN remote control is visibly smoother than fallback RFB while remaining stable during bandwidth degradation. Evidence: recorded latency/FPS/bitrate comparison under LAN and degraded profiles, committed to the plan report.

---

## 10. Status Update

On completion update `docs/status/PROGRAM_STATUS.md` and `program-state.json`.
