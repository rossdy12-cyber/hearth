import Foundation
import Network

/// Knows whether the phone is on mobile data, so music can use the mobile-data quality.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// True on mobile data (or a hotspot / Low Data connection), even with Tailscale on top.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let expensive = path.isExpensive || path.usesInterfaceType(.cellular)
            Task { @MainActor in
                NetworkMonitor.shared.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.hearth.network"))
    }

    /// Call once at launch so the first answer is ready before music starts.
    func start() {}
}
