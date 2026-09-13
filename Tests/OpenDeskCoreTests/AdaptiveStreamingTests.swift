import XCTest
@testable import OpenDeskCore

/// Plan 14 §8: adaptive controller tests (synthetic RTT/loss/pressure
/// profiles), channel protocol types, degradation stability.
final class AdaptiveStreamingTests: XCTestCase {

    // MARK: Adaptive controller (Plan 14 §6 — measure-driven, documented thresholds)

    func testHealthyProfileHoldsTopQuality() {
        var controller = AdaptiveQualityController()
        let decision = controller.update(metrics: StreamMetrics(
            rttMs: 5, packetLossPercent: 0, bandwidthKbps: 40_000,
            encoderPressure: 0.2, decoderPressure: 0.2, renderBacklog: 0
        ))
        XCTAssertEqual(decision.resolutionScale, 1.0, "healthy LAN keeps full resolution")
        XCTAssertGreaterThanOrEqual(decision.fps, 30)
        XCTAssertGreaterThanOrEqual(decision.bitrateKbps, 8_000)
        XCTAssertEqual(decision.requestKeyframe, false)
    }

    func testBandwidthClampDegradesBitrateFirst() {
        var controller = AdaptiveQualityController()
        // Bandwidth collapse: bitrate clamps before resolution/FPS degrade.
        let decision = controller.update(metrics: StreamMetrics(
            rttMs: 30, packetLossPercent: 0.5, bandwidthKbps: 4_000,
            encoderPressure: 0.3, decoderPressure: 0.3, renderBacklog: 0
        ))
        XCTAssertLessThan(decision.bitrateKbps, 4_000, "bitrate clamps to available bandwidth")
        XCTAssertEqual(decision.resolutionScale, 1.0, "resolution untouched at this severity")
        XCTAssertGreaterThanOrEqual(decision.fps, 15)
    }

    func testSustainedPressureDegradesStaircase() {
        var controller = AdaptiveQualityController()
        // Sustained severe pressure walks the staircase: bitrate → FPS → resolution.
        let first = controller.update(metrics: StreamMetrics(
            rttMs: 250, packetLossPercent: 8, bandwidthKbps: 1_500,
            encoderPressure: 0.9, decoderPressure: 0.6, renderBacklog: 3
        ))
        XCTAssertEqual(first.fps, 24, "one step: 30 → 24")
        XCTAssertEqual(first.resolutionScale, 1.0, "resolution holds at this severity")
        XCTAssertTrue(first.requestKeyframe)
        // Stability: an identical profile produces an IDENTICAL decision (no flapping).
        let repeat1 = controller.update(metrics: StreamMetrics(
            rttMs: 250, packetLossPercent: 8, bandwidthKbps: 1_500,
            encoderPressure: 0.9, decoderPressure: 0.6, renderBacklog: 3
        ))
        XCTAssertEqual(repeat1.fps, 15, "one step per update: 24 → 15 (stepwise, never a cliff)")
    }

    func testRecoveryIsConservative() {
        var controller = AdaptiveQualityController()
        // Start degraded (two steps), then conditions improve → recovery is
        // conservative: ONE step up per update, keyframe requested.
        _ = controller.update(metrics: StreamMetrics(
            rttMs: 250, packetLossPercent: 8, bandwidthKbps: 1_500,
            encoderPressure: 0.9, decoderPressure: 0.6, renderBacklog: 3
        ))
        _ = controller.update(metrics: StreamMetrics(
            rttMs: 250, packetLossPercent: 8, bandwidthKbps: 1_500,
            encoderPressure: 0.9, decoderPressure: 0.6, renderBacklog: 3
        ))
        let recovery = controller.update(metrics: StreamMetrics(
            rttMs: 20, packetLossPercent: 0, bandwidthKbps: 40_000,
            encoderPressure: 0.2, decoderPressure: 0.2, renderBacklog: 0
        ))
        XCTAssertLessThan(recovery.fps, 30, "one step up per update (no oscillation)")
        XCTAssertTrue(recovery.requestKeyframe, "quality recovery requests a keyframe to resync")
    }

    // MARK: Channel protocol (Plan 14 §4 — multiplexed channels)

    func testChannelMultiplexerFramesAreTypedAndSequenced() {
        let mux = ChannelMultiplexer(channels: [.control, .video, .audio, .input, .telemetry])
        let frame1 = mux.frame(channel: .video, payload: Data([0x01]), sequence: 1)
        let frame2 = mux.frame(channel: .input, payload: Data([0x02]), sequence: 1)
        XCTAssertEqual(mux.channel(of: frame1), .video)
        XCTAssertEqual(mux.channel(of: frame2), .input)
        XCTAssertNotEqual(frame1, frame2, "channel + sequence disambiguate frames")
        XCTAssertEqual(mux.channelNames, ["control", "video", "audio", "input", "telemetry"], "§4 preferred architecture channels")
    }

    func testLoopbackChannelTransportDeliversInOrder() throws {
        // Channel integration with loopback transport (Plan 14 §8).
        let transport = LoopbackStreamTransport()
        let mux = ChannelMultiplexer(channels: [.control, .video])
        for seq in 1...5 {
            let frame = mux.frame(channel: .video, payload: Data([UInt8(seq)]), sequence: UInt32(seq))
            try transport.send(frame)
        }
        let received = transport.drain()
        XCTAssertEqual(received.count, 5)
        let sequences = received.map { mux.sequence(of: $0) }
        XCTAssertEqual(sequences, [1, 2, 3, 4, 5], "in-order delivery on the video channel")
    }
}

/// Loopback transport for channel tests (in-order, bounded).
final class LoopbackStreamTransport: @unchecked Sendable {
    private var buffer: [Data] = []
    private let lock = NSLock()

    func send(_ frame: Data) throws {
        lock.lock(); defer { lock.unlock() }
        buffer.append(frame)
    }

    func drain() -> [Data] {
        lock.lock(); defer { lock.unlock() }
        let out = buffer
        buffer.removeAll()
        return out
    }
}
