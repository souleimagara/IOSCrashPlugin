import Foundation

/// Detects watchdog timeout crashes
///
/// Strategy: Periodically write a heartbeat file with current timestamp
/// If heartbeat is old (>5 seconds), it means watchdog killed the app
struct WatchdogDetector {
    private static let heartbeatFileName = "crash_reporter_heartbeat.json"
    private static let watchdogThresholdSeconds: TimeInterval = 5  // Watchdog typically ~2-10 seconds

    private static var heartbeatTimer: Timer?
    private static let heartbeatQueue = DispatchQueue(label: "com.crashreporter.watchdog")

    // MARK: - Get Heartbeat Path

    static func getHeartbeatPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let documentsPath = paths.first else { return "" }
        return (documentsPath as NSString).appendingPathComponent(heartbeatFileName)
    }

    // MARK: - Start Heartbeat (Called after CrashReporter initializes)

    /// Start writing periodic heartbeat to detect watchdog timeouts
    static func startHeartbeat() {
        // Write initial heartbeat immediately
        writeHeartbeat()

        // Schedule periodic heartbeat (every 2 seconds - before watchdog threshold)
        DispatchQueue.main.async {
            heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                heartbeatQueue.async {
                    writeHeartbeat()
                }
            }
        }
    }

    // MARK: - Stop Heartbeat (Called on app termination)

    static func stopHeartbeat() {
        DispatchQueue.main.async {
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
        }
    }

    // MARK: - Write Heartbeat

    private static func writeHeartbeat() {
        let heartbeatPath = getHeartbeatPath()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        let heartbeatData: [String: Any] = [
            "timestamp": timestamp,
            "status": "alive"
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: heartbeatData)
            try jsonData.write(to: URL(fileURLWithPath: heartbeatPath), options: .atomic)
        } catch {
            // Silently fail - don't disrupt app
        }
    }

    // MARK: - Detect Watchdog Timeout

    /// Check if app was killed by watchdog on previous run
    static func detectWatchdogTimeout() -> WatchdogCrashData? {
        let heartbeatPath = getHeartbeatPath()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: heartbeatPath) else {
            // No heartbeat file - normal startup
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: heartbeatPath))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            guard let heartbeatTimestamp = json["timestamp"] as? Int64 else {
                return nil
            }

            let lastHeartbeat = TimeInterval(heartbeatTimestamp) / 1000.0
            let now = Date().timeIntervalSince1970
            let timeSinceLastHeartbeat = now - lastHeartbeat

            // If heartbeat is older than threshold, watchdog likely killed the app
            if timeSinceLastHeartbeat > watchdogThresholdSeconds {
                return WatchdogCrashData(
                    heartbeatTimestamp: heartbeatTimestamp,
                    timeSinceLastHeartbeat: Int64(timeSinceLastHeartbeat * 1000)
                )
            }

            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Delete Heartbeat

    static func deleteHeartbeat() {
        let heartbeatPath = getHeartbeatPath()
        try? FileManager.default.removeItem(atPath: heartbeatPath)
    }
}

// MARK: - Watchdog Crash Data

struct WatchdogCrashData {
    let heartbeatTimestamp: Int64  // Last time app was alive
    let timeSinceLastHeartbeat: Int64  // Milliseconds since heartbeat
}
