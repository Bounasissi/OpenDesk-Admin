import Foundation

// MARK: - Plan 14 §2/§3: capture + encode configuration (consent-gated impl)

public struct CaptureConfiguration: Equatable, Sendable {
    public var displayIDs: [Int]
    public var audioEnabled: Bool
    public var dynamicResolution: Bool

    public init(displayIDs: [Int], audioEnabled: Bool = false, dynamicResolution: Bool = true) {
        self.displayIDs = displayIDs
        self.audioEnabled = audioEnabled
        self.dynamicResolution = dynamicResolution
    }
}

public enum StreamCodec: String, Codable, Sendable {
    case h264
    case hevc
}

public struct EncodeConfiguration: Equatable, Sendable {
    public var codec: StreamCodec
    public var hardwareAcceleration: Bool

    public init(codec: StreamCodec = .h264, hardwareAcceleration: Bool = true) {
        self.codec = codec
        self.hardwareAcceleration = hardwareAcceleration
    }
}

// MARK: - §2: Session state machine (interruption + permission handling)

public enum StreamingPhase: Equatable, Sendable {
    case idle
    case capturing
    case interrupted(reason: String)
    case stopped

    var isTerminal: Bool { self == .stopped }
    var isInterrupted: Bool {
        if case .interrupted = self { return true }
        return false
    }
}

/// Streaming session phases with interruption recovery and an explicit
/// stopped-by-revocation terminal state (Plan 14 §2: permission changes,
/// capture interruption).
public struct StreamingSessionState {
    public private(set) var phase: StreamingPhase = .idle
    /// A stop-by-revocation cannot silently restart; operator must re-authorize.
    public private(set) var stoppedByRevocation = false

    public init() {}

    public mutating func transition(_ next: StreamingPhase) {
        guard !phase.isTerminal else { return }
        phase = next
        if next == .stopped { stoppedByRevocation = true }
    }

    public mutating func requestTransition(_ next: StreamingPhase) throws {
        guard !phase.isTerminal else {
            throw ConfigurationError.invalidValue(key: "streamingPhase", reason: "session stopped by permission revocation")
        }
        transition(next)
    }

    public var canRestart: Bool {
        phase == .idle || (phase == .stopped && !stoppedByRevocation)
    }
}

// MARK: - §6: Keyframe policy

public enum KeyframeReason: Equatable, Sendable {
    case newViewer
    case qualityRecovery
    case steadyState(lastKeyframeSecondsAgo: Double)
}

/// Keyframe behavior (Plan 14 §6 output): new viewers and quality recovery
/// always keyframe; steady state keyframes on a ≥8s cadence.
public enum StreamKeyframePolicy {
    public static func keyframeNeeded(reason: KeyframeReason) -> Bool {
        switch reason {
        case .newViewer, .qualityRecovery: return true
        case .steadyState(let secondsAgo): return secondsAgo >= 8
        }
    }
}

// MARK: - §4 input channel: event parity with the RFB path (Plan 06 §5)

public enum InputEvent: Equatable, Sendable {
    case key(keysym: UInt32, down: Bool)
    case pointer(x: UInt16, y: UInt16, buttonMask: UInt8)
    case clipboard(text: String)

    /// Wire format: [type(1) | body]. Mirrors RFB KeyEvent (type 4) /
    /// PointerEvent (type 5) / ServerCutText (type 6) semantics.
    public static func encode(_ event: InputEvent) -> Data {
        switch event {
        case .key(let keysym, let down):
            var data = Data([1])
            data.append(down ? 1 : 0)
            let k = keysym.bigEndian
            withUnsafeBytes(of: k) { data.append(contentsOf: $0) }
            return data
        case .pointer(let x, let y, let mask):
            var data = Data([2])
            let xx = x.bigEndian, yy = y.bigEndian
            withUnsafeBytes(of: xx) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: yy) { data.append(contentsOf: $0) }
            data.append(mask)
            return data
        case .clipboard(let text):
            var data = Data([3])
            let bytes = Array(text.utf8)
            let length = UInt32(bytes.count).bigEndian
            withUnsafeBytes(of: length) { data.append(contentsOf: $0) }
            data.append(contentsOf: bytes)
            return data
        }
    }

    public static func decode(_ data: Data?) -> InputEvent? {
        guard let data, let type = data.first else { return nil }
        let body = data.dropFirst()
        switch type {
        case 1:
            guard body.count >= 5 else { return nil }
            let down = body.first == 1
            var keysym: UInt32 = 0
            for byte in body.dropFirst().prefix(4) { keysym = (keysym << 8) | UInt32(byte) }
            return .key(keysym: keysym, down: down)
        case 2:
            guard body.count >= 5 else { return nil }
            let x = UInt16(body[body.startIndex]) << 8 | UInt16(body[body.startIndex + 1])
            let y = UInt16(body[body.startIndex + 2]) << 8 | UInt16(body[body.startIndex + 3])
            return .pointer(x: x, y: y, buttonMask: body[body.startIndex + 4])
        case 3:
            guard body.count >= 4 else { return nil }
            var length: UInt32 = 0
            for byte in body.prefix(4) { length = (length << 8) | UInt32(byte) }
            let textBytes = body.dropFirst(4).prefix(Int(length))
            guard let text = String(data: Data(textBytes), encoding: .utf8) else { return nil }
            return .clipboard(text: text)
        default:
            return nil
        }
    }
}
