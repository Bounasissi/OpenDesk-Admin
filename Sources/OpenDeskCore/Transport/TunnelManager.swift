import Foundation

/// Establishes an SSH local port-forward so the screen viewer can reach a
/// client's VNC server over WAN/VPN (ARD's known LAN-only weakness).
/// The tunnel forwards 127.0.0.1:<localPort> → client's localhost:5900.
public final class TunnelManager: @unchecked Sendable {
    public struct Tunnel {
        public let localPort: UInt16
        public let process: Process
    }

    public enum TunnelError: Error, Equatable {
        case portAllocationFailed
        case tunnelStartFailed(String)
    }

    public init() {}

    /// Start an SSH tunnel to the host's VNC port.
    /// - Returns: the tunnel; connect the RFB client to 127.0.0.1:localPort.
    public func open(host: Host, remoteScreenPort: UInt16 = 5900) throws -> Tunnel {
        // Find a free local port.
        let localPort = try TunnelManager.findFreePort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",                       // no remote command
            "-T",                       // no pty
            "-p", String(host.port),
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ExitOnForwardFailure=yes",
            "-L", "\(localPort):localhost:\(remoteScreenPort)",
            "\(host.username)@\(host.hostname)",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw TunnelError.tunnelStartFailed("ssh tunnel could not start")
        }
        // Give ssh a moment to establish the forward; ExitOnForwardFailure
        // means a failed bind terminates the process.
        Thread.sleep(forTimeInterval: 0.5)
        if !process.isRunning {
            throw TunnelError.tunnelStartFailed("ssh tunnel exited immediately (auth or forward failure)")
        }
        return Tunnel(localPort: localPort, process: process)
    }

    public func close(_ tunnel: Tunnel) {
        if tunnel.process.isRunning {
            tunnel.process.terminate()
        }
    }

    /// Bind port 0 on loopback to discover a free TCP port, then close it.
    static func findFreePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TunnelError.portAllocationFailed }
        defer { Darwin.close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw TunnelError.portAllocationFailed }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard getsocknameResult == 0 else { throw TunnelError.portAllocationFailed }
        let port = UInt16(bigEndian: boundAddr.sin_port)
        guard port != 0 else { throw TunnelError.portAllocationFailed }
        return port
    }
}
