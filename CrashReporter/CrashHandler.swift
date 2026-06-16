import Foundation
import UIKit
import MachO

// Signal handler implemented directly in Swift using @_cdecl so it has a C-compatible symbol.
// Only async-signal-safe operations (CrashMarkerHandler uses raw syscalls only).
@_cdecl("CrashReporter_SignalHandler")
func CrashReporter_SignalHandler(_ signal: Int32) {
    CrashMarkerHandler.writeMarkerFile(signalNumber: signal)
    Darwin.signal(signal, SIG_DFL)
    Darwin.raise(signal)
}

class CrashHandler {
    private let crashStorage: CrashStorage
    private let crashSender: CrashSender
    private let deviceInfoCollector: DeviceInfoCollector
    private var previousExceptionHandler: NSUncaughtExceptionHandler?

    // Re-entrancy guard to prevent duplicate crash handling (thread-safe)
    private static var isHandlingCrash = false
    private static let crashHandlingLock = NSLock()

    // Signal handler flags (volatile for signal-safe access)
    private static var signalCrashOccurred = false
    private static var lastSignalNumber: Int32 = 0

    init(crashStorage: CrashStorage, crashSender: CrashSender, deviceInfoCollector: DeviceInfoCollector) {
        self.crashStorage = crashStorage
        self.crashSender = crashSender
        self.deviceInfoCollector = deviceInfoCollector
    }
    
    // MARK: - Setup Exception Handler

    func setupExceptionHandler() {
        // Save previous handler
        previousExceptionHandler = NSGetUncaughtExceptionHandler()

        // Set our custom handler
        NSSetUncaughtExceptionHandler { exception in
            CrashReporterCore.shared.handleException(exception)
        }

        CrashReporterLogger.info("Exception handler installed", log: CrashReporterLogger.crashHandler)
    }

    // MARK: - Setup Signal Handler

    func setupSignalHandler() {
        // Signals to catch
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE]

        // CRITICAL FIX: Use C function pointer, not Swift closure
        // Signal handlers MUST be C functions to work correctly
        for sig in signals {
            signal(sig, CrashReporter_SignalHandler)
        }

