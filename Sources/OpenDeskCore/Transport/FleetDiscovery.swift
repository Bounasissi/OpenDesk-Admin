import Foundation
import Network

/// Discovers nearby Macs advertising Screen Sharing (RFB/VNC) or SSH services
/// via Bonjour/mDNS. Results are delivered on the main queue.
public final class FleetDiscovery {
    public init() {}
    public static let screenService = "_rfb._tcp"
    public static let sshService = "_ssh._tcp"

    public struct DiscoveredService: Identifiable, Hashable, Sendable {
        public var id: String { "\(service).\(name).\(domain)" }
        public let name: String
        public let service: String
        public let domain: String
        public var hostname: String?
        public var port: Int?
    }

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "opendesk.discovery")
    private var services: [DiscoveredService] = []
    private var onServicesUpdated: (([DiscoveredService]) -> Void)?

    /// Start browsing. `onServicesUpdated` is called on the main queue whenever
    /// the discovered set changes.
    public func start(onServicesUpdated: @escaping ([DiscoveredService]) -> Void) {
        stop()
        self.onServicesUpdated = onServicesUpdated

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjour(type: FleetDiscovery.screenService, domain: nil),
            using: parameters
        )
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var updated: [DiscoveredService] = []
            for result in results {
                if case let .service(name, type, domain, _) = result.endpoint {
                    // Hostname/port resolution happens at connect time.
                    updated.append(DiscoveredService(name: name, service: type, domain: domain))
                }
            }
            // The handler already runs on `queue` — assign directly.
            // Calling queue.sync here traps (libdispatch: "queue already
            // owned by current thread").
            self.services = updated
            DispatchQueue.main.async { onServicesUpdated(updated) }
        }

        browser.start(queue: queue)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        queue.sync { services = [] }
    }

    /// Snapshot of currently known discovered services (thread-safe).
    public var currentServices: [DiscoveredService] {
        queue.sync { services }
    }

    deinit { stop() }
}
