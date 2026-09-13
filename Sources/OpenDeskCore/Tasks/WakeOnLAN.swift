import Foundation

/// Wake-on-LAN magic packet construction and transmission.
/// Packet layout: 6 × 0xFF followed by the target MAC repeated 16 times (102 bytes).
public enum WakeOnLAN {
    public enum WOLError: Error, Equatable {
        case invalidMACAddress(String)
        case socketSendFailed
    }

    /// Build the magic packet payload for a MAC address.
    /// Accepts "AA:BB:CC:DD:EE:FF", "AA-BB-CC-DD-EE-FF", or "aabbccddeeff".
    public static func magicPacket(mac: String) throws -> Data {
        var octets = [UInt8]()
        let separators = CharacterSet(charactersIn: ":-")
        let cleaned = mac.unicodeScalars
            .map { separators.contains($0) ? " " : String($0) }
            .joined()
            .replacingOccurrences(of: " ", with: ":")

        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 6 {
            for part in parts {
                guard let octet = UInt8(part, radix: 16), part.count == 2 else {
                    throw WOLError.invalidMACAddress(mac)
                }
                octets.append(octet)
            }
        } else if cleaned.count == 12, cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: ":") ) == nil {
            var index = cleaned.startIndex
            for _ in 0..<6 {
                let next = cleaned.index(index, offsetBy: 2)
                guard let octet = UInt8(cleaned[index..<next], radix: 16) else {
                    throw WOLError.invalidMACAddress(mac)
                }
                octets.append(octet)
                index = next
            }
        } else {
            throw WOLError.invalidMACAddress(mac)
        }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: octets)
        }
        return Data(packet)
    }

    /// Broadcast the magic packet on the local network (UDP port 9 by default).
    /// - Parameters:
    ///   - mac: target NIC address
    ///   - port: WOL UDP port (9 = discard, 7 = echo are conventional)
    ///   - interface: optional broadcast address override (e.g. "192.168.1.255")
    public static func wake(mac: String, port: UInt16 = 9, broadcastAddress: String = "255.255.255.255") throws {
        let packet = try magicPacket(mac: mac)
        try sendUDPBroadcast(payload: packet, port: port, broadcastAddress: broadcastAddress)
    }

    /// Wake a host using its registered MAC (no-op if no MAC is registered).
    public static func wake(host: Host, port: UInt16 = 9) throws {
        guard let mac = host.macAddress, !mac.isEmpty else {
            throw WOLError.invalidMACAddress("host \(host.hostname) has no MAC address registered")
        }
        try wake(mac: mac, port: port)
    }

    static func sendUDPBroadcast(payload: Data, port: UInt16, broadcastAddress: String) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw WOLError.socketSendFailed }
        defer { Darwin.close(fd) }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard let cBroadcast = broadcastAddress.cString(using: .utf8) else {
            throw WOLError.socketSendFailed
        }
        guard inet_pton(AF_INET, cBroadcast, &addr.sin_addr) == 1 else {
            throw WOLError.socketSendFailed
        }

        var bytes = [UInt8](payload)
        let sent = bytes.withUnsafeMutableBytes { raw in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(fd, raw.baseAddress, raw.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == payload.count else { throw WOLError.socketSendFailed }
    }
}
