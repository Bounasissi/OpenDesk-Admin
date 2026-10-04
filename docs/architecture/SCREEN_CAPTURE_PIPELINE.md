# ScreenCaptureKit Capture Pipeline

**Status:** Capture implementation in progress under Plan 14. This document
covers agent-side capture only; encoding, network delivery, client decode, and
rendering remain separate Plan 14 work.

## Ownership and consent

`Sources/OpenDeskAgent/ScreenCaptureService.swift` is the ScreenCaptureKit
adapter. Instantiate it in the per-user agent, not the privileged daemon:
screen recording authorization is granted to a user application/process.
`start(...)` checks `CGPreflightScreenCaptureAccess()` and fails with a typed
permission error instead of prompting unexpectedly. A user-initiated consent
flow may call `requestScreenRecordingPermission()` explicitly. Following a
permission change, the service reports revocation and stops every active
display stream; reauthorization requires an explicit new start.

Each requested display gets an independent `SCStream` configured for native
pixel dimensions, H.264-compatible bi-planar 4:2:0 video samples, and the
requested frame-rate ceiling. Optional system audio is attached to one stream
only, so a multi-display capture does not duplicate audio. Complete video
samples are delivered with display ID, dimensions, presentation timestamp,
content rectangle, and scale metadata. The frame wrapper retains the IOSurface-
backed pixel buffer for downstream processing.

Display geometry and Screen Recording authorization are rechecked every five
seconds while capture is active. Geometry updates adjust active stream
configurations without reconnecting; removed displays are stopped and reported,
and a later reappearance is started again. ScreenCaptureKit stream-stop errors,
blank frames, and suspended frames produce interruption events. Transient
capture errors may be retried by the display monitor; permission revocation is
terminal for the current capture request.

## Testable boundary

`OpenDeskCore.CaptureConfiguration.streamPlans(available:)` is the pure planning
boundary consumed by the native adapter. It validates selected display IDs,
dimensions, uniqueness, and FPS (1–60), preserves requested order, and assigns
optional audio to exactly one stream. `CaptureFrameMetadata` is a framework-free
value type with geometry validation and a stable Codable representation.
`Tests/OpenDeskCoreTests/StreamingSessionTests.swift` covers these behaviors
without requesting Screen Recording permission or touching screen contents.

## Local native integration probe

The endpoint binary includes a short capture probe that counts frame metadata
in memory only; it neither saves nor transmits captured pixels:

```bash
swift run opendesk-agent capture-smoke --display <CGDirectDisplayID> --seconds 5
```

If Screen Recording is not authorized, enable it in **System Settings → Privacy
& Security → Screen Recording**, then rerun the command. The command accepts
`--request-permission` only as an explicit opt-in. A real capture probe is
permission-gated and must be run on a machine where that authorization is
available; CI verifies compilation and the framework-neutral planning and
metadata components only.

## Remaining Plan 14 capture work

- Wire the per-user agent capture service into an authenticated remote-session
  request/approval path.
- Add VideoToolbox H.264 encoding and bind bitrate/keyframe adaptation.
- Measure hardware behavior, dynamic-resolution transitions, and multi-display
  capture on a consented test Mac.
