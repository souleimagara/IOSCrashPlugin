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

    /// Extract the faulting library/image from a crash stack trace.
    /// Apple backtrace frames look like: "2   libil2cpp.so   0x0000.. symbol + 12".
    /// Skips our own crash-reporter frames and system frames to find the first frame
    /// that represents the actual faulting code. Returns "" for managed/empty stacks.
    func extractFaultingLibrary(_ stackTrace: String) -> String {
        // Our handler + system libs sit on top of the stack — skip them all so we report
        // the first *app* image where the crash actually originated (UnityFramework = engine,
        // the game's own binary, etc.).
        let skip = ["CrashReporter", "libsystem", "libc++", "libdyld", "libobjc", "dyld", "???"]
        for rawLine in stackTrace.split(separator: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let cols = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            // Standard frame: "<index> <image> <address> <symbol...>"
            guard cols.count >= 2, Int(cols[0]) != nil else { continue }
            let image = String(cols[1])
            if skip.contains(where: { image.contains($0) }) { continue }
            return image
        }
        return ""
    }

    /// Compute confidence that this crash was caused by ZBD SDK code.
    ///  - "high":   a real ZBD symbol is present in the stack (debug/unstripped builds)
    ///  - "medium": a ZBD operation was ACTIVELY in-flight when the crash happened
    ///  - "low":    a ZBD operation had recently failed but already ended — weak/coincidental
    ///  - "none":   no ZBD signal — most likely game or engine code
    ///
    /// IMPORTANT: in IL2CPP release builds, ZBD C# and game C# share the same stripped
    /// image, so "high" is NOT reachable for managed crashes on-device. Trustworthy
    /// ZBD-vs-game attribution there needs backend symbolication. Treat medium/low as hints.
    func getSDKConfidence(_ stackTrace: String, _ faultingLibrary: String) -> String {
        let strongPatterns = [
            "com.zbd.", "ZBD.", "ZBDSDK", "ZBDUserController", "ZBDSignUpController",
            "ZBDSendRewardController", "ZBDCrashReporter", "ZBDAndroidCrashBridge",
            "crashreporter.library"
        ]
        if strongPatterns.contains(where: { stackTrace.contains($0) }) { return "high" }
        if let op = currentOperation, !op.isEmpty, op.lowercased() != "none" { return "medium" }
        if let op = lastFailedOperation, !op.isEmpty, op.lowercased() != "none" { return "low" }
        return "none"
    }

    /// Check if crash is related to ZBD SDK based on stack trace analysis
    func isSDKRelatedCrash(_ stackTrace: String) -> Bool {
        // If an SDK operation was active at crash time, it's SDK-related
        // (matches Android behavior — stack trace patterns alone don't work for IL2CPP release builds)
        // Guard against "none" sentinel value stored when no operation is active
        if let op = currentOperation, !op.isEmpty && op.lowercased() != "none" { return true }
        if let op = lastFailedOperation, !op.isEmpty && op.lowercased() != "none" { return true }

        // Fallback: check stack trace patterns (works for debug builds).
        // Use "ZBD." (the C# namespace prefix), NOT bare "ZBD" — the app's bundle/package
        // path can appear in stacks and a bare "ZBD" would falsely match it.
        let sdkPatterns = [
            "com.zbd.",
            "ZBD.",
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
        // First try stack trace patterns (works for debug builds)
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
        } else if stackTrace.contains("ZBD.") {  // "ZBD." namespace, not bare "ZBD"
            return "ZBD_Unknown"
        }

        // Fallback: use active operation name (matches Android behavior for IL2CPP builds)
        // Guard against "none" sentinel value stored when no operation is active
        if let op = currentOperation, !op.isEmpty && op.lowercased() != "none" { return "SDK_\(op)" }
        if let op = lastFailedOperation, !op.isEmpty && op.lowercased() != "none" { return "SDK_\(op)" }

        return ""
    }
}
