import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor.
@Observable
@MainActor
final class NetworkMonitor {
    var isConnected: Bool = true
    var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cosyposts.networkmonitor")

    enum ConnectionType: Sendable {
        case wifi
        case cellular
        case wired
        case unknown
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let type: ConnectionType
            if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = .wired
            } else {
                type = .unknown
            }
            Task { @MainActor [weak self] in
                self?.isConnected = connected
                self?.connectionType = type
            }
        }
        monitor.start(queue: queue)
    }
}
