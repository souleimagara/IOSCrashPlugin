import Foundation

/// Classifies crashes by severity and generates human-readable issue titles
///
/// Severity levels:
/// - CRITICAL: Main thread, native, ANR, startup, OutOfMemory
/// - HIGH: NullReferenceException, IllegalStateException
/// - MEDIUM: Everything else
class CrashGrouping {

    enum Severity: String, Codable {
        case critical = "CRITICAL"
        case high = "HIGH"
        case medium = "MEDIUM"
        case low = "LOW"
    }

    // MARK: - Classify Severity

    /// Classify crash severity
    /// - Parameters:
    ///   - exceptionType: Type of exception/crash
    ///   - isANR: Whether this is ANR crash
    ///   - isNativeCrash: Whether this is native signal crash
    ///   - isStartupCrash: Whether app crashed during startup
    ///   - threadName: Name of thread that crashed
    /// - Returns: Severity level
    static func classifySeverity(
        exceptionType: String,
        isANR: Bool,
        isNativeCrash: Bool,
        isStartupCrash: Bool,
        threadName: String
    ) -> Severity {
        // CRITICAL: ANR, startup crashes, native signals
        if isANR {
            return .critical
        }

        if isStartupCrash {
            return .critical
        }

        if isNativeCrash {
            return .critical
        }

        // CRITICAL: Main thread exceptions
        if threadName.lowercased() == "main" || threadName.lowercased().contains("main") {
            return .critical
        }

        // CRITICAL: Memory-related crashes
        let lowercaseType = exceptionType.lowercased()
        if lowercaseType.contains("outofmemory") || lowercaseType.contains("memory") {
            return .critical
        }

        // HIGH: Null reference and state exceptions
        if lowercaseType.contains("nullreference") || lowercaseType.contains("nullpointer") {
            return .high
        }

        if lowercaseType.contains("illegalstate") {
            return .high
        }

        if lowercaseType.contains("stackoverflow") {
            return .high
        }

        // MEDIUM: Default for most exceptions
        return .medium
    }

    // MARK: - Generate Issue Title

    /// Generate human-readable crash title for grouping
    /// - Parameters:
    ///   - exceptionType: Type of exception/crash
    ///   - topFrameFunction: Top function in stack trace
    ///   - threadName: Name of thread that crashed
    /// - Returns: Human-readable title (e.g., "SIGSEGV at libunity.so")
    static func generateIssueTitle(
        exceptionType: String,
        topFrameFunction: String = "",
        threadName: String = ""
    ) -> String {
        // Special cases first
        if exceptionType == "ANR" {
            return "ANR - Application Not Responding"
        }

        // Extract top function if provided
        let function = extractTopFunction(topFrameFunction)
        let functionPart = !function.isEmpty ? " at \(function)" : ""

        // Format: "SIGSEGV at libunity.so"
        return exceptionType + functionPart
    }

    // MARK: - Sampling (Non-Fatal Crashes)

    /// Determine if non-fatal crash should be sent (sampling)
    /// - Parameters:
    ///   - isNativeCrash: Whether this is native crash
    ///   - isANR: Whether this is ANR
    ///   - isStartupCrash: Whether this is startup crash
    /// - Returns: true if should send (sample), false if should skip
    static func shouldSampleCrash(
        isNativeCrash: Bool,
        isANR: Bool,
        isStartupCrash: Bool
    ) -> Bool {
        // Always send fatal crashes
        if isNativeCrash || isANR || isStartupCrash {
            return true
        }

        // For non-fatal crashes: send 15% (1 in 7)
        let randomValue = Int.random(in: 0..<100)
        return randomValue < 15
    }

    // MARK: - Helper Methods

    /// Extract function name from stack frame
    /// - Parameter stackFrame: Full stack frame string
    /// - Returns: Extracted function name or file name
    private static func extractTopFunction(_ stackFrame: String) -> String {
        if stackFrame.isEmpty {
            return ""
        }

        // Try to extract function/class name
        // Format variations:
        // "0 MyApp 0x0000000100001234 _Z3fooRN3MyC7MyClassE + 1234"
        // "libunity.so!MyClass.MyFunction()"
        // "com.example.app.MyClass.myMethod(MyClass.java:123)"

        let components = stackFrame.split(separator: " ")

        // For "at Class.method(file:line)" format
        if stackFrame.contains("at ") {
            if let atIndex = stackFrame.range(of: "at ") {
                let afterAt = String(stackFrame[atIndex.upperBound...])
                let methodPart = afterAt.split(separator: "(").first ?? ""
                return String(methodPart).trimmingCharacters(in: .whitespaces)
            }
        }

        // For "libname!function" format
        if stackFrame.contains("!") {
            let parts = stackFrame.split(separator: "!", maxSplits: 1)
            if parts.count > 1 {
                let functionName = String(parts[1]).split(separator: " ").first ?? ""
                return String(functionName)
            }
        }

        // For "0x address symbol +offset" format
        // Return the symbol (usually the library or function name)
        let lastComponent = components.last ?? ""
        if !lastComponent.hasPrefix("0x") {
            return String(lastComponent)
        }

        // Fallback: try to find library name
        if stackFrame.contains("libunity") {
            return "libunity.so"
        }

        if stackFrame.contains(".so") {
            if let soRange = stackFrame.range(of: ".so") {
                let beforeSo = stackFrame[..<soRange.lowerBound]
                if let lastSlash = beforeSo.lastIndex(of: "/") {
                    return String(beforeSo[beforeSo.index(after: lastSlash)...]) + ".so"
                }
            }
        }

        return ""
    }

    // MARK: - Get Crash Category

    /// Get human-readable crash category
    /// - Parameter exceptionType: Type of exception
    /// - Returns: Category string (e.g., "Native Crash", "Exception", "ANR")
    static func getCrashCategory(_ exceptionType: String) -> String {
        let lower = exceptionType.lowercased()

        if exceptionType == "ANR" {
            return "ANR"
        }

        if lower.hasPrefix("sig") {
            return "Native Crash"
        }

        if lower.contains("exception") {
            return "Exception"
        }

        if lower.contains("error") {
            return "Error"
        }

        return "Unknown"
    }
}
