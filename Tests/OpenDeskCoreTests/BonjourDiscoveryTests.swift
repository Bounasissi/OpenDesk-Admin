import XCTest
import Network
@testable import OpenDeskCore

/// §25 gap #19: headless Bonjour discovery test — publish a real mDNS
/// service and discover it with the same browsing stack the admin app uses.
final class BonjourDiscoveryTests: XCTestCase {

    func testBrowseDiscoversPublishedService() throws {
        // Publish via NetService (reliable cross-version mDNS publish).
        // Publish under the ACTUAL Screen Sharing service type the admin app
        // browses (_rfb._tcp) — a stand-in for a real Mac advertising it.
        let service = NetService(domain: "", type: "_rfb._tcp.", name: "opendesk-selftest", port: 5901)
        // Hold the delegate strongly: NetService.delegate is unowned(unsafe).
        let publishDelegate = BonjourPublishDelegate(onPublish: { })
        service.delegate = publishDelegate
        service.schedule(in: .main, forMode: RunLoop.Mode.default)
        service.publish()

        let discovery = FleetDiscovery()
        var discoveredNames: [String] = []
        let lock = NSLock()
        let found = expectation(description: "service discovered")

        discovery.start(onServicesUpdated: { services in
            lock.lock()
            let names = services.map { $0.name }
            if names.contains("opendesk-selftest") && !discoveredNames.contains("opendesk-selftest") {
                discoveredNames = names
                found.fulfill()
            }
            lock.unlock()
        })

        // Wait for discovery on a background queue (NetService publish runs on main).
        let result = XCTWaiter.wait(for: [found], timeout: 15)
        discovery.stop()
        service.stop()
        XCTAssertEqual(result, .completed, "published service must be discovered; saw: \(discoveredNames)")
    }
}

/// NetService delegate bridging publish-success to a semaphore.
final class BonjourPublishDelegate: NSObject, NetServiceDelegate {
    let onPublish: () -> Void
    init(onPublish: @escaping () -> Void) { self.onPublish = onPublish }

    func netServiceDidPublish(_ sender: NetService) {
        print("BONJOUR published on port \(sender.port)")
        onPublish()
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("BONJOUR publish failed: \(errorDict)")
        onPublish()
    }
}
