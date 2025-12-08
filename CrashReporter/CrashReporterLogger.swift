import Foundation
import os

/// Centralized logging for CrashReporter
/// Uses os_log for production-safe logging with proper levels
struct CrashReporterLogger {
    private static let subsystem = "com.crashreporter"

    // Create loggers for different categories
    static let crashHandler = OSLog(subsystem: subsystem, category: "CrashHandler")
    static let crashStorage = OSLog(subsystem: subsystem, category: "CrashStorage")
    static let crashSender = OSLog(subsystem: subsystem, category: "CrashSender")
    static let general = OSLog(subsystem: subsystem, category: "General")

    // MARK: - Logging Methods

    static func debug(_ message: String, log: OSLog? = nil) {
        os_log("DEBUG: %{public}@", log: log ?? general, type: .debug, message)
    }

    static func info(_ message: String, log: OSLog? = nil) {
        os_log("ℹ️ %{public}@", log: log ?? general, type: .info, message)
    }

    static func warning(_ message: String, log: OSLog? = nil) {
        os_log("⚠️ %{public}@", log: log ?? general, type: .default, message)
    }

    static func error(_ message: String, log: OSLog? = nil) {
        os_log("❌ %{public}@", log: log ?? general, type: .error, message)
    }

    static func critical(_ message: String, log: OSLog? = nil) {
        os_log("🔥 %{public}@", log: log ?? general, type: .fault, message)
    }
}
