import Foundation
import Network

/// Tracks network connectivity changes for crash context
///
/// Monitors:
/// - Network availability (AVAILABLE/CHANGED/LOST)
/// - Connection type (WIFI/CELLULAR/ETHERNET/NONE)
/// - Connected state
/// Stores last 10 network events with timestamp
class NetworkReachabilityTracker {
    static let shared = NetworkReachabilityTracker()

    private var networkChanges: [NetworkChange] = []
    private let maxChanges = 10
    private let queue = DispatchQueue(label: "com.crashreporter.network")
    private var monitor: NWPathMonitor?
    private var lastPath: NWPath?

    struct NetworkChange: Codable {
        let timestamp: Int64      // Milliseconds since epoch
        let event: String         // CHANGED, AVAILABLE, LOST, INITIAL
        let networkType: String   // WIFI, CELLULAR, ETHERNET, NONE
        let isConnected: Bool     // Is device connected?
    }

    // MARK: - Initialization

    init() {
        setupNetworkMonitoring()
    }

    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        self.monitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathChange(path)
        }

        monitor.start(queue: queue)

        // Record initial state
        let initialPath = monitor.currentPath
        recordInitialState(initialPath)
    }

    deinit {
        monitor?.cancel()
    }

    // MARK: - Handle Path Changes

    private func handlePathChange(_ path: NWPath) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // Determine event type
        var event = "INITIAL"
        if let lastPath = lastPath {
            if path.status != lastPath.status {
                event = path.status == .satisfied ? "AVAILABLE" : "LOST"
            } else {
                event = "CHANGED"  // Same status but details changed
            }
        }

        let networkType = getNetworkType(path)
        let isConnected = path.status == .satisfied

        let change = NetworkChange(
            timestamp: timestamp,
            event: event,
            networkType: networkType,
            isConnected: isConnected
        )

        addNetworkChange(change)
        lastPath = path
    }

    private func recordInitialState(_ path: NWPath) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let networkType = getNetworkType(path)
        let isConnected = path.status == .satisfied

        let initialChange = NetworkChange(
            timestamp: timestamp,
            event: "INITIAL",
            networkType: networkType,
            isConnected: isConnected
        )

        queue.async {
            self.networkChanges.append(initialChange)
            self.lastPath = path
        }
    }

    // MARK: - Add Network Change

    private func addNetworkChange(_ change: NetworkChange) {
        queue.async {
            self.networkChanges.append(change)

            // Keep only last 10 changes
            if self.networkChanges.count > self.maxChanges {
                self.networkChanges.removeFirst()
            }
        }
    }

    // MARK: - Get Network Changes

    func getNetworkChanges() -> [NetworkChange] {
        var result: [NetworkChange] = []
        queue.sync {
            result = self.networkChanges
        }
        return result
    }

    // MARK: - Check if Network Was Recently Lost

    func wasNetworkRecentlyLost(withinSeconds: Int = 30) -> Bool {
        let cutoffTime = Int64(Date().timeIntervalSince1970 * 1000) - Int64(withinSeconds * 1000)

        for change in getNetworkChanges() {
            if change.timestamp > cutoffTime && !change.isConnected {
                return true
            }
        }

        return false
    }

    // MARK: - Get Current Network Type

    func getCurrentNetworkType() -> String {
        guard let monitor = monitor else { return "NONE" }
        return getNetworkType(monitor.currentPath)
    }

    // MARK: - Helper Methods

    private func getNetworkType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WIFI"
        } else if path.usesInterfaceType(.cellular) {
            return "CELLULAR"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "ETHERNET"
        } else if path.usesInterfaceType(.loopback) {
            return "LOOPBACK"
        } else {
            return "NONE"
        }
    }

    // MARK: - Clear History

    func clearNetworkChanges() {
        queue.async {
            self.networkChanges.removeAll()
        }
    }
}
