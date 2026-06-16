import Foundation
import Darwin

// MARK: - C Bridge Functions for Unity

@_cdecl("CrashReporter_Initialize")
public func CrashReporter_Initialize(_ apiEndpoint: UnsafePointer<CChar>) {
    guard apiEndpoint != nil else {
        print("❌ CrashReporter_Initialize: Null pointer for apiEndpoint")
        return
    }
    let endpoint = String(cString: apiEndpoint)
    CrashReporterCore.shared.initialize(apiEndpoint: endpoint)
}

@_cdecl("CrashReporter_IsInitialized")
public func CrashReporter_IsInitialized() -> Bool {
    return CrashReporterCore.shared.checkIsInitialized()
}

@_cdecl("CrashReporter_GetPendingCrashCount")
public func CrashReporter_GetPendingCrashCount() -> Int32 {
    return Int32(CrashReporterCore.shared.getPendingCrashCount())
}

@_cdecl("CrashReporter_SendPendingCrashes")
public func CrashReporter_SendPendingCrashes() {
    CrashReporterCore.shared.sendPendingCrashesNow()
}

// MARK: - Host-driven signed send (Unity C# pulls, signs with the attestation key, sends)

@_cdecl("CrashReporter_SetDeferSendToHost")
public func CrashReporter_SetDeferSendToHost(_ enabled: Bool) {
    CrashReporterCore.shared.setDeferSendToHost(enabled)
}

@_cdecl("CrashReporter_GetPendingCrashesAsJson")
public func CrashReporter_GetPendingCrashesAsJson() -> UnsafePointer<CChar>? {
    let json = CrashReporterCore.shared.getPendingCrashesAsJson()
    return UnsafePointer((json as NSString).utf8String)
}

@_cdecl("CrashReporter_MarkCrashAsSent")
public func CrashReporter_MarkCrashAsSent(_ crashId: UnsafePointer<CChar>?) {
    guard let crashId = crashId else { return }
    CrashReporterCore.shared.markCrashAsSent(String(cString: crashId))
}

@_cdecl("CrashReporter_SetUserContext")
public func CrashReporter_SetUserContext(
    _ userId: UnsafePointer<CChar>?,
    _ email: UnsafePointer<CChar>?,
    _ username: UnsafePointer<CChar>?
) {
    let userIdStr = userId != nil ? String(cString: userId!) : nil
    let emailStr = email != nil ? String(cString: email!) : nil
    let usernameStr = username != nil ? String(cString: username!) : nil

    CrashReporterCore.shared.setUserContext(userId: userIdStr, email: emailStr, username: usernameStr)
}

@_cdecl("CrashReporter_SetTag")
public func CrashReporter_SetTag(_ key: UnsafePointer<CChar>, _ value: UnsafePointer<CChar>) {
    guard key != nil, value != nil else {
        print("❌ CrashReporter_SetTag: Null pointer for key or value")
        return
    }
    let keyStr = String(cString: key)
    let valueStr = String(cString: value)
    CrashReporterCore.shared.setTag(key: keyStr, value: valueStr)
}

@_cdecl("CrashReporter_RemoveTag")
public func CrashReporter_RemoveTag(_ key: UnsafePointer<CChar>) {
    guard key != nil else {
        print("❌ CrashReporter_RemoveTag: Null pointer for key")
        return
    }
    let keyStr = String(cString: key)
    CrashReporterCore.shared.removeTag(key: keyStr)
}

@_cdecl("CrashReporter_SetEnvironment")
public func CrashReporter_SetEnvironment(_ env: UnsafePointer<CChar>) {
    guard env != nil else {
        print("❌ CrashReporter_SetEnvironment: Null pointer for env")
        return
    }
    let envStr = String(cString: env)
    CrashReporterCore.shared.setEnvironment(env: envStr)
}

@_cdecl("CrashReporter_AddBreadcrumb")
public func CrashReporter_AddBreadcrumb(
    _ category: UnsafePointer<CChar>,
    _ message: UnsafePointer<CChar>,
    _ level: UnsafePointer<CChar>
) {
    guard category != nil, message != nil, level != nil else {
        print("❌ CrashReporter_AddBreadcrumb: Null pointer for category, message, or level")
        return
    }
    let categoryStr = String(cString: category)
    let messageStr = String(cString: message)
    let levelStr = String(cString: level)

    CrashReporterCore.shared.addBreadcrumb(category: categoryStr, message: messageStr, level: levelStr, data: [:])
}

@_cdecl("CrashReporter_HasPendingCrashes")
public func CrashReporter_HasPendingCrashes() -> Int32 {
    return CrashReporterCore.shared.getPendingCrashCount() > 0 ? 1 : 0
}

@_cdecl("CrashReporter_PendingCrashCount")
public func CrashReporter_PendingCrashCount() -> Int32 {
    return Int32(CrashReporterCore.shared.getPendingCrashCount())
}

// MARK: - SDK Context Functions (New)

@_cdecl("CrashReporter_SetSDKInfo")
public func CrashReporter_SetSDKInfo(_ json: UnsafePointer<CChar>) {
    let jsonString = String(cString: json)
    SDKInfoManager.shared.update(from: jsonString)
}

@_cdecl("CrashReporter_SetUnityInfo")
public func CrashReporter_SetUnityInfo(_ json: UnsafePointer<CChar>) {
    let jsonString = String(cString: json)
    UnityInfoManager.shared.update(from: jsonString)
}

