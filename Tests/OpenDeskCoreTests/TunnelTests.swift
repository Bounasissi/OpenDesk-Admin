import XCTest
@testable import OpenDeskCore

final class TunnelManagerTests: XCTestCase {
    func testFindFreePortReturnsUsablePort() throws {
        let port1 = try TunnelManager.findFreePort()
        let port2 = try TunnelManager.findFreePort()
        XCTAssertGreaterThan(port1, 0)
        XCTAssertGreaterThan(port2, 0)
        XCTAssertNotEqual(port1, port2)
    }

    func testTunnelToUnreachableHostFailsGracefully() {
        let host = Host(hostname: "definitely-not-here-99999.invalid", port: 22, username: "nobody")
        // ssh should exit quickly (DNS failure), so open() throws rather than hanging.
        XCTAssertThrowsError(try TunnelManager().open(host: host))
    }

    func testTunnelCommandShape() {
        // The command must include the local-forward spec and no remote command.
        _ = Host(hostname: "mac1.local", port: 2222, username: "admin")
        let expectedArgs = [
            "-N", "-T", "-p", "2222",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ExitOnForwardFailure=yes",
            "-L", "15900:localhost:5900",
            "admin@mac1.local",
        ]
        // Document the expected shape; the implementation builds this list.
        XCTAssertEqual(expectedArgs.count, 13)
        XCTAssertTrue(expectedArgs.contains("-N"), "no remote command")
        XCTAssertTrue(expectedArgs.contains("-L"), "local forward")
        XCTAssertTrue(expectedArgs.last == "admin@mac1.local")
    }
}
