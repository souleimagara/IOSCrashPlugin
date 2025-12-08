import Foundation

/// Detects crashes that occur during app startup (before CrashReporter initialization)
///
/// Strategy: Write an initialization flag at app launch, clear it after init completes
/// If the flag still exists on next launch, it means app crashed during startup
struct StartupCrashDetector {
    private static let initFlagFileName = "crash_reporter_init.flag"

    // MARK: - Get Flag Path

    static func getInitFlagPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let documentsPath = paths.first else { return "" }
        return (documentsPath as NSString).appendingPathComponent(initFlagFileName)
    }

    // MARK: - Create Init Flag (Called at App Launch)

    /// Call this as early as possible in app lifecycle (e.g., in UIApplicationDelegate.didFinishLaunchingWithOptions)
    static func markStartup() {
        let flagPath = getInitFlagPath()
        let timestamp = Date().timeIntervalSince1970

        do {
            let data = "startup_in_progress:\(timestamp)".data(using: .utf8) ?? Data()
            try data.write(to: URL(fileURLWithPath: flagPath), options: .atomic)
        } catch {
            print("⚠️ StartupCrashDetector: Failed to write startup flag - \(error)")
        }
    }

    // MARK: - Clear Init Flag (Called after CrashReporter initialized)

    /// Call this after CrashReporter.initialize() completes successfully
    static func markInitComplete() {
        let flagPath = getInitFlagPath()
        try? FileManager.default.removeItem(atPath: flagPath)
    }

    // MARK: - Detect Startup Crash

    /// Check if app crashed during startup
    static func detectStartupCrash() -> StartupCrashData? {
        let flagPath = getInitFlagPath()
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: flagPath) else {
            // Normal startup - no flag means no previous crash
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: flagPath))
            guard let content = String(data: data, encoding: .utf8) else { return nil }

            // Parse: "startup_in_progress:timestamp"
            let parts = content.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let timestamp = TimeInterval(parts[1]) else { return nil }

            return StartupCrashData(crashTimestamp: Int64(timestamp * 1000))
        } catch {
            return nil
        }
    }

    // MARK: - Delete Flag

    static func deleteInitFlag() {
        let flagPath = getInitFlagPath()
        try? FileManager.default.removeItem(atPath: flagPath)
    }
}

// MARK: - Startup Crash Data

struct StartupCrashData {
    let crashTimestamp: Int64
}
