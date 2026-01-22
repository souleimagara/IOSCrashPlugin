import Foundation

/// Tracks SDK operations and context for crash reporting
/// Used by Unity bridge to record what operation was in progress when crash occurred
/// Also stores SDK context (version, component, etc.) for SLO monitoring
class OperationTracker {
    static let shared = OperationTracker()

    private let lock = NSLock()

    // MARK: - SDK Context (Common SLO fields)

    private(set) var sdkVersion: String = ""
    private(set) var crashReporterPluginVersion: String = "1.0.0"
    private(set) var platform: String = "iOS"
    private(set) var initFailurePoint: String = ""
    private(set) var responsibleComponent: String = ""

    // MARK: - Operation Tracking

    private(set) var currentOperation: String?
    private(set) var lastSuccessfulOperation: String?
    private(set) var lastFailedOperation: String?
    private(set) var lastFailureReason: String?
    private(set) var operationContext: [String: String] = [:]

    private init() {}

    // MARK: - Operation Methods

    /// Set the current operation in progress
    func setCurrentOperation(_ operation: String?) {
        lock.lock()
        defer { lock.unlock() }
        currentOperation = operation
        print("📊 [OperationTracker] Current operation: \(operation ?? "nil")")
    }

    /// Get the current operation in progress
    func getCurrentOperation() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return currentOperation
    }

    /// Record a successful operation
    func setLastSuccessfulOperation(_ operation: String) {
        lock.lock()
        defer { lock.unlock() }
        lastSuccessfulOperation = operation
        print("✅ [OperationTracker] Successful operation: \(operation)")
    }

    /// Get the last successful operation
    func getLastSuccessfulOperation() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastSuccessfulOperation
    }

    /// Record a failed operation
    func setLastFailedOperation(_ operation: String, reason: String) {
        lock.lock()
        defer { lock.unlock() }
        lastFailedOperation = operation
        lastFailureReason = reason
        print("❌ [OperationTracker] Failed operation: \(operation) - \(reason)")
    }

    /// Get the last failed operation
    func getLastFailedOperation() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastFailedOperation
    }

    /// Get the last failure reason
    func getLastFailureReason() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastFailureReason
    }

    /// Clear all tracked operations
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        currentOperation = nil
        lastSuccessfulOperation = nil
        lastFailedOperation = nil
        lastFailureReason = nil
    }

    /// Get all tracked data as a dictionary for crash reports
    func toMap() -> [String: Any?] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "currentOperation": currentOperation,
            "lastSuccessfulOperation": lastSuccessfulOperation,
            "lastFailedOperation": lastFailedOperation,
            "lastFailureReason": lastFailureReason
        ]
    }

    // MARK: - SDK Context Methods

    /// Set the ZBD SDK version (called from Unity)
    func setSDKVersion(_ version: String) {
        lock.lock()
        defer { lock.unlock() }
        sdkVersion = version
        print("📊 [OperationTracker] SDK Version set: \(version)")
    }

    /// Get the ZBD SDK version
    func getSDKVersion() -> String {
        lock.lock()
        defer { lock.unlock() }
        return sdkVersion
    }

    /// Set the crash reporter plugin version
    func setCrashReporterPluginVersion(_ version: String) {
        lock.lock()
        defer { lock.unlock() }
        crashReporterPluginVersion = version
        print("📊 [OperationTracker] Crash Reporter Plugin Version set: \(version)")
    }

    /// Get the crash reporter plugin version
    func getCrashReporterPluginVersion() -> String {
        lock.lock()
        defer { lock.unlock() }
        return crashReporterPluginVersion
    }

    /// Set the platform (Android, iOS, Unity)
    func setPlatform(_ platformName: String) {
        lock.lock()
        defer { lock.unlock() }
        platform = platformName
        print("📊 [OperationTracker] Platform set: \(platformName)")
    }

    /// Get the platform
    func getPlatform() -> String {
        lock.lock()
        defer { lock.unlock() }
        return platform
    }

    /// Set the SDK component that caused the crash (for SDK-related crashes)
    func setResponsibleComponent(_ component: String) {
        lock.lock()
        defer { lock.unlock() }
        responsibleComponent = component
        print("📊 [OperationTracker] Responsible component set: \(component)")
    }

    /// Get the responsible SDK component
    func getResponsibleComponent() -> String {
        lock.lock()
        defer { lock.unlock() }
        return responsibleComponent
    }

    /// Set where in SDK init the failure occurred (if applicable)
    func setInitFailurePoint(_ failurePoint: String) {
        lock.lock()
        defer { lock.unlock() }
        initFailurePoint = failurePoint
        print("📊 [OperationTracker] Init failure point set: \(failurePoint)")
    }

    /// Get the init failure point
    func getInitFailurePoint() -> String {
        lock.lock()
        defer { lock.unlock() }
        return initFailurePoint
    }

    /// Set additional context for the current operation
    func setOperationContext(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        operationContext[key] = value
    }

    /// Get operation context
    func getOperationContext() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return operationContext
    }

    /// Clear operation context
    func clearOperationContext() {
        lock.lock()
        defer { lock.unlock() }
        operationContext.removeAll()
    }

    /// Check if crash is related to ZBD SDK based on stack trace analysis
    func isSDKRelatedCrash(_ stackTrace: String) -> Bool {
        let sdkPatterns = [
            "com.zbd.",
            "ZBD",
            "ZBDSDK",
            "ZBDUserController",
            "ZBDSignUpController",
            "ZBDSendRewardController",
            "ZBDCrashReporter",
            "ZBDAndroidCrashBridge",
            "crashreporter.library"
        ]
        return sdkPatterns.contains { stackTrace.contains($0) }
    }

    /// Determine which SDK component is responsible based on stack trace
    func determineResponsibleComponent(_ stackTrace: String) -> String {
        if stackTrace.contains("ZBDUserController") {
            return "ZBDUserController"
        } else if stackTrace.contains("ZBDSignUpController") {
            return "ZBDSignUpController"
        } else if stackTrace.contains("ZBDSendRewardController") {
            return "ZBDSendRewardController"
        } else if stackTrace.contains("ZBDCrashReporter") {
            return "ZBDCrashReporter"
        } else if stackTrace.contains("ZBDAndroidCrashBridge") {
            return "ZBDAndroidCrashBridge"
        } else if stackTrace.contains("crashreporter.library") {
            return "CrashReporterLibrary"
        } else if stackTrace.contains("ZBD") {
            return "ZBD_Unknown"
        } else {
            return ""
        }
    }
}
