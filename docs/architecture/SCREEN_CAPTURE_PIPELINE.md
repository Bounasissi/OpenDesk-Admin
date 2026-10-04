# ScreenCaptureKit Capture Pipeline

**Status:** Agent-side capture and VideoToolbox encoding are implemented under
Plan 14. Network delivery, client decode, and rendering remain separate work.

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

## VideoToolbox encoding

`Sources/OpenDeskAgent/VideoToolboxEncoder.swift` consumes the captured
IOSurface-backed NV12 buffers directly. H.264 is the default; HEVC is selectable
through `EncodeConfiguration` but is not enabled by default. The compression
session is configured for real-time encoding, expected frame rate, average
bitrate, a bounded keyframe interval, and disabled frame reordering for lower
latency. Hardware acceleration is requested when enabled but not required, so
VideoToolbox can fall back; this is not proof that the selected encoder is
hardware-backed.

Each output contains compressed bytes, presentation time, coded dimensions,
keyframe state, codec, and its `CMFormatDescription` (required for downstream
decoder setup). `setAverageBitrate(kbps:)` applies adaptive bitrate decisions
without recreating the session. If capture dimensions change, the encoder
completes outstanding VideoToolbox callbacks from the old session, then creates
a new session; a shared serial output queue preserves delivery order across
that transition, and the new session begins with a keyframe. Output handlers
run asynchronously and may finish after `finish()` returns. Invalid geometry, formats,
rates, and encoder lifecycle calls produce typed errors.

`Tests/OpenDeskAgentTests/VideoToolboxEncoderTests.swift` creates synthetic
NV12 pixel buffers and runs the actual VideoToolbox H.264 compressor. The test
checks non-empty compressed output, H.264 format description, timestamps,
keyframes, bitrate updates, dimension reconfiguration, stop/error behavior, and
callback reentrancy.
This requires no screen recording permission and captures no real user content.

## Remaining Plan 14 work

- Wire the per-user agent capture service into an authenticated remote-session
  request/approval path.
- Connect the adaptive controller's keyframe/bitrate outputs to the encoder and
  capture configuration in the live capture-to-network session.
- Measure hardware selection, real capture/encode latency, dynamic-resolution
  transitions, and multi-display behavior on a consented test Mac.
- Implement transport, decode/render, and Plan 14 §9 LAN/degraded-profile
  comparison evidence.
