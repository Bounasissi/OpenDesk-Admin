import Foundation

// MARK: - Plan 14 §2/§3: capture + encode configuration

public struct CaptureConfiguration: Equatable, Sendable {
    public var displayIDs: [Int]
    public var audioEnabled: Bool
    public var dynamicResolution: Bool
    public var framesPerSecond: Int

    public init(
        displayIDs: [Int],
        audioEnabled: Bool = false,
        dynamicResolution: Bool = true,
        framesPerSecond: Int = 30
    ) {
        self.displayIDs = displayIDs
        self.audioEnabled = audioEnabled
        self.dynamicResolution = dynamicResolution
        self.framesPerSecond = framesPerSecond
    }

    /// Returns the selected displays after validating the request against the
    /// current shareable-content snapshot. Kept framework-free for unit tests.
    public func validatedDisplays(available: [CaptureDisplayDescriptor]) throws -> [CaptureDisplayDescriptor] {
        guard !displayIDs.isEmpty else {
            throw ConfigurationError.invalidValue(key: "displayIDs", reason: "at least one display is required")
        }
        guard Set(displayIDs).count == displayIDs.count else {
            throw ConfigurationError.invalidValue(key: "displayIDs", reason: "display identifiers must be unique")
        }
        guard (1...60).contains(framesPerSecond) else {
            throw ConfigurationError.invalidValue(key: "framesPerSecond", reason: "must be between 1 and 60")
        }
        guard Set(available.map(\.id)).count == available.count else {
            throw ConfigurationError.invalidValue(key: "availableDisplays", reason: "display identifiers must be unique")
        }
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        return try displayIDs.map { id in
            guard let display = byID[id] else {
                throw ConfigurationError.invalidValue(key: "displayIDs", reason: "display \(id) is not available")
            }
            guard display.width > 0, display.height > 0 else {
                throw ConfigurationError.invalidValue(key: "displayDimensions", reason: "display dimensions must be positive")
            }
            return display
        }
    }

    /// Deterministic per-display plan consumed by the ScreenCaptureKit adapter.
    /// System audio is attached once to avoid duplicate audio frames when
    /// multiple displays are captured concurrently.
    public func streamPlans(available: [CaptureDisplayDescriptor]) throws -> [CaptureStreamPlan] {
        try validatedDisplays(available: available).enumerated().map { index, display in
            CaptureStreamPlan(
                display: display,
                framesPerSecond: framesPerSecond,
                capturesAudio: audioEnabled && index == 0,
                dynamicResolution: dynamicResolution
            )
        }
    }
}

public struct CaptureStreamPlan: Equatable, Sendable {
    public let display: CaptureDisplayDescriptor
    public let framesPerSecond: Int
    public let capturesAudio: Bool
    public let dynamicResolution: Bool

    public init(display: CaptureDisplayDescriptor, framesPerSecond: Int, capturesAudio: Bool, dynamicResolution: Bool) {
        self.display = display
        self.framesPerSecond = framesPerSecond
        self.capturesAudio = capturesAudio
        self.dynamicResolution = dynamicResolution
    }
}

/// Framework-neutral display snapshot from ScreenCaptureKit shareable content.
public struct CaptureDisplayDescriptor: Equatable, Codable, Sendable {
    public let id: Int
    public let width: Int
    public let height: Int

    public init(id: Int, width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }
}

/// Metadata emitted for each complete video sample. Coordinates are in pixels;
/// timestamp is the sample presentation time expressed in nanoseconds.
public struct CaptureFrameMetadata: Equatable, Codable, Sendable {
    public let displayID: Int
    public let width: Int
    public let height: Int
    public let timestampNanoseconds: Int64
    public let contentX: Double
    public let contentY: Double
    public let contentWidth: Double
    public let contentHeight: Double
    public let scaleFactor: Double

    public init(
        displayID: Int,
        width: Int,
        height: Int,
        timestampNanoseconds: Int64,
        contentX: Double,
        contentY: Double,
        contentWidth: Double,
        contentHeight: Double,
        scaleFactor: Double
    ) {
        self.displayID = displayID
        self.width = width
        self.height = height
        self.timestampNanoseconds = timestampNanoseconds
        self.contentX = contentX
        self.contentY = contentY
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.scaleFactor = scaleFactor
    }

    public var hasValidGeometry: Bool {
        width > 0 && height > 0 && contentWidth > 0 && contentHeight > 0 && scaleFactor > 0 &&
            [contentX, contentY, contentWidth, contentHeight, scaleFactor].allSatisfy(\.isFinite)
    }
}

public enum StreamCodec: String, Codable, Sendable {
    case h264
    case hevc
}

public struct EncodeConfiguration: Equatable, Sendable {
    public var codec: StreamCodec
    public var hardwareAcceleration: Bool
    public var averageBitrateKbps: Int
    public var maxKeyframeIntervalSeconds: Int

    public init(
        codec: StreamCodec = .h264,
        hardwareAcceleration: Bool = true,
        averageBitrateKbps: Int = 6_000,
        maxKeyframeIntervalSeconds: Int = 2
    ) {
        self.codec = codec
        self.hardwareAcceleration = hardwareAcceleration
        self.averageBitrateKbps = averageBitrateKbps
        self.maxKeyframeIntervalSeconds = maxKeyframeIntervalSeconds
    }

    public func validate(width: Int, height: Int, framesPerSecond: Int) throws {
        guard (1...16_384).contains(width), (1...16_384).contains(height) else {
            throw ConfigurationError.invalidValue(key: "encodeDimensions", reason: "width and height must be between 1 and 16384 pixels")
        }
        guard (1...60).contains(framesPerSecond) else {
            throw ConfigurationError.invalidValue(key: "framesPerSecond", reason: "must be between 1 and 60")
        }
        guard (64...100_000).contains(averageBitrateKbps) else {
            throw ConfigurationError.invalidValue(key: "averageBitrateKbps", reason: "must be between 64 and 100000")
        }
        guard (1...10).contains(maxKeyframeIntervalSeconds) else {
            throw ConfigurationError.invalidValue(key: "maxKeyframeIntervalSeconds", reason: "must be between 1 and 10 seconds")
        }
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
