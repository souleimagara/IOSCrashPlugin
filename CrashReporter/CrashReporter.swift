import Foundation
import UIKit
import CommonCrypto

public class CrashReporterCore {
    public static let shared = CrashReporterCore()

    private var isInitialized = false
    private var crashHandler: CrashHandler?
    private var crashStorage: CrashStorage?
    private var crashSender: CrashSender?
    private var deviceInfoCollector: DeviceInfoCollector?
    
    private init() {}
    
    // MARK: - Initialize
    
    public func initialize(apiEndpoint: String) {
        if isInitialized {
            print("⚠️ CrashReporter: Already initialized, skipping...")
            return
        }

        // CRITICAL FIX #1: Validate URL format
        guard !apiEndpoint.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("❌ CrashReporter: API endpoint cannot be empty")
            return
        }

        // CRITICAL FIX #2: Enforce HTTPS
        guard apiEndpoint.lowercased().hasPrefix("https://") else {
            print("❌ CrashReporter: API endpoint must use HTTPS (secure connection required)")
            return
        }

        // CRITICAL FIX #1: Validate URL is well-formed
        let testUrl = URL(string: apiEndpoint)
        guard testUrl != nil else {
            print("❌ CrashReporter: Invalid API endpoint URL format: \(apiEndpoint)")
            return
        }

        print("🚀 CrashReporter: Initializing with endpoint: \(apiEndpoint)")

        // LIMITATION FIX #1: Detect startup crashes (before this init call)
        detectStartupCrash()

        // LIMITATION FIX #2: Detect watchdog timeout from previous run
        detectWatchdogTimeout()

        // Initialize components
        let storage = CrashStorage()
        let sender = CrashSender(apiEndpoint: apiEndpoint, crashStorage: storage)
        let collector = DeviceInfoCollector()
        let handler = CrashHandler(crashStorage: storage, crashSender: sender, deviceInfoCollector: collector)

        self.crashStorage = storage
        self.crashSender = sender
        self.deviceInfoCollector = collector
        self.crashHandler = handler

        // Setup exception handler
        handler.setupExceptionHandler()

        // Setup signal handler
        handler.setupSignalHandler()

        // ARCHITECTURAL FIX: Check for crash marker from previous app run
        // This handles signal crashes that were saved as marker files
        processPreviousCrashMarker(storage: storage)

        // Note: Unity will call sendPendingCrashesNow() if sendPendingCrashesOnStart is enabled
        // So we don't automatically send here to avoid redundant calls

