import Foundation

/// Stores and retrieves SDK context from UserDefaults
/// Used to pass SDK state from C# to native crash reporter
class SDKContextStorage {
    private static let sdkContextKey = "com.zebedee.crash_reporter.sdk_context"
    private static let operationContextKey = "com.zebedee.crash_reporter.operation_context"

    /// Store SDK context JSON from C#
    static func storeSDKContext(_ contextJson: String) {
        UserDefaults.standard.set(contextJson, forKey: sdkContextKey)
        UserDefaults.standard.synchronize()
        print("✅ [SDK_CONTEXT] Stored SDK context (\(contextJson.count) bytes)")
    }

    /// Retrieve stored SDK context JSON
    static func getStoredSDKContext() -> String? {
        guard let context = UserDefaults.standard.string(forKey: sdkContextKey) else {
            print("⚠️ [SDK_CONTEXT] No stored SDK context found")
            return nil
        }
        print("✅ [SDK_CONTEXT] Retrieved stored SDK context (\(context.count) bytes)")
        return context
    }

    /// Clear stored SDK context
    static func clearSDKContext() {
        UserDefaults.standard.removeObject(forKey: sdkContextKey)
        UserDefaults.standard.synchronize()
        print("🗑️ [SDK_CONTEXT] Cleared SDK context")
    }

    // MARK: - Complete Context Bundle (NEW)

    /// Bundle ALL SDK context (SDK info, Unity info, operations, user state) and persist it
    /// This is called periodically and before crashes to ensure data survives app termination
    static func persistCompleteContext() {
        var context: [String: Any] = [:]

        // Add SDK info
        if let sdkInfo = SDKInfoManager.shared.toDict() {
            context["sdk_info"] = sdkInfo
        }

        // Add Unity info
        if let unityInfo = UnityInfoManager.shared.toDict() {
            context["unity_info"] = unityInfo
        }

        // Add SDK user state
        if let userState = SDKUserStateManager.shared.toDict() {
            context["sdk_user_state"] = userState
        }

        // Add performance metrics
        if let perfMetrics = SDKPerformanceMetricsManager.shared.toDict() {
            context["performance_metrics"] = perfMetrics
        }

        // Add operation tracker state
        context["currentOperation"] = OperationTracker.shared.getCurrentOperation() ?? "none"
        context["lastSuccessfulOperation"] = OperationTracker.shared.getLastSuccessfulOperation() ?? "none"
        context["lastFailedOperation"] = OperationTracker.shared.getLastFailedOperation() ?? "none"
        context["lastOperationError"] = OperationTracker.shared.getLastFailureReason() ?? "none"
        // getSDKVersion() returns "" (empty string) not nil, so ?? "unknown" never triggers.
        // Use explicit empty-string check instead.
        let sdkVer = OperationTracker.shared.getSDKVersion()
        context["sdkVersion"] = sdkVer.isEmpty ? "unknown" : sdkVer

        // Add metadata
        context["platform"] = "iOS"
        context["crashReporterPluginVersion"] = "1.0.0"
        context["isDebugBuild"] = isDebugBuild()
        context["environment"] = CustomDataManager.shared.getEnvironment()

        // Convert to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: context, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: operationContextKey)
                UserDefaults.standard.synchronize()
                print("✅ [CONTEXT_BUNDLE] Persisted complete SDK context (\(jsonString.count) bytes)")
            }
        } catch {
            print("❌ [CONTEXT_BUNDLE] Failed to serialize context: \(error)")
        }
    }

    /// Retrieve the complete persisted context bundle
    static func getPersistedCompleteContext() -> [String: Any]? {
        guard let jsonString = UserDefaults.standard.string(forKey: operationContextKey) else {
            print("⚠️ [CONTEXT_BUNDLE] No persisted context bundle found")
            return nil
        }

        do {
            if let jsonData = jsonString.data(using: .utf8) {
                let context = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                print("✅ [CONTEXT_BUNDLE] Retrieved persisted context bundle (\(jsonString.count) bytes)")
                return context
            }
        } catch {
            print("❌ [CONTEXT_BUNDLE] Failed to deserialize context: \(error)")
        }

        return nil
    }

    /// Detect if this is a debug build
    private static func isDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Public Bridge Functions (called from C#)

/// Called from C# via P/Invoke to store SDK context
@_cdecl("CrashReporter_SetSDKContext")
public func CrashReporter_SetSDKContext(_ contextJsonCString: UnsafePointer<CChar>) {
    let contextJson = String(cString: contextJsonCString)
    SDKContextStorage.storeSDKContext(contextJson)
}

/// Called from C# to persist complete SDK context bundle
/// This should be called periodically (e.g., every 5 seconds) to ensure data survives crashes
@_cdecl("CrashReporter_PersistCompleteContext")
public func CrashReporter_PersistCompleteContext() {
    SDKContextStorage.persistCompleteContext()
}
