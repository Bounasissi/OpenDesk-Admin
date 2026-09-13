import Foundation

// MARK: - Plan 14 §6: Adaptive quality controller

/// Measured inputs for one adaptation cycle (Plan 14 §6).
public struct StreamMetrics: Equatable, Sendable {
    public var rttMs: Double
    public var packetLossPercent: Double
    public var bandwidthKbps: Double
    public var encoderPressure: Double
    public var decoderPressure: Double
    public var renderBacklog: Int

    public init(rttMs: Double, packetLossPercent: Double, bandwidthKbps: Double,
                encoderPressure: Double, decoderPressure: Double, renderBacklog: Int) {
        self.rttMs = rttMs
        self.packetLossPercent = packetLossPercent
        self.bandwidthKbps = bandwidthKbps
        self.encoderPressure = encoderPressure
        self.decoderPressure = decoderPressure
        self.renderBacklog = renderBacklog
    }
}

/// One controller decision (Plan 14 §6 outputs).
public struct QualityDecision: Equatable, Sendable {
    public var resolutionScale: Double
    public var bitrateKbps: Double
    public var fps: Int
    public var requestKeyframe: Bool
}

/// Measure-driven adaptive-quality controller (Plan 14 §6).
///
/// Degradation staircase (documented thresholds, §7.5):
/// 1. bitrate clamps to measured bandwidth (headroom ×0.8)
/// 2. FPS steps 30 → 24 → 15 → 10 on sustained pressure/loss
/// 3. resolution steps ×1.0 → 0.9 → 0.75 → 0.5 last (visible quality last)
/// Recovery is conservative: one step per update, keyframe on any up-step.
public struct AdaptiveQualityController: Sendable {
    public var state: Step
    /// Measured bandwidth retained for the bitrate clamp (bit/sec headroom 0.8).
    var lastBandwidthKbps: Double = 40_000

    public enum Step: Int, CaseIterable, Sendable {
        case top = 0        // 1.0 res, 30fps
        case fpsDown = 1    // 1.0 res, 24fps
        case fpsLow = 2     // 0.9 res, 15fps
        case resStep = 3    // 0.75 res, 15fps
        case resLow = 4     // 0.5 res, 10fps

        public var resolutionScale: Double {
            switch self {
            case .top, .fpsDown: return 1.0
            case .fpsLow: return 0.9
            case .resStep: return 0.75
            case .resLow: return 0.5
            }
        }

        public var fps: Int {
            switch self {
            case .top: return 30
            case .fpsDown: return 24
            case .fpsLow, .resStep: return 15
            case .resLow: return 10
            }
        }

        public var tierBitrateKbps: Double {
            switch self {
            case .top: return 12_000
            case .fpsDown: return 8_000
            case .fpsLow: return 5_000
            case .resStep: return 3_000
            case .resLow: return 1_500
            }
        }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { rawValue > 0 ? Step(rawValue: rawValue - 1) : nil }
    }

    public init(state: Step = .top) {
        self.state = state
    }

    public mutating func update(metrics: StreamMetrics) -> QualityDecision {
        lastBandwidthKbps = metrics.bandwidthKbps
        let overloaded =
            metrics.rttMs > 100 ||
            metrics.packetLossPercent > 2 ||
            metrics.bandwidthKbps < 5_000 ||
            metrics.encoderPressure > 0.8 ||
            metrics.decoderPressure > 0.8 ||
            metrics.renderBacklog >= 2

        let healthy =
            metrics.rttMs < 50 &&
            metrics.packetLossPercent < 1 &&
            metrics.bandwidthKbps > 15_000 &&
            metrics.encoderPressure < 0.5 &&
            metrics.decoderPressure < 0.5 &&
            metrics.renderBacklog == 0

        if overloaded, let next = state.next {
            state = next
            return decision(for: next, requestKeyframe: true)
        }
        if healthy, let better = state.previous {
            state = better
            return decision(for: better, requestKeyframe: true)
        }
        return decision(for: state, requestKeyframe: false)
    }

    func decision(for step: Step, requestKeyframe: Bool) -> QualityDecision {
        // Bitrate clamp (§8 degradation test): tier baseline vs available
        // bandwidth ×0.8 headroom — bandwidth collapse clamps bitrate FIRST.
        let clamped = min(step.tierBitrateKbps, max(500, lastBandwidthKbps * 0.8))
        return QualityDecision(
            resolutionScale: step.resolutionScale,
            bitrateKbps: clamped,
            fps: step.fps,
            requestKeyframe: requestKeyframe
        )
    }
}

// MARK: - Plan 14 §4: Channel multiplexer

public enum StreamChannel: String, Codable, Sendable, CaseIterable {
    case control
    case video
    case audio
    case input
    case telemetry
}

/// Wire frame: [channel(1) | sequence(4) | payload]. Typed + sequenced so a
/// single secure transport carries the five §4 channels in order.
public struct ChannelFrame: Equatable, Sendable {
    public let channel: StreamChannel
    public let sequence: UInt32
    public let payload: Data
}

public struct ChannelMultiplexer: Sendable {
    public let channels: [StreamChannel]

    public init(channels: [StreamChannel]) {
        self.channels = channels
    }

    public func frame(channel: StreamChannel, payload: Data, sequence: UInt32) -> Data {
        var data = Data([channelByte(channel)])
        var seq = sequence.bigEndian
        withUnsafeBytes(of: &seq) { data.append(contentsOf: $0) }
        data.append(payload)
        return data
    }

    public func parse(_ data: Data) -> ChannelFrame? {
        guard let first = data.first,
              let channel = channel(forByte: first), data.count >= 5 else { return nil }
        var sequence: UInt32 = 0
        for byte in data[1...4] { sequence = (sequence << 8) | UInt32(byte) }
        return ChannelFrame(channel: channel, sequence: sequence, payload: data.dropFirst(5))
    }

    public func channel(of frame: Data) -> StreamChannel? {
        parse(frame)?.channel
    }

    public func sequence(of frame: Data) -> UInt32 {
        parse(frame)?.sequence ?? 0
    }

    public var channelNames: [String] { channels.map { $0.rawValue } }

    private func channelByte(_ channel: StreamChannel) -> UInt8 {
        UInt8(channels.firstIndex(of: channel) ?? 0)
    }

    private func channel(forByte byte: UInt8) -> StreamChannel? {
        guard Int(byte) < channels.count else { return nil }
        return channels[Int(byte)]
    }

}