        isInitialized = true
        print("✅ CrashReporter: Initialized successfully!")
    }
    
    // MARK: - Process Previous Crash Marker

    private func processPreviousCrashMarker(storage: CrashStorage) {
        print("🔍 [INIT] processPreviousCrashMarker - checking for previous crash marker...")

        // Check for crash marker from previous app run (signal crash)
        guard let markerData = CrashMarkerHandler.readMarkerFile() else {
            print("❌ [INIT] No previous crash marker found")
            return
        }

        guard let collector = deviceInfoCollector else {
            print("⚠️ [INIT] Cannot process marker - device collector unavailable")
            return
        }

        print("🚨 [INIT] CRITICAL: Detected previous signal crash - \(markerData.getSignalName())")

        // Load persisted complete context bundle (SDK info, Unity info, operations, user state, etc.)
        let persistedContext = SDKContextStorage.getPersistedCompleteContext()

        // Extract and decode SDK info
        var sdkInfo: SDKInfo? = nil
        if let context = persistedContext, let sdkDict = context["sdk_info"] as? [String: Any] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: sdkDict, options: [])
                sdkInfo = try JSONDecoder().decode(SDKInfo.self, from: jsonData)
                print("✅ [INIT] Loaded SDK info from persisted context")
            } catch {
                print("⚠️ [INIT] Failed to decode SDK info: \(error)")
            }
        }

        // Extract and decode Unity info
        var unityInfo: UnityInfo? = nil
        if let context = persistedContext, let unityDict = context["unity_info"] as? [String: Any] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: unityDict, options: [])
                unityInfo = try JSONDecoder().decode(UnityInfo.self, from: jsonData)
                print("✅ [INIT] Loaded Unity info from persisted context")
            } catch {
                print("⚠️ [INIT] Failed to decode Unity info: \(error)")
            }
        }

        // Extract and decode SDK user state
        var sdkUserState: SDKUserState? = nil
        if let context = persistedContext, let userStateDict = context["sdk_user_state"] as? [String: Any] {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: userStateDict, options: [])
                sdkUserState = try JSONDecoder().decode(SDKUserState.self, from: jsonData)
                print("✅ [INIT] Loaded SDK user state from persisted context")
            } catch {
                print("⚠️ [INIT] Failed to decode SDK user state: \(error)")
            }
        }

        // Extract operation tracking data
        let currentOperation = persistedContext?["currentOperation"] as? String
        let lastSuccessfulOperation = persistedContext?["lastSuccessfulOperation"] as? String
        let lastFailedOperation = persistedContext?["lastFailedOperation"] as? String
        let lastOperationError = persistedContext?["lastOperationError"] as? String
        let sdkVersion = persistedContext?["sdkVersion"] as? String ?? "unknown"

        // Extract metadata
        let platform = persistedContext?["platform"] as? String ?? "iOS"
        let crashReporterPluginVersion = persistedContext?["crashReporterPluginVersion"] as? String ?? "1.0.0"
        let isDebugBuild = persistedContext?["isDebugBuild"] as? Bool ?? false
        let environment = persistedContext?["environment"] as? String

        // Generate crash fingerprint for deduplication (SHA256 hash of signal type)
        let crashFingerprint = generateCrashFingerprint(signalName: markerData.getSignalName())

        // Build custom data with all SDK context
        var customData = CustomDataManager.shared.getCustomData()
        customData["sdkVersion"] = sdkVersion
        customData["platform"] = platform
        customData["crashReporterPluginVersion"] = crashReporterPluginVersion
        customData["isDebugBuild"] = String(isDebugBuild)
        if let currentOp = currentOperation {
            customData["currentOperation"] = currentOp
        }
        if let lastSuccessOp = lastSuccessfulOperation {
            customData["lastSuccessfulOperation"] = lastSuccessOp
        }
        if let lastFailedOp = lastFailedOperation {
            customData["lastFailedOperation"] = lastFailedOp
        }
        if let lastError = lastOperationError {
            customData["lastOperationError"] = lastError
        }

        // Create crash report from marker with full context
        let crashData = CrashData(
            crashId: UUID().uuidString,
            timestamp: Int64(markerData.timestamp * 1000),  // Convert to milliseconds
            exceptionType: markerData.getSignalName(),
            exceptionMessage: "Signal \(markerData.signal) crash detected on previous app run",
            stackTrace: "(Stack trace unavailable - process terminated before collection)",
            threadName: "unknown",
            deviceInfo: collector.getDeviceInfo(),
            appInfo: collector.getAppInfo(),
            deviceState: collector.getDeviceState(),
            networkInfo: collector.getNetworkInfo(),
            memoryInfo: collector.getMemoryInfo(),
            cpuInfo: collector.getCpuInfo(),
            processInfo: collector.getProcessInfo(),
            allThreads: [],  // Thread info unavailable - process crashed
            breadcrumbs: BreadcrumbManager.shared.getBreadcrumbs(),
            customData: customData,
            environment: environment ?? CustomDataManager.shared.getEnvironment(),
            cpuRegisters: nil,
            memoryState: nil,
            binaryImages: [],  // Binary images unavailable
            sessionInfo: SessionInfo(sessionId: UUID().uuidString, sessionStartTime: Int64(Date().timeIntervalSince1970 * 1000), sessionDurationMs: 0, isInForeground: false, eventsBeforeCrash: 0, appWasInBackground: true),
            sessionAnalytics: nil,
            isANR: false,
            isNativeCrash: true,
            anrDurationMs: nil,
            nativeSignal: markerData.getSignalName(),
            nativeFaultAddress: nil,
            crashFingerprint: crashFingerprint,
            severity: "CRITICAL",
            issueTitle: "Native crash: \(markerData.getSignalName())",
            memoryWarnings: MemoryWarningTracker.shared.getMemoryWarnings(),
            networkChanges: NetworkReachabilityTracker.shared.getNetworkChanges(),
            isInCrashLoop: CrashLoopDetector.shared.isInCrashLoop(),
            crashLoopCount: CrashLoopDetector.shared.getCrashCount(),
            sdk_info: sdkInfo,
            sdk_user_state: sdkUserState,
            unity_info: unityInfo
        )

        print("📝 [INIT] Saving reconstructed crash from marker - ID: \(crashData.crashId), Fingerprint: \(crashFingerprint)")

        // Save the reconstructed crash
        storage.saveCrash(crashData)
        print("✅ [INIT] Previous signal crash saved - \(crashData.crashId)")

        print("🗑️ [INIT] Deleting marker file...")
        // Delete the marker file
        CrashMarkerHandler.deleteMarkerFile()
        print("✅ [INIT] Marker file deleted")
    }

    // MARK: - Generate Crash Fingerprint

    private func generateCrashFingerprint(signalName: String) -> String {
        // Generate SHA256 hash from signal name for deduplication
        // This groups crashes by signal type for easier analysis
        let input = "signal_crash_\(signalName)"
        guard let data = input.data(using: .utf8) else {
            return "unknown_fingerprint"
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Send Pending Crashes

    private func sendPendingCrashes() {
        guard let sender = crashSender else { return }
        sender.sendAllPendingCrashes()
    }
    
    public func sendPendingCrashesNow() {
        sendPendingCrashes()
    }
    
    // MARK: - Check Initialized

    public func checkIsInitialized() -> Bool {
        return isInitialized
    }

    // MARK: - Get Crash Handler (for managed exceptions)

    internal func getCrashHandler() -> CrashHandler? {
        return crashHandler
    }
    
    // MARK: - Get Pending Crash Count
    
    public func getPendingCrashCount() -> Int {
        return crashStorage?.getPendingCrashCount() ?? 0
    }
    
    // MARK: - Handle Exception (called by crash handler)

    internal func handleException(_ exception: NSException) {
        crashHandler?.handleException(exception)
    }

    // MARK: - Handle Signal (called by signal handler)

    internal func handleSignal(_ signal: Int32) {
        crashHandler?.handleSignal(signal)
    }
    
    // MARK: - Public API for Custom Data
    
    public func setUserContext(userId: String?, email: String? = nil, username: String? = nil) {
        CustomDataManager.shared.setUserContext(userId: userId, email: email, username: username)
    }
    
    public func setTag(key: String, value: String) {
        CustomDataManager.shared.setTag(key: key, value: value)
    }
    
    public func removeTag(key: String) {
        CustomDataManager.shared.removeTag(key: key)
    }
    
    public func setEnvironment(env: String) {
        CustomDataManager.shared.setEnvironment(env: env)
    }
    
    // MARK: - Public API for Breadcrumbs

    public func addBreadcrumb(category: String, message: String, level: String = "info", data: [String: String] = [:]) {
        BreadcrumbManager.shared.addBreadcrumb(category: category, message: message, level: level, data: data)
    }

    // MARK: - Public API for Testing/Debugging

    public func clearAllCrashes() {
        crashStorage?.deleteAllCrashes()
        print("🗑️ CrashReporter: All crashes cleared")
    }

    // MARK: - Startup Crash Detection (LIMITATION FIX #1)

    private func detectStartupCrash() {
        // Check if app crashed during startup in previous run
        guard let startupCrash = StartupCrashDetector.detectStartupCrash() else {
            return
        }

        print("🚨 CrashReporter: Detected startup crash from previous run")

        guard let collector = deviceInfoCollector else {
            print("⚠️ CrashReporter: Cannot process startup crash - device collector unavailable")
            return
        }

        guard let storage = crashStorage else {
            print("⚠️ CrashReporter: Cannot process startup crash - storage unavailable")
            return
        }

        // Reconstruct crash report from startup crash data
        let crashData = CrashData(
            crashId: UUID().uuidString,
            timestamp: startupCrash.crashTimestamp,
            exceptionType: "STARTUP_CRASH",
            exceptionMessage: "App crashed during startup initialization",
            stackTrace: "(Stack trace unavailable - crash occurred before full initialization)",
            threadName: "main",
            deviceInfo: collector.getDeviceInfo(),
            appInfo: collector.getAppInfo(),
            deviceState: collector.getDeviceState(),
            networkInfo: collector.getNetworkInfo(),
            memoryInfo: collector.getMemoryInfo(),
            cpuInfo: collector.getCpuInfo(),
            processInfo: collector.getProcessInfo(),
            allThreads: [],
            breadcrumbs: BreadcrumbManager.shared.getBreadcrumbs(),
            customData: CustomDataManager.shared.getCustomData(),
            environment: CustomDataManager.shared.getEnvironment(),
            cpuRegisters: nil,
            memoryState: nil,
            binaryImages: [],
            sessionInfo: SessionInfo(sessionId: UUID().uuidString, sessionStartTime: Int64(Date().timeIntervalSince1970 * 1000), sessionDurationMs: 0, isInForeground: false, eventsBeforeCrash: 0, appWasInBackground: true),
            sessionAnalytics: nil,
            isANR: false,
            isNativeCrash: false,
            anrDurationMs: nil,
            nativeSignal: nil,
            nativeFaultAddress: nil,
            crashFingerprint: nil,
            severity: "CRITICAL",
            issueTitle: "Startup crash during initialization",
            memoryWarnings: MemoryWarningTracker.shared.getMemoryWarnings(),
            networkChanges: NetworkReachabilityTracker.shared.getNetworkChanges(),
            isInCrashLoop: CrashLoopDetector.shared.isInCrashLoop(),
            crashLoopCount: CrashLoopDetector.shared.getCrashCount(),
            sdk_info: nil,
            sdk_user_state: nil,
            unity_info: nil
        )

        storage.saveCrash(crashData)
        print("✅ CrashReporter: Startup crash saved - \(crashData.crashId)")

        // Clean up the startup flag
        StartupCrashDetector.deleteInitFlag()
    }

    // MARK: - Watchdog Timeout Detection (LIMITATION FIX #2)

    private func detectWatchdogTimeout() {
        // Check if app was killed by watchdog in previous run
        guard let watchdogCrash = WatchdogDetector.detectWatchdogTimeout() else {
            return
        }

        print("🚨 CrashReporter: Detected watchdog timeout from previous run (heartbeat age: \(watchdogCrash.timeSinceLastHeartbeat)ms)")

        guard let collector = deviceInfoCollector else {
            print("⚠️ CrashReporter: Cannot process watchdog crash - device collector unavailable")
            return
        }

        guard let storage = crashStorage else {
            print("⚠️ CrashReporter: Cannot process watchdog crash - storage unavailable")
            return
        }

        // Reconstruct crash report from watchdog timeout
        let crashData = CrashData(
            crashId: UUID().uuidString,
            timestamp: watchdogCrash.heartbeatTimestamp,
            exceptionType: "WATCHDOG_TIMEOUT",
            exceptionMessage: "App killed by watchdog (main thread blocked for too long)",
            stackTrace: "(Stack trace unavailable - process killed by OS)",
            threadName: "main",
            deviceInfo: collector.getDeviceInfo(),
            appInfo: collector.getAppInfo(),
            deviceState: collector.getDeviceState(),
            networkInfo: collector.getNetworkInfo(),
            memoryInfo: collector.getMemoryInfo(),
            cpuInfo: collector.getCpuInfo(),
            processInfo: collector.getProcessInfo(),
            allThreads: [],
            breadcrumbs: BreadcrumbManager.shared.getBreadcrumbs(),
            customData: CustomDataManager.shared.getCustomData(),
            environment: CustomDataManager.shared.getEnvironment(),
            cpuRegisters: nil,
            memoryState: nil,
            binaryImages: [],
            sessionInfo: SessionInfo(sessionId: UUID().uuidString, sessionStartTime: Int64(Date().timeIntervalSince1970 * 1000), sessionDurationMs: 0, isInForeground: false, eventsBeforeCrash: 0, appWasInBackground: true),
            sessionAnalytics: nil,
            isANR: true,
            isNativeCrash: false,
            anrDurationMs: Int(watchdogCrash.timeSinceLastHeartbeat),
            nativeSignal: nil,
            nativeFaultAddress: nil,
            crashFingerprint: nil,
            severity: "HIGH",
            issueTitle: "Watchdog timeout (main thread blocked)",
            memoryWarnings: MemoryWarningTracker.shared.getMemoryWarnings(),
            networkChanges: NetworkReachabilityTracker.shared.getNetworkChanges(),
            isInCrashLoop: CrashLoopDetector.shared.isInCrashLoop(),
            crashLoopCount: CrashLoopDetector.shared.getCrashCount(),
            sdk_info: nil,
            sdk_user_state: nil,
            unity_info: nil
        )

        storage.saveCrash(crashData)
        print("✅ CrashReporter: Watchdog timeout crash saved - \(crashData.crashId)")

        // Clean up heartbeat
        WatchdogDetector.deleteHeartbeat()
    }

    // MARK: - Startup Flag Management (User should call before initialize)

    /// Call this as early as possible in app lifecycle (e.g., UIApplicationDelegate.didFinishLaunchingWithOptions)
    public static func markAppStartup() {
        StartupCrashDetector.markStartup()
    }

    /// Call this after initialize() completes successfully
    public static func markInitializationComplete() {
        StartupCrashDetector.markInitComplete()
        // Start watchdog heartbeat after initialization
        WatchdogDetector.startHeartbeat()
    }

    /// Call this when app is about to terminate
    public static func markAppTerminating() {
        WatchdogDetector.stopHeartbeat()
    }
}