        CrashReporterLogger.info("Signal handler installed for SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE", log: CrashReporterLogger.crashHandler)
    }

    // MARK: - Handle Signal (MUST BE ASYNC-SAFE)

    func handleSignal(_ signalNumber: Int32) {
        // ⚠️ CRITICAL: Signal handlers must only call async-safe functions!
        // ARCHITECTURAL FIX: Write marker file instead of relying on exception handler
        // NSSetUncaughtExceptionHandler only handles Objective-C exceptions, NOT signals
        // So we write a marker that will be detected on app restart

        // Log to stderr immediately (async-safe)
        let enterMsg = "🚨 [SIGNAL_HANDLER] ENTERED - Signal \(signalNumber)\n"
        _ = write(STDERR_FILENO, enterMsg, enterMsg.count)

        // Write crash marker file (async-safe open/write/close)
        CrashMarkerHandler.writeMarkerFile(signalNumber: signalNumber)

        let writeCompleteMsg = "✅ [SIGNAL_HANDLER] Marker write completed\n"
        _ = write(STDERR_FILENO, writeCompleteMsg, writeCompleteMsg.count)

        // Reset to default handler and re-raise signal to crash the process
        // This is async-safe and lets the OS handle the crash
        let resetMsg = "🔄 [SIGNAL_HANDLER] Resetting signal handler to SIG_DFL\n"
        _ = write(STDERR_FILENO, resetMsg, resetMsg.count)

        signal(signalNumber, SIG_DFL)

        let raiseMsg = "💥 [SIGNAL_HANDLER] Raising signal \(signalNumber) to crash process\n"
        _ = write(STDERR_FILENO, raiseMsg, raiseMsg.count)

        raise(signalNumber)

        // If raise() didn't crash (shouldn't happen), force exit immediately
        let exitMsg = "⚠️ [SIGNAL_HANDLER] raise() failed, forcing exit(1)\n"
        _ = write(STDERR_FILENO, exitMsg, exitMsg.count)

        exit(1)
    }

    // MARK: - Collect Signal Crash Data

    private func collectSignalCrashData(signal: Int32) -> CrashData {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let crashId = UUID().uuidString
        let signalName = getSignalName(signal)
        let signalNameFormatted = getFormattedSignalName(signal)  // Format: "SIGABRT (6)"
        let stackTrace = getSignalStackTrace()

        // Collect Tier 2 data
        let performanceMetrics = PerformanceMetricsCollector.shared.getCurrentMetrics()
        let recentEvents = AnalyticsEventManager.shared.getRecentEvents(count: 20)
        let sessionAnalytics = SessionAnalytics(
            performanceMetrics: performanceMetrics,
            recentEvents: recentEvents
        )

        // Extract fault address from CPU registers if available
        let faultAddress = extractFaultAddress(from: getCPURegisters())

        // Generate fingerprint for deduplication
        let fingerprint = CrashFingerprinting.generateFingerprint(from: stackTrace)

        // Classify severity
        let severity = CrashGrouping.classifySeverity(
            exceptionType: signalNameFormatted,
            isANR: false,
            isNativeCrash: true,
            isStartupCrash: false,
            threadName: Thread.current.name ?? "main"
        )

        // Generate issue title
        let issueTitle = CrashGrouping.generateIssueTitle(
            exceptionType: signalNameFormatted,
            topFrameFunction: extractTopFunction(from: stackTrace),
            threadName: Thread.current.name ?? "main"
        )

        // Check crash loop status
        let isInLoop = CrashLoopDetector.shared.isInCrashLoop()
        let crashLoopCount = CrashLoopDetector.shared.getCrashCount()

        // Collect tracking data
        let memoryWarnings = MemoryWarningTracker.shared.getMemoryWarnings()
        let networkChanges = NetworkReachabilityTracker.shared.getNetworkChanges()

        var customData = CustomDataManager.shared.getCustomData()
        customData = SensitiveDataScrubber.scrubDictionary(customData)

        return CrashData(
            crashId: crashId,
            timestamp: timestamp,
            exceptionType: signalNameFormatted,  // Now formatted as "SIGABRT (6)"
            exceptionMessage: "Signal \(signal) - \(getSignalDescription(signal))",
            stackTrace: SensitiveDataScrubber.scrubStackTrace(stackTrace),
            threadName: Thread.current.name ?? "main",
            deviceInfo: deviceInfoCollector.getDeviceInfo(),
            appInfo: deviceInfoCollector.getAppInfo(),
            deviceState: deviceInfoCollector.getDeviceState(),
            networkInfo: deviceInfoCollector.getNetworkInfo(),
            memoryInfo: deviceInfoCollector.getMemoryInfo(),
            cpuInfo: deviceInfoCollector.getCpuInfo(),
            processInfo: deviceInfoCollector.getProcessInfo(),
            allThreads: limitThreadStackFrames(getAllThreadInfo()),
            breadcrumbs: BreadcrumbManager.shared.getBreadcrumbs(),
            customData: customData,
            environment: CustomDataManager.shared.getEnvironment(),
            cpuRegisters: getCPURegisters(),
            memoryState: getMemoryState(),
            binaryImages: [],  // Not sent to reduce payload size (Android doesn't send this)
            sessionInfo: SessionManager.shared.getSessionInfo(),
            sessionAnalytics: sessionAnalytics,
            isANR: false,  // Signal crash is not ANR
            isNativeCrash: true,  // This is a native signal crash
            anrDurationMs: nil,
            nativeSignal: signalNameFormatted,  // Store formatted signal name
            nativeFaultAddress: faultAddress,
            crashFingerprint: fingerprint,
            severity: severity.rawValue,
            issueTitle: issueTitle,
            memoryWarnings: memoryWarnings,
            networkChanges: networkChanges,
            isInCrashLoop: isInLoop,
            crashLoopCount: crashLoopCount,
            sdk_info: SDKInfoManager.shared.getSDKInfo() ?? SDKInfoManager.shared.createDefaultSDKInfo(),
            sdk_user_state: SDKUserStateManager.shared.getUserState() ?? SDKUserStateManager.shared.createDefaultUserState(),
            unity_info: UnityInfoManager.shared.getUnityInfo() ?? UnityInfoManager.shared.createDefaultUnityInfo(),
            isSDKRelated: OperationTracker.shared.isSDKRelatedCrash(stackTrace),
            sdkConfidence: OperationTracker.shared.getSDKConfidence(stackTrace, OperationTracker.shared.extractFaultingLibrary(stackTrace)),
            faultingLibrary: OperationTracker.shared.extractFaultingLibrary(stackTrace),
            responsibleSDKComponent: OperationTracker.shared.determineResponsibleComponent(stackTrace),
            sdkVersion: OperationTracker.shared.sdkVersion,
            crashReporterPluginVersion: OperationTracker.shared.crashReporterPluginVersion,
            platform: OperationTracker.shared.platform,
            initFailurePoint: OperationTracker.shared.initFailurePoint,
            currentOperation: OperationTracker.shared.currentOperation ?? "",
            operationContext: OperationTracker.shared.operationContext,
            powerSaveMode: deviceInfoCollector.isPowerSaveMode(),
            isDebugBuild: deviceInfoCollector.isDebugBuild(),
            bootTime: deviceInfoCollector.getBootTime(),
            deviceUptime: deviceInfoCollector.getDeviceUptime(),
            timezone: deviceInfoCollector.getTimezone(),
            isVPNActive: deviceInfoCollector.isVPNActive(),
            isProxyActive: deviceInfoCollector.isProxyActive(),
            memoryPressure: deviceInfoCollector.getMemoryPressure(),
            wasNetworkRecentlyLost: NetworkReachabilityTracker.shared.wasNetworkRecentlyLost(),
            isStartupCrash: false
        )
    }

    // MARK: - Signal Helpers

    private func getSignalName(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT: return "SIGABRT"
        case SIGILL: return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE: return "SIGFPE"
        case SIGBUS: return "SIGBUS"
        case SIGPIPE: return "SIGPIPE"
        default: return "SIG\(signal)"
        }
    }

    /// Format signal as "SIGABRT (6)" - includes signal number for Android parity
    private func getFormattedSignalName(_ signal: Int32) -> String {
        let name = getSignalName(signal)
        return "\(name) (\(signal))"
    }

    private func getSignalDescription(_ signal: Int32) -> String {
        switch signal {
        case SIGABRT: return "Abort signal (abnormal termination)"
        case SIGILL: return "Illegal instruction"
        case SIGSEGV: return "Segmentation fault (invalid memory access)"
        case SIGFPE: return "Floating-point exception"
        case SIGBUS: return "Bus error (invalid memory alignment)"
        case SIGPIPE: return "Broken pipe"
        default: return "Unknown signal"
        }
    }

    /// Extract fault address from CPU registers (typically in PC or X30 register)
    private func extractFaultAddress(from registers: CPURegisters?) -> String? {
        guard let registers = registers else { return nil }

        // Try to get fault address from program counter (PC) or other registers
        if let pc = registers.pc, pc > 0 {
            return String(format: "0x%llx", pc)
        }

        // Fallback to link register if available
        if let lr = registers.lr, lr > 0 {
            return String(format: "0x%llx", lr)
        }

        return nil
    }

    /// Extract top function name from stack trace
    private func extractTopFunction(from stackTrace: String) -> String {
        let lines = stackTrace.split(separator: "\n")

        // Find first frame line (skip header lines)
        for line in lines {
            let lineStr = String(line)
            if lineStr.starts(with: "0") || lineStr.starts(with: "1") {
                // Try to extract function name
                let components = lineStr.split(separator: " ")
                for component in components {
                    let comp = String(component)
                    if !comp.hasPrefix("0x") && !comp.isEmpty {
                        return comp
                    }
                }
            }
        }

        return ""
    }

    private func getSignalStackTrace() -> String {
        var stackTrace = "Signal Stack Trace:\n"
        let symbols = Thread.callStackSymbols
        for (index, symbol) in symbols.enumerated() {
            stackTrace += "\(index): \(symbol)\n"
        }
        return stackTrace
    }
    
    // MARK: - Handle Exception

    func handleException(_ exception: NSException) {
        // Re-entrancy guard: prevent duplicate crash handling (thread-safe)
        CrashHandler.crashHandlingLock.lock()
        defer { CrashHandler.crashHandlingLock.unlock() }

        if CrashHandler.isHandlingCrash {
            CrashReporterLogger.warning("Already handling a crash, ignoring duplicate", log: CrashReporterLogger.crashHandler)
            return
        }

        CrashHandler.isHandlingCrash = true
        CrashReporterLogger.critical("Uncaught exception detected - \(exception.name)", log: CrashReporterLogger.crashHandler)

        // Check if a signal crash occurred (set by async-safe signal handler)
        if CrashHandler.signalCrashOccurred {
            CrashReporterLogger.critical("Processing deferred signal crash - \(getSignalName(CrashHandler.lastSignalNumber))", log: CrashReporterLogger.crashHandler)
            let crashData = collectSignalCrashData(signal: CrashHandler.lastSignalNumber)
            crashStorage.saveCrash(crashData, isSignalCrash: true)
            CrashReporterLogger.info("Signal crash saved - \(crashData.crashId)", log: CrashReporterLogger.crashStorage)
            CrashHandler.signalCrashOccurred = false
        } else {
            // Regular exception crash
            let crashData = collectCrashData(exception: exception)
            crashStorage.saveCrash(crashData)
            CrashReporterLogger.info("Exception crash saved - \(crashData.crashId)", log: CrashReporterLogger.crashStorage)
        }

        // Note: Crash will be sent by sendAllPendingCrashes() on app restart
        // Don't send immediately - just save to queue

        // Call previous handler if available to support handler chaining with other crash reporters
        if let previousHandler = previousExceptionHandler {
            previousHandler(exception)
        }
    }

    // MARK: - Handle Managed Exception (C# Exceptions)

    func handleManagedException(exceptionType: String, exceptionMessage: String, stackTrace: String, isFatal: Bool) {
        print("🔴 [MANAGED_EXCEPTION] Processing C# exception: \(exceptionType)")

        // Collect crash data for managed exception
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let crashId = UUID().uuidString
        let deviceState = deviceInfoCollector.getDeviceState()
        let processInfo = deviceInfoCollector.getProcessInfo()

        // Generate fingerprint for deduplication
        let fingerprint = CrashFingerprinting.generateFingerprint(from: stackTrace)

        // Classify severity based on whether it's fatal
        let severity = isFatal ? "CRITICAL" : "HIGH"

        // Generate issue title
        let issueTitle = "C# Exception: \(exceptionType)"

        // Get custom data (with all SDK context)
        var customData = CustomDataManager.shared.getCustomData()
        customData["isManagedException"] = "true"
        customData["isFatal"] = String(isFatal)
        customData = SensitiveDataScrubber.scrubDictionary(customData)

        // Check crash loop status
        let isInLoop = CrashLoopDetector.shared.isInCrashLoop()
        let crashLoopCount = CrashLoopDetector.shared.getCrashCount()

        // Get SDK info, Unity info, user state
        let sdkInfo = SDKInfoManager.shared.getSDKInfo()
        let unityInfo = UnityInfoManager.shared.getUnityInfo()
        let sdkUserState = SDKUserStateManager.shared.getUserState()

        let crashData = CrashData(
            crashId: crashId,
            timestamp: timestamp,
            exceptionType: exceptionType,
            exceptionMessage: exceptionMessage,
            stackTrace: stackTrace,
            threadName: Thread.current.name ?? "main",
            deviceInfo: deviceInfoCollector.getDeviceInfo(),
            appInfo: deviceInfoCollector.getAppInfo(),
            deviceState: deviceState,
            networkInfo: deviceInfoCollector.getNetworkInfo(),
            memoryInfo: deviceInfoCollector.getMemoryInfo(),
            cpuInfo: deviceInfoCollector.getCpuInfo(),
            processInfo: processInfo,
            allThreads: limitThreadStackFrames(getAllThreadInfo()),
            breadcrumbs: BreadcrumbManager.shared.getBreadcrumbs(),
            customData: customData,
            environment: CustomDataManager.shared.getEnvironment(),
            cpuRegisters: nil,
            memoryState: nil,
            binaryImages: [],  // Not sent to reduce payload size (Android doesn't send this)
            sessionInfo: SessionInfo(
                sessionId: UUID().uuidString,
                sessionStartTime: timestamp,
                sessionDurationMs: 0,
                isInForeground: UIApplication.shared.applicationState == .active,
                eventsBeforeCrash: 0,
                appWasInBackground: UIApplication.shared.applicationState != .active
            ),
            sessionAnalytics: nil,
            isANR: false,
            isNativeCrash: false,
            anrDurationMs: nil,
            nativeSignal: nil,
            nativeFaultAddress: nil,
            crashFingerprint: fingerprint,
            severity: severity,
            issueTitle: issueTitle,
            memoryWarnings: MemoryWarningTracker.shared.getMemoryWarnings(),
            networkChanges: NetworkReachabilityTracker.shared.getNetworkChanges(),
            isInCrashLoop: isInLoop,
            crashLoopCount: crashLoopCount,
            sdk_info: sdkInfo,
            sdk_user_state: sdkUserState,
            unity_info: unityInfo,
            isSDKRelated: OperationTracker.shared.isSDKRelatedCrash(stackTrace),
            sdkConfidence: OperationTracker.shared.getSDKConfidence(stackTrace, OperationTracker.shared.extractFaultingLibrary(stackTrace)),
            faultingLibrary: OperationTracker.shared.extractFaultingLibrary(stackTrace),
            responsibleSDKComponent: OperationTracker.shared.determineResponsibleComponent(stackTrace),
            sdkVersion: OperationTracker.shared.sdkVersion,
            crashReporterPluginVersion: OperationTracker.shared.crashReporterPluginVersion,
            platform: OperationTracker.shared.platform,
            initFailurePoint: OperationTracker.shared.initFailurePoint,
            currentOperation: OperationTracker.shared.currentOperation ?? "",
            operationContext: OperationTracker.shared.operationContext,
            powerSaveMode: deviceInfoCollector.isPowerSaveMode(),
            isDebugBuild: deviceInfoCollector.isDebugBuild(),
            bootTime: deviceInfoCollector.getBootTime(),
            deviceUptime: deviceInfoCollector.getDeviceUptime(),
            timezone: deviceInfoCollector.getTimezone(),
            isVPNActive: deviceInfoCollector.isVPNActive(),
            isProxyActive: deviceInfoCollector.isProxyActive(),
            memoryPressure: deviceInfoCollector.getMemoryPressure(),
            wasNetworkRecentlyLost: NetworkReachabilityTracker.shared.wasNetworkRecentlyLost(),
            isStartupCrash: false
        )

        // Save crash
        crashStorage.saveCrash(crashData)
        print("✅ [MANAGED_EXCEPTION] C# exception saved - \(crashData.crashId)")

        // Send immediately (like Android)
        crashSender.sendAllPendingCrashes()
        print("📤 [MANAGED_EXCEPTION] Sent crash report to webhook")
    }

    // MARK: - Collect Crash Data

    private func collectCrashData(exception: NSException) -> CrashData {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let crashId = UUID().uuidString
        let deviceState = deviceInfoCollector.getDeviceState()
        let processInfo = deviceInfoCollector.getProcessInfo()
        let stackTrace = getStackTrace(exception: exception)

        // Check if this is an ANR crash (watchdog timeout detected)
        let watchdogData = WatchdogDetector.detectWatchdogTimeout()
        let isANR = watchdogData != nil
        let anrDurationMs = isANR ? watchdogData?.timeSinceLastHeartbeat : nil

        // Collect Tier 2 data
        let performanceMetrics = PerformanceMetricsCollector.shared.getCurrentMetrics()
        let recentEvents = AnalyticsEventManager.shared.getRecentEvents(count: 20)
        let sessionAnalytics = SessionAnalytics(
            performanceMetrics: performanceMetrics,
            recentEvents: recentEvents
        )

        // Classify exception type
        let exceptionType = classifyExceptionType(isANR: isANR)
        let exceptionMessage = isANR ? "Application Not Responding" : (exception.reason ?? "No message")

        // Generate fingerprint for deduplication
        let fingerprint = CrashFingerprinting.generateFingerprint(from: stackTrace)

        // Classify severity
        let severity = CrashGrouping.classifySeverity(
            exceptionType: exceptionType,
            isANR: isANR,
            isNativeCrash: false,
            isStartupCrash: false,
            threadName: Thread.current.name ?? "main"
        )

        // Generate issue title
        let issueTitle = CrashGrouping.generateIssueTitle(
            exceptionType: exceptionType,
            topFrameFunction: extractTopFunction(from: stackTrace),
            threadName: Thread.current.name ?? "main"
        )

        // Validate ANR if detected
        var customData = CustomDataManager.shared.getCustomData()
        if isANR {
            let validation = ANRValidator.validateANR(
                watchdogDurationMs: anrDurationMs ?? 0,
                deviceState: deviceState,
                processInfo: processInfo
            )
            customData = ANRValidator.enrichCustomDataWithValidation(customData, validation: validation)
        }

        // Scrub sensitive data
        customData = SensitiveDataScrubber.scrubDictionary(customData)

        // Check crash loop status
        let isInLoop = CrashLoopDetector.shared.isInCrashLoop()
        let crashLoopCount = CrashLoopDetector.shared.getCrashCount()

        // Collect tracking data
        let memoryWarnings = MemoryWarningTracker.shared.getMemoryWarnings()
        let networkChanges = NetworkReachabilityTracker.shared.getNetworkChanges()

        return CrashData(
            crashId: crashId,
            timestamp: timestamp,
            exceptionType: exceptionType,
            exceptionMessage: SensitiveDataScrubber.scrubExceptionMessage(exceptionMessage),
            stackTrace: SensitiveDataScrubber.scrubStackTrace(stackTrace),
            threadName: Thread.current.name ?? "main",
            deviceInfo: deviceInfoCollector.getDeviceInfo(),
            appInfo: deviceInfoCollector.getAppInfo(),
            deviceState: deviceState,
            networkInfo: deviceInfoCollector.getNetworkInfo(),
            memoryInfo: deviceInfoCollector.getMemoryInfo(),
            cpuInfo: deviceInfoCollector.getCpuInfo(),
            processInfo: processInfo,
            allThreads: limitThreadStackFrames(getAllThreadInfo()),
            breadcrumbs: BreadcrumbManager.shared.getBreadcrumbs(),
            customData: customData,
            environment: CustomDataManager.shared.getEnvironment(),
            cpuRegisters: getCPURegisters(),
            memoryState: getMemoryState(),
            binaryImages: [],  // Not sent to reduce payload size (Android doesn't send this)
            sessionInfo: SessionManager.shared.getSessionInfo(),
            sessionAnalytics: sessionAnalytics,
            isANR: isANR,
            isNativeCrash: false,  // Exceptions are not native crashes
            anrDurationMs: anrDurationMs != nil ? Int(anrDurationMs!) : nil,
            nativeSignal: nil,
            nativeFaultAddress: nil,
            crashFingerprint: fingerprint,
            severity: severity.rawValue,
            issueTitle: issueTitle,
            memoryWarnings: memoryWarnings,
            networkChanges: networkChanges,
            isInCrashLoop: isInLoop,
            crashLoopCount: crashLoopCount,
            sdk_info: SDKInfoManager.shared.getSDKInfo() ?? SDKInfoManager.shared.createDefaultSDKInfo(),
            sdk_user_state: SDKUserStateManager.shared.getUserState() ?? SDKUserStateManager.shared.createDefaultUserState(),
            unity_info: UnityInfoManager.shared.getUnityInfo() ?? UnityInfoManager.shared.createDefaultUnityInfo(),
            isSDKRelated: OperationTracker.shared.isSDKRelatedCrash(stackTrace),
            sdkConfidence: OperationTracker.shared.getSDKConfidence(stackTrace, OperationTracker.shared.extractFaultingLibrary(stackTrace)),
            faultingLibrary: OperationTracker.shared.extractFaultingLibrary(stackTrace),
            responsibleSDKComponent: OperationTracker.shared.determineResponsibleComponent(stackTrace),
            sdkVersion: OperationTracker.shared.sdkVersion,
            crashReporterPluginVersion: OperationTracker.shared.crashReporterPluginVersion,
            platform: OperationTracker.shared.platform,
            initFailurePoint: OperationTracker.shared.initFailurePoint,
            currentOperation: OperationTracker.shared.currentOperation ?? "",
            operationContext: OperationTracker.shared.operationContext,
            powerSaveMode: deviceInfoCollector.isPowerSaveMode(),
            isDebugBuild: deviceInfoCollector.isDebugBuild(),
            bootTime: deviceInfoCollector.getBootTime(),
            deviceUptime: deviceInfoCollector.getDeviceUptime(),
            timezone: deviceInfoCollector.getTimezone(),
            isVPNActive: deviceInfoCollector.isVPNActive(),
            isProxyActive: deviceInfoCollector.isProxyActive(),
            memoryPressure: deviceInfoCollector.getMemoryPressure(),
            wasNetworkRecentlyLost: NetworkReachabilityTracker.shared.wasNetworkRecentlyLost(),
            isStartupCrash: false
        )
    }

    /// Classify exception type for webhook parity with Android
    /// - Returns: "ANR" if application not responding, "Exception" otherwise
    private func classifyExceptionType(isANR: Bool) -> String {
        if isANR {
            return "ANR"  // Standardized ANR type
        }
        return "Exception"  // Standardized exception type (not the specific class name)
    }
    
    // MARK: - Get Stack Trace
    
    private func getStackTrace(exception: NSException) -> String {
        var stackTrace = "Exception: \(exception.name.rawValue)\n"
        stackTrace += "Reason: \(exception.reason ?? "No reason")\n\n"
        stackTrace += "Call Stack:\n"
        
        let symbols = exception.callStackSymbols
        for (index, symbol) in symbols.enumerated() {
            stackTrace += "\(index): \(symbol)\n"
        }
        
        return stackTrace
    }
    
    // MARK: - Get All Thread Info

    private func getAllThreadInfo() -> [ThreadInfo] {
        var threads: [ThreadInfo] = []

        // Get all threads in the current task
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)

        guard result == KERN_SUCCESS, let threads_list = threadList else {
            // Fallback to main thread only
            threads.append(getMainThreadInfo())
            return threads
        }

        // Use defer to ensure memory is freed
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads_list), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        }

        // Iterate through all threads
        for i in 0..<Int(threadCount) {
            let thread = threads_list[i]
            let threadInfo = getThreadInfo(thread: thread, index: i)
            threads.append(threadInfo)
        }

        return threads
    }

    // MARK: - Limit Thread Stack Frames (Optimization)

    /// Limit non-crashed thread stack traces to 10 frames (keep full stack for crashed thread)
    private func limitThreadStackFrames(_ threads: [ThreadInfo]) -> [ThreadInfo] {
        // COST OPTIMIZATION: Match Android limits
        let maxThreads = 5  // Max 5 threads total
        let maxStackLinesForCrashed = 100  // Max 100 lines for crashed thread
        let maxStackLinesForOthers = 10  // Max 10 lines for other threads
        let mainThreadId = UInt64(pthread_mach_thread_np(pthread_self()))

        // Find crashed/main thread
        let crashedThread = threads.first { $0.id == mainThreadId }

        // Get other important threads (prioritize "main" by name)
        let otherThreads = threads.filter { $0.id != mainThreadId }
            .sorted { a, b in
                // Prioritize main thread by name
                if a.name == "main" && b.name != "main" { return true }
                if a.name != "main" && b.name == "main" { return false }
                return false
            }
            .prefix(maxThreads - 1)

        // Combine: crashed thread + up to 4 others = max 5 threads
        let limitedThreads = ([crashedThread].compactMap { $0 } + otherThreads)

        return limitedThreads.map { thread in
            let stackLines = thread.stackTrace.split(separator: "\n")

            // Limit stack trace lines based on thread type
            let maxLines = (thread.id == mainThreadId) ? maxStackLinesForCrashed : maxStackLinesForOthers
            let limitedLines = stackLines.prefix(maxLines)
            let limitedStackTrace = limitedLines.joined(separator: "\n")

            // Add truncation notice if needed
            let finalStackTrace = stackLines.count > maxLines
                ? limitedStackTrace + "\n... [\(stackLines.count - maxLines) more lines truncated]"
                : limitedStackTrace

            return ThreadInfo(
                id: thread.id,
                name: thread.name,
                state: thread.state,
                priority: thread.priority,
                isDaemon: thread.isDaemon,
                stackTrace: finalStackTrace
            )
        }
    }

    private func getMainThreadInfo() -> ThreadInfo {
        let mainThread = Thread.main
        return ThreadInfo(
            id: UInt64(pthread_mach_thread_np(pthread_self())),
            name: mainThread.name ?? "main",
            state: "running",
            priority: Int(mainThread.threadPriority * 10),
            isDaemon: false,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )
    }

    private func getThreadInfo(thread: thread_t, index: Int) -> ThreadInfo {
        // Get thread basic info
        var threadInfo = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &threadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }

        var state = "unknown"
        var priority = 5

        if result == KERN_SUCCESS {
            // Map thread run state
            switch threadInfo.run_state {
            case TH_STATE_RUNNING:
                state = "running"
            case TH_STATE_STOPPED:
                state = "stopped"
            case TH_STATE_WAITING:
                state = "waiting"
            case TH_STATE_UNINTERRUPTIBLE:
                state = "uninterruptible"
            case TH_STATE_HALTED:
                state = "halted"
            default:
                state = "unknown"
            }

            priority = Int(threadInfo.cpu_usage / 10)
        }

        // Get thread name if available
        var threadName = getThreadName(thread: thread)
        if threadName.isEmpty {
            threadName = "Thread-\(index)"
        }

        // Check if it's the main thread
        let isMainThread = pthread_main_np() == 1 && thread == mach_thread_self()
        if isMainThread {
            threadName = "main"
        }

        // Thread.callStackSymbols returns the CALLING thread's stack, not the target thread's.
        // Capturing another thread's real stack requires Mach backtrace APIs per-thread,
        // which is complex and out of scope here. Mark it honestly so the field isn't misleading.
        let stackTrace = "(Stack trace unavailable for non-crashed threads)"

        return ThreadInfo(
            id: UInt64(thread),
            name: threadName,
            state: state,
            priority: priority,
            isDaemon: !isMainThread,
            stackTrace: stackTrace
        )
    }

    private func getThreadName(thread: thread_t) -> String {
        var name = [CChar](repeating: 0, count: 256)
        return pthread_from_mach_thread_np(thread).flatMap { pthread in
            pthread_getname_np(pthread, &name, name.count)
            return String(cString: name)
        } ?? ""
    }

    // MARK: - Get CPU Registers

    private func getCPURegisters() -> CPURegisters? {
        let thread = mach_thread_self()

        #if arch(arm64)
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)

        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        // Extract all ARM64 registers
        return CPURegisters(
            x0: state.__x.0, x1: state.__x.1, x2: state.__x.2, x3: state.__x.3,
            x4: state.__x.4, x5: state.__x.5, x6: state.__x.6, x7: state.__x.7,
            x8: state.__x.8, x9: state.__x.9, x10: state.__x.10, x11: state.__x.11,
            x12: state.__x.12, x13: state.__x.13, x14: state.__x.14, x15: state.__x.15,
            x16: state.__x.16, x17: state.__x.17, x18: state.__x.18, x19: state.__x.19,
            x20: state.__x.20, x21: state.__x.21, x22: state.__x.22, x23: state.__x.23,
            x24: state.__x.24, x25: state.__x.25, x26: state.__x.26, x27: state.__x.27,
            x28: state.__x.28,
            fp: state.__fp,
            lr: state.__lr,
            sp: state.__sp,
            pc: state.__pc,
            cpsr: UInt64(state.__cpsr)
        )
        #elseif arch(x86_64)
        // CRITICAL FIX #3: x86_64 Simulator Support
        var state = x86_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<UInt32>.size)

        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, thread_state_flavor_t(x86_THREAD_STATE64), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        // Extract x86_64 registers - map to ARM64 field names for compatibility
        // RAX, RBX, RCX, RDX, RSI, RDI map to x0-x5 concept
        return CPURegisters(
            x0: UInt64(state.__rax), x1: UInt64(state.__rbx), x2: UInt64(state.__rcx), x3: UInt64(state.__rdx),
            x4: UInt64(state.__rsi), x5: UInt64(state.__rdi), x6: UInt64(state.__r8), x7: UInt64(state.__r9),
            x8: UInt64(state.__r10), x9: UInt64(state.__r11), x10: UInt64(state.__r12), x11: UInt64(state.__r13),
            x12: UInt64(state.__r14), x13: UInt64(state.__r15), x14: 0, x15: 0,
            x16: 0, x17: 0, x18: 0, x19: 0,
            x20: 0, x21: 0, x22: 0, x23: 0,
            x24: 0, x25: 0, x26: 0, x27: 0,
            x28: 0,
            fp: UInt64(state.__rbp),
            lr: 0,  // x86_64 doesn't have link register
            sp: UInt64(state.__rsp),
            pc: UInt64(state.__rip),
            cpsr: UInt64(state.__rflags)
        )
        #else
        // Fallback for other architectures
        return nil
        #endif
    }

    // MARK: - Get Memory State

    private func getMemoryState() -> MemoryState? {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let pageSize = Int(vm_kernel_page_size)
        let toMB: (natural_t) -> Int64 = { Int64($0) * Int64(pageSize) / (1024 * 1024) }

        return MemoryState(
            usedMemoryMB: toMB(vmStats.active_count + vmStats.wire_count),
            freeMemoryMB: toMB(vmStats.free_count),
            activeMemoryMB: toMB(vmStats.active_count),
            inactiveMemoryMB: toMB(vmStats.inactive_count),
            wiredMemoryMB: toMB(vmStats.wire_count),
            compressedMemoryMB: toMB(vmStats.compressor_page_count),
            pageSize: pageSize,
            pageIns: Int64(vmStats.pageins),
            pageOuts: Int64(vmStats.pageouts)
        )
    }

    // MARK: - Get Binary Images (for Symbolication)

    private func getBinaryImages() -> [BinaryImage] {
        var images: [BinaryImage] = []

        let imageCount = _dyld_image_count()

        for i in 0..<imageCount {
            guard let header = _dyld_get_image_header(i),
                  let name = _dyld_get_image_name(i) else {
                continue
            }

            let slide = _dyld_get_image_vmaddr_slide(i)
            let imageName = URL(fileURLWithPath: String(cString: name)).lastPathComponent
            let imagePath = String(cString: name)

            // Get UUID from LC_UUID load command
            var uuid = ""
            var currentArch = ""
            var loadAddress: UInt64 = 0
            var maxAddress: UInt64 = 0

            // Get architecture
            #if arch(arm64)
            currentArch = "arm64"
            #elseif arch(arm64e)
            currentArch = "arm64e"
            #elseif arch(x86_64)
            currentArch = "x86_64"
            #else
            currentArch = "unknown"
            #endif

            // Calculate load address
            loadAddress = UInt64(bitPattern: Int64(Int(bitPattern: header)))

            // Parse Mach-O header to find UUID
            var commandPointer = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)

            for _ in 0..<header.pointee.ncmds {
                let loadCommand = commandPointer.assumingMemoryBound(to: load_command.self)

                // Check for UUID command
                if loadCommand.pointee.cmd == LC_UUID {
                    let uuidCommand = commandPointer.assumingMemoryBound(to: uuid_command.self)
                    let uuidBytes = withUnsafeBytes(of: uuidCommand.pointee.uuid) { Array($0) }

                    uuid = uuidBytes.map { String(format: "%02X", $0) }.joined()
                    uuid = "\(uuid.prefix(8))-\(uuid.dropFirst(8).prefix(4))-\(uuid.dropFirst(12).prefix(4))-\(uuid.dropFirst(16).prefix(4))-\(uuid.dropFirst(20))"
                }

                // Check for SEGMENT_64 to calculate max address
                if loadCommand.pointee.cmd == LC_SEGMENT_64 {
                    let segmentCommand = commandPointer.assumingMemoryBound(to: segment_command_64.self)
                    let segmentEnd = segmentCommand.pointee.vmaddr + UInt64(slide) + segmentCommand.pointee.vmsize
                    if segmentEnd > maxAddress {
                        maxAddress = segmentEnd
                    }
                }

                commandPointer = commandPointer.advanced(by: Int(loadCommand.pointee.cmdsize))
            }

            let binaryImage = BinaryImage(
                name: imageName,
                uuid: uuid,
                architecture: currentArch,
                loadAddress: String(format: "0x%llx", loadAddress),
                maxAddress: String(format: "0x%llx", maxAddress),
                path: imagePath
            )

            images.append(binaryImage)
        }

        return images
    }
}
