import SwiftUI
import AppKit
import OpenDeskCore

/// The Screen Viewer window: connects to a target host and renders the live
/// framebuffer. Supports observe (default) and control (input injection) modes.
struct ScreenViewerView: View {
    @ObservedObject var streamer: ScreenStreamer
    @State private var password = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if streamer.isConnected {
                ScreenEventCatcher(streamer: streamer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(streamer.status)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack {
                        SecureField("VNC password (if required)", text: $password)
                            .frame(maxWidth: 220)
                        Button("Connect with password") {
                            streamer.stopStreaming()
                            let target = streamer.host
                            let pw = password.isEmpty ? nil : password
                            Task { @MainActor in
                                let replacement = ScreenStreamer(host: target, password: pw)
                                replacement.startStreaming()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var toolbar: some View {
        HStack {
            Text(streamer.host.hostname)
                .font(.headline)
            Text(streamer.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Toggle("Control", isOn: Binding(
                get: { streamer.controlMode },
                set: { streamer.controlMode = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Button("Disconnect") {
                streamer.stopStreaming()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// NSView hosting the streamed frame and routing keyboard/pointer events to
/// the RFB connection when control mode is on.
struct ScreenEventCatcher: NSViewRepresentable {
    @ObservedObject var streamer: ScreenStreamer

    func makeNSView(context: Context) -> EventCatcherNSView {
        let view = EventCatcherNSView()
        view.streamer = streamer
        return view
    }

    func updateNSView(_ nsView: EventCatcherNSView, context: Context) {
        nsView.streamer = streamer
    }

    final class EventCatcherNSView: NSView {
        var streamer: ScreenStreamer?
        private var leftButtonDown = false
        private var rightButtonDown = false
        private var middleButtonDown = false

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let streamer else { return }
            if let image = MainActor.assumeIsolated({ streamer.frame }) {
                image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            } else {
                NSColor.black.setFill()
                dirtyRect.fill()
            }
        }

        // MARK: Pointer events

        override func mouseMoved(with event: NSEvent) {
            sendPointer(event: event, buttonMask: 0)
        }

        override func mouseDragged(with event: NSEvent) {
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func mouseDown(with event: NSEvent) {
            leftButtonDown = true
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func mouseUp(with event: NSEvent) {
            leftButtonDown = false
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func rightMouseDown(with event: NSEvent) {
            rightButtonDown = true
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func rightMouseUp(with event: NSEvent) {
            rightButtonDown = false
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func otherMouseDown(with event: NSEvent) {
            middleButtonDown = true
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func otherMouseUp(with event: NSEvent) {
            middleButtonDown = false
            sendPointer(event: event, buttonMask: buttonMask())
        }

        override func scrollWheel(with event: NSEvent) {
            // Button masks 0x08 / 0x10 = wheel up/down (RFB button 4/5).
            let mask: UInt8 = event.deltaY < 0 ? 0x08 : 0x10
            sendPointer(event: event, buttonMask: mask)
            // Release immediately (wheel press is transient).
            sendPointer(event: event, buttonMask: 0)
        }

        // MARK: Keyboard events

        override func keyDown(with event: NSEvent) {
            guard let streamer, streamer.controlMode else { return }
            let keysym = KeysymMap.keysym(
                character: event.charactersIgnoringModifiers?.first,
                keyCode: event.keyCode
            )
            guard let keysym else { return }
            streamer.sendKeyEvent(keysym: keysym, down: true)
            streamer.sendKeyEvent(keysym: keysym, down: false)
        }

        override func flagsChanged(with event: NSEvent) {
            guard let streamer, streamer.controlMode else { return }
            sendModifier(keysym: KeysymMap.SpecialKeysym.shiftLeft.rawValue,
                         active: event.modifierFlags.contains(.shift))
            sendModifier(keysym: KeysymMap.SpecialKeysym.controlLeft.rawValue,
                         active: event.modifierFlags.contains(.control))
            sendModifier(keysym: KeysymMap.SpecialKeysym.altLeft.rawValue,
                         active: event.modifierFlags.contains(.option))
            sendModifier(keysym: KeysymMap.SpecialKeysym.metaRight.rawValue,
                         active: event.modifierFlags.contains(.command))
        }

        // MARK: Helpers

        private func framebufferCoordinates(_ event: NSEvent) -> (UInt16, UInt16)? {
            guard let streamer,
                  let frame = MainActor.assumeIsolated({ streamer.frame }) else { return nil }
            let point = convert(event.locationInWindow, from: nil)
            let scaleX = CGFloat(frame.size.width) / max(bounds.width, 1)
            let scaleY = CGFloat(frame.size.height) / max(bounds.height, 1)
            let x = max(0, min(CGFloat(frame.size.width) - 1, point.x * scaleX))
            let y = max(0, min(CGFloat(frame.size.height) - 1, (bounds.height - point.y) * scaleY))
            return (UInt16(x), UInt16(y))
        }

        private func sendPointer(event: NSEvent, buttonMask: UInt8) {
            guard let streamer, streamer.controlMode,
                  let (x, y) = framebufferCoordinates(event) else { return }
            streamer.sendPointerEvent(x: x, y: y, buttonMask: buttonMask)
            needsDisplay = true
        }

        private func sendModifier(keysym: UInt32, active: Bool) {
            streamer?.sendKeyEvent(keysym: keysym, down: active)
        }

        private func buttonMask() -> UInt8 {
            var mask: UInt8 = 0
            if leftButtonDown { mask |= 0x01 }
            if middleButtonDown { mask |= 0x02 }
            if rightButtonDown { mask |= 0x04 }
            return mask
        }
    }
}
