import Foundation

/// Stores and retrieves SDK context from UserDefaults
/// Used to pass SDK state from C# to native crash reporter
class SDKContextStorage {
    private static let sdkContextKey = "com.zebedee.crash_reporter.sdk_context"
    
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
}

// MARK: - Public Bridge Functions (called from C#)

/// Called from C# via P/Invoke to store SDK context
@_cdecl("CrashReporter_SetSDKContext")
public func CrashReporter_SetSDKContext(_ contextJsonCString: UnsafePointer<CChar>) {
    let contextJson = String(cString: contextJsonCString)
    SDKContextStorage.storeSDKContext(contextJson)
}
