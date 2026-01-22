import Foundation

/// Detects crash loops (3+ crashes in 60 seconds)
///
/// Strategy:
/// - Track crash timestamps
/// - If 3+ crashes in 60-second window, set isInCrashLoop=true
/// - Disable reporting to prevent spam
/// - Reset counter if no crash for > 60 seconds
class CrashLoopDetector {
    static let shared = CrashLoopDetector()

    private var crashTimestamps: [Int64] = []
    private let queue = DispatchQueue(label: "com.crashreporter.crashloop")
    private let crashThreshold = 3  // 3+ crashes = loop
    private let timeWindowSeconds: TimeInterval = 60  // In 60 seconds

    // MARK: - Record Crash

    /// Record a crash timestamp
    /// - Returns: true if crash loop detected, false otherwise
    func recordCrash() -> Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        queue.async {
            // Add current crash timestamp
            self.crashTimestamps.append(now)

            // Remove crashes older than time window
            let cutoffTime = now - Int64(self.timeWindowSeconds * 1000)
            self.crashTimestamps.removeAll { $0 < cutoffTime }
        }

        // Return result synchronously by waiting
        return queue.sync {
            return self.crashTimestamps.count >= self.crashThreshold
        }
    }

    /// Get current crash count in time window
    /// - Returns: Number of crashes in past 60 seconds
    func getCrashCount() -> Int {
        var count = 0
        queue.sync {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let cutoffTime = now - Int64(self.timeWindowSeconds * 1000)
            count = self.crashTimestamps.filter { $0 >= cutoffTime }.count
        }
        return count
    }

    /// Check if currently in crash loop
    /// - Returns: true if 3+ crashes in past 60 seconds
    func isInCrashLoop() -> Bool {
        var inLoop = false
        queue.sync {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let cutoffTime = now - Int64(self.timeWindowSeconds * 1000)
            let recentCrashes = self.crashTimestamps.filter { $0 >= cutoffTime }
            inLoop = recentCrashes.count >= self.crashThreshold
        }
        return inLoop
    }

    /// Clear crash history
    func resetCrashHistory() {
        queue.async {
            self.crashTimestamps.removeAll()
        }
    }

    // MARK: - Get Loop Info

    /// Get information about current crash loop status
    /// - Returns: (isInLoop, crashCount, timeUntilReset)
    func getLoopInfo() -> (isInLoop: Bool, crashCount: Int, timeUntilReset: Int) {
        var result = (isInLoop: false, crashCount: 0, timeUntilReset: 0)

        queue.sync {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let cutoffTime = now - Int64(self.timeWindowSeconds * 1000)

            // Filter recent crashes
            let recentCrashes = self.crashTimestamps.filter { $0 >= cutoffTime }
            result.crashCount = recentCrashes.count
            result.isInLoop = recentCrashes.count >= self.crashThreshold

            // Calculate time until oldest crash leaves the window
            if let oldestCrashTime = recentCrashes.first {
                let timeUntilReset = Int((oldestCrashTime + Int64(self.timeWindowSeconds * 1000) - now) / 1000)
                result.timeUntilReset = max(0, timeUntilReset)
            }
        }

        return result
    }

    // MARK: - Should Report Crash

    /// Determine if crash should be reported (false if in crash loop)
    /// - Returns: true if should report, false if should skip (in crash loop)
    func shouldReportCrash() -> Bool {
        // Don't report if already in crash loop (to avoid spam)
        if isInCrashLoop() {
            return false
        }

        // Record this crash and check if it creates a loop
        let newCount = self.getCrashCount() + 1

        queue.async {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            self.crashTimestamps.append(now)

            // Clean up old timestamps
            let cutoffTime = now - Int64(self.timeWindowSeconds * 1000)
            self.crashTimestamps.removeAll { $0 < cutoffTime }
        }

        // Report if not creating a loop
        return newCount < self.crashThreshold
    }
}
