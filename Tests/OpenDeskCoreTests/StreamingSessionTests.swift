import XCTest
@testable import OpenDeskCore

/// Plan 14 §2/§3/§6: consent-free streaming session logic — capture/encode
/// configuration types, interruption state machine, keyframe policy, and
/// input-channel event parity with the RFB path (Plan 06 §5).
final class StreamingSessionTests: XCTestCase {

    // MARK: Session state machine (capture interruption + permission changes, §2)

    func testSessionInterruptionStateMachine() throws {
        var session = StreamingSessionState()
        XCTAssertEqual(session.phase, .idle)
        session.transition(.capturing)
        XCTAssertEqual(session.phase, .capturing)
        // Capture interruption (screen lock, display sleep) → interrupted → recovers.
        session.transition(.interrupted(reason: "display reconfigured"))
        XCTAssertTrue(session.phase.isInterrupted)
        session.transition(.capturing)
        XCTAssertEqual(session.phase, .capturing, "interruption recovers to capturing")
        // Permission revoked mid-session → stopped, never silent.
        session.transition(.stopped)
        XCTAssertEqual(session.phase, .stopped)
        // Illegal transition: stopped is terminal.
        XCTAssertThrowsError(try session.requestTransition(.capturing))
    }

    func testPermissionRevokedBlocksRestart() {
        var session = StreamingSessionState()
        session.transition(.capturing)
        session.transition(.stopped)
        XCTAssertFalse(session.canRestart, "stopped-by-revocation cannot silently restart")
    }

    // MARK: Keyframe policy (Plan 14 §6 outputs — requestKeyframe behavior)

    func testKeyframeRequestedOnRecoveryAndNewViewer() throws {
        // New viewer joins → keyframe needed regardless of quality state.
        XCTAssertTrue(StreamKeyframePolicy.keyframeNeeded(reason: .newViewer))
        // Recovery up-step → keyframe (verified in controller tests; policy agrees).
        XCTAssertTrue(StreamKeyframePolicy.keyframeNeeded(reason: .qualityRecovery))
        // Periodic keyframes bound decoder resync cost.
        XCTAssertFalse(StreamKeyframePolicy.keyframeNeeded(reason: .steadyState(lastKeyframeSecondsAgo: 2)))
        XCTAssertTrue(StreamKeyframePolicy.keyframeNeeded(reason: .steadyState(lastKeyframeSecondsAgo: 9)), "steady-state cadence ≥ 8s forces a keyframe")
    }

    // MARK: Input channel parity (Plan 06 §5 semantics over the §4 input channel)

    func testInputChannelEventParityWithRFB() throws {
        let mux = ChannelMultiplexer(channels: [.control, .video, .audio, .input, .telemetry])
        // Key event: type 1, down flag, keysym — mirrors KeyEvent (type 4).
        let keyEvent = InputEvent.key(keysym: 0x61, down: true)
        let keyFrame = mux.frame(channel: .input, payload: InputEvent.encode(keyEvent), sequence: 1)
        let decodedKey = try XCTUnwrap(InputEvent.decode(mux.parse(keyFrame)?.payload))
        XCTAssertEqual(decodedKey, keyEvent)
        // Pointer event: x, y, button mask — mirrors PointerEvent (type 5).
        let pointerEvent = InputEvent.pointer(x: 100, y: 50, buttonMask: 1)
        let pointerFrame = mux.frame(channel: .input, payload: InputEvent.encode(pointerEvent), sequence: 2)
        let decodedPointer = try XCTUnwrap(InputEvent.decode(mux.parse(pointerFrame)?.payload))
        XCTAssertEqual(decodedPointer, pointerEvent)
        // Clipboard event — mirrors CutText (type 6).
        let clipboardEvent = InputEvent.clipboard(text: "hello")
        let clipFrame = mux.frame(channel: .input, payload: InputEvent.encode(clipboardEvent), sequence: 3)
        let decodedClip = try XCTUnwrap(InputEvent.decode(mux.parse(clipFrame)?.payload))
        XCTAssertEqual(decodedClip, clipboardEvent)
    }

    // MARK: Capture/encode configuration types (§2/§3 behind the consent gate)

    func testEncodeConfigurationDefaultsAndHEVCFlag() {
        let h264 = EncodeConfiguration()
        XCTAssertEqual(h264.codec, .h264, "start with H.264 (§3)")
        XCTAssertTrue(h264.hardwareAcceleration)
        let hevc = EncodeConfiguration(codec: .hevc)
        XCTAssertEqual(hevc.codec, .hevc, "HEVC behind capability flag")
    }

    func testCaptureConfigurationCoversDisplaysAndAudio() {
        let config = CaptureConfiguration(displayIDs: [1, 2], audioEnabled: true, dynamicResolution: true)
        XCTAssertEqual(config.displayIDs.count, 2, "multiple displays (§2)")
        XCTAssertTrue(config.audioEnabled, "audio where enabled (§2)")
        XCTAssertTrue(config.dynamicResolution, "dynamic resolution (§2)")
    }
}