@_cdecl("CrashReporter_SetPerformanceMetrics")
public func CrashReporter_SetPerformanceMetrics(_ json: UnsafePointer<CChar>) {
    let jsonString = String(cString: json)
    SDKPerformanceMetricsManager.shared.update(from: jsonString)
}

@_cdecl("CrashReporter_SetSDKUserState")
public func CrashReporter_SetSDKUserState(_ json: UnsafePointer<CChar>) {
    let jsonString = String(cString: json)
    SDKUserStateManager.shared.update(from: jsonString)
}

@_cdecl("CrashReporter_ClearAllCrashes")
public func CrashReporter_ClearAllCrashes() {
    CrashReporterCore.shared.clearAllCrashes()
}

// MARK: - Operation Tracking (New)

@_cdecl("CrashReporter_SetCurrentOperation")
public func CrashReporter_SetCurrentOperation(_ operation: UnsafePointer<CChar>?) {
    let operationStr = operation != nil ? String(cString: operation!) : nil
    OperationTracker.shared.setCurrentOperation(operationStr)
}

@_cdecl("CrashReporter_GetCurrentOperation")
public func CrashReporter_GetCurrentOperation() -> UnsafePointer<CChar>? {
    guard let operation = OperationTracker.shared.getCurrentOperation() else { return nil }
    return UnsafePointer((operation as NSString).utf8String)
}

@_cdecl("CrashReporter_SetLastSuccessfulOperation")
public func CrashReporter_SetLastSuccessfulOperation(_ operation: UnsafePointer<CChar>) {
    guard operation != nil else { return }
    let operationStr = String(cString: operation)
    OperationTracker.shared.setLastSuccessfulOperation(operationStr)
}

@_cdecl("CrashReporter_GetLastSuccessfulOperation")
public func CrashReporter_GetLastSuccessfulOperation() -> UnsafePointer<CChar>? {
    guard let operation = OperationTracker.shared.getLastSuccessfulOperation() else { return nil }
    return UnsafePointer((operation as NSString).utf8String)
}

@_cdecl("CrashReporter_SetLastFailedOperation")
public func CrashReporter_SetLastFailedOperation(_ operation: UnsafePointer<CChar>, _ reason: UnsafePointer<CChar>) {
    guard operation != nil, reason != nil else { return }
    let operationStr = String(cString: operation)
    let reasonStr = String(cString: reason)
    OperationTracker.shared.setLastFailedOperation(operationStr, reason: reasonStr)
}

@_cdecl("CrashReporter_GetLastFailedOperation")
public func CrashReporter_GetLastFailedOperation() -> UnsafePointer<CChar>? {
    guard let operation = OperationTracker.shared.getLastFailedOperation() else { return nil }
    return UnsafePointer((operation as NSString).utf8String)
}

@_cdecl("CrashReporter_GetLastFailureReason")
public func CrashReporter_GetLastFailureReason() -> UnsafePointer<CChar>? {
    guard let reason = OperationTracker.shared.getLastFailureReason() else { return nil }
    return UnsafePointer((reason as NSString).utf8String)
}

@_cdecl("CrashReporter_SetSDKVersion")
public func CrashReporter_SetSDKVersion(_ version: UnsafePointer<CChar>) {
    guard version != nil else { return }
    let versionStr = String(cString: version)
    OperationTracker.shared.setSDKVersion(versionStr)
}

@_cdecl("CrashReporter_SetInitFailurePoint")
public func CrashReporter_SetInitFailurePoint(_ failurePoint: UnsafePointer<CChar>) {
    guard failurePoint != nil else { return }
    let failureStr = String(cString: failurePoint)
    OperationTracker.shared.setInitFailurePoint(failureStr)
}

@_cdecl("CrashReporter_SetResponsibleComponent")
public func CrashReporter_SetResponsibleComponent(_ component: UnsafePointer<CChar>) {
    guard component != nil else { return }
    let componentStr = String(cString: component)
    OperationTracker.shared.setResponsibleComponent(componentStr)
}

// MARK: - Managed Exception Handler (C# Exceptions)

/// Handle managed C# exceptions immediately (like Android)
/// Called from Unity when C# exceptions occur
@_cdecl("CrashReporter_HandleManagedException")
public func CrashReporter_HandleManagedException(
    _ exceptionType: UnsafePointer<CChar>,
    _ exceptionMessage: UnsafePointer<CChar>,
    _ stackTrace: UnsafePointer<CChar>,
    _ isFatal: Bool
) {
    guard exceptionType != nil, exceptionMessage != nil, stackTrace != nil else {
        print("❌ CrashReporter_HandleManagedException: Null pointer for exception data")
        return
    }

    let exceptionTypeStr = String(cString: exceptionType)
    let exceptionMessageStr = String(cString: exceptionMessage)
    let stackTraceStr = String(cString: stackTrace)

    print("🔴 [MANAGED_EXCEPTION] Handling C# exception: \(exceptionTypeStr) - \(exceptionMessageStr)")

    // Get crash handler from shared instance
    guard let crashHandler = CrashReporterCore.shared.getCrashHandler() else {
        print("❌ [MANAGED_EXCEPTION] Crash handler not available")
        return
    }

    // Handle the managed exception
    crashHandler.handleManagedException(
        exceptionType: exceptionTypeStr,
        exceptionMessage: exceptionMessageStr,
        stackTrace: stackTraceStr,
        isFatal: isFatal
    )
}

// MARK: - Native Crash Trigger (Testing Only)

@_cdecl("TriggerSignalCrash")
public func TriggerSignalCrash(_ signal: Int32) {
    print("💥 TriggerSignalCrash: Sending signal \(signal) to process")
    kill(getpid(), signal)
}
