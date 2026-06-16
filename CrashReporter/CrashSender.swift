import Foundation
import Network
import Compression

class CrashSender {
    private let apiEndpoint: String
    private let crashStorage: CrashStorage
    private let session: URLSession
    private var isSending = false  // Prevent concurrent sends
    private let senderLock = NSLock()  // Thread-safe lock for isSending flag
    private let monitor = NWPathMonitor()

    // Request management
    private var activeTasks = Set<URLSessionDataTask>()
    private let taskLock = NSLock()  // Thread-safe lock for activeTasks

    init(apiEndpoint: String, crashStorage: CrashStorage) {
        self.apiEndpoint = apiEndpoint
        self.crashStorage = crashStorage

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        // Start network monitoring on background queue
        monitor.start(queue: DispatchQueue.global(qos: .background))
    }

    // MARK: - Request Management

    private func trackTask(_ task: URLSessionDataTask) {
        taskLock.lock()
        defer { taskLock.unlock() }
        activeTasks.insert(task)
    }

    private func untrackTask(_ task: URLSessionDataTask) {
        taskLock.lock()
        defer { taskLock.unlock() }
        activeTasks.remove(task)
    }

    func cancelAllPendingRequests() {
        taskLock.lock()
        defer { taskLock.unlock() }

        let cancelledCount = activeTasks.count
        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()

        if cancelledCount > 0 {
            CrashReporterLogger.info("Cancelled \(cancelledCount) pending request(s)", log: CrashReporterLogger.crashSender)
        }
    }

    // MARK: - Compression

    private func gzipCompress(_ data: Data) -> Data? {
        let sourceBuffer = [UInt8](data)
        // Allocate buffer with 10% overhead + 64 bytes for compression headers
        let maxCompressedSize = sourceBuffer.count + (sourceBuffer.count / 10) + 64
        var compressedBuffer = [UInt8](repeating: 0, count: maxCompressedSize)

        let compressedSize = compression_encode_buffer(
            &compressedBuffer,
            compressedBuffer.count,
            sourceBuffer,
            sourceBuffer.count,
            nil,
            COMPRESSION_ZLIB
        )

        guard compressedSize > 0 else { return nil }

        return Data(compressedBuffer.prefix(compressedSize))
    }

    // MARK: - Network Connectivity Check

    private func isNetworkAvailable() -> Bool {
        return monitor.currentPath.status == .satisfied
    }

    // MARK: - HTTP Status Code Handling

    private func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        switch statusCode {
        // Success (already handled but included for completeness)
        case 200...299:
            return true

        // Client errors - most should NOT be retried
        case 400, 401, 403, 404, 405, 406, 410, 413, 414, 415:
            // These indicate malformed requests or permission issues
            return false

        // Special cases: DO retry
        case 408:
            // Request timeout - server didn't respond in time, retry allowed
            return true
        case 429:
            // Too many requests (rate limit) - retry with backoff
            return true

        // Server errors - always retry
        case 500...599:
            return true

        // Unknown/redirect - treat as retryable to be safe
        default:
            return true
        }
    }

    // MARK: - Send Single Crash

    private func sendCrash(_ crashData: CrashData, metadata: CrashMetadata, fileURL: URL, completion: @escaping (Bool, String?) -> Void) {
        // Use the endpoint directly — New Relic provides the full ingest URL
        guard let url = URL(string: apiEndpoint) else {
            let errorMsg = "Invalid API endpoint URL"
            CrashReporterLogger.error("\(errorMsg)", log: CrashReporterLogger.crashSender)
            completion(false, errorMsg)
            return
        }

        do {
            // New Relic Events API requires a JSON array with an eventType field. Build the
            // FLAT event (New Relic drops nested objects) and array-wrap it.
            let event = flattenedEvent(crashData)

            let jsonData = try JSONSerialization.data(withJSONObject: [event], options: [.sortedKeys])

            let jsonSize = Double(jsonData.count) / 1024.0
            CrashReporterLogger.info("Sending crash to New Relic (\(String(format: "%.1f", jsonSize))KB)", log: CrashReporterLogger.crashSender)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("CrashReporter-iOS/1.0", forHTTPHeaderField: "User-Agent")
            // New Relic ingest key — for testing only
            request.setValue("eu01xe5d8f90a9ecc28b6963c670d8091beeNRAL", forHTTPHeaderField: "Api-Key")

            request.httpBody = jsonData

            var task: URLSessionDataTask?
            task = session.dataTask(with: request) { [weak self] data, response, error in
                defer {
                    if let task = task {
                        self?.untrackTask(task)
                    }
                }

                if let error = error {
                    let errorMsg = error.localizedDescription
                    CrashReporterLogger.error("Network error - \(errorMsg)", log: CrashReporterLogger.crashSender)
                    completion(false, errorMsg)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        CrashReporterLogger.info("Crash sent successfully - \(crashData.crashId) (Status: \(httpResponse.statusCode))", log: CrashReporterLogger.crashSender)
                        completion(true, nil)
                    } else {
                        let isRetryable = self?.isRetryableStatusCode(httpResponse.statusCode) ?? true
                        let errorMsg = "HTTP \(httpResponse.statusCode)\(isRetryable ? "" : ":PERMANENT")"

                        if isRetryable {
                            CrashReporterLogger.warning("Retryable error - HTTP \(httpResponse.statusCode)", log: CrashReporterLogger.crashSender)
                        } else {
                            CrashReporterLogger.error("Permanent error - HTTP \(httpResponse.statusCode) (won't retry)", log: CrashReporterLogger.crashSender)
                        }

                        // Log response body for debugging
                        if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                            CrashReporterLogger.debug("Response: \(responseBody)", log: CrashReporterLogger.crashSender)
                        }

                        completion(false, errorMsg)
                    }
                } else {
                    completion(false, "No HTTP response")
                }
            }

            if let task = task {
                trackTask(task)
                task.resume()
            }

        } catch {
            let errorMsg = "Error encoding crash data: \(error.localizedDescription)"
            CrashReporterLogger.error("\(errorMsg)", log: CrashReporterLogger.crashSender)
            completion(false, errorMsg)
        }
    }

    // MARK: - Build Payload (for host-driven signed send)

    /// Build the flattened crash payload as a single JSON object string — the EXACT bytes the
    /// host (Unity C#) signs and POSTs. Mirrors the New Relic event the native sender would build.
    func buildPayloadJson(_ crashData: CrashData) -> String? {
        do {
            let event = flattenedEvent(crashData)
            let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            CrashReporterLogger.error("buildPayloadJson failed: \(error.localizedDescription)", log: CrashReporterLogger.crashSender)
            return nil
        }
    }

    /// Build the New Relic event as a FLAT top-level dictionary. New Relic silently drops nested
    /// JSON objects, so the device/app/state structs must be hoisted to top-level primitives
    /// (mirrors the Android EnhancedCrashSender flattening + field names). Nested containers and
    /// arrays New Relic can't store (threads, breadcrumbs, registers, binary images, etc.) are
    /// intentionally omitted.
    func flattenedEvent(_ crashData: CrashData) -> [String: Any] {
        var e: [String: Any] = [:]

        // Required by New Relic NRQL + per-studio filtering
        e["eventType"] = "ZBDCrashReport"
        e["gameId"] = crashData.appInfo.bundleId

        // Crash identity
        e["crashId"] = crashData.crashId
        e["timestamp"] = crashData.timestamp
        e["exceptionType"] = crashData.exceptionType
        e["exceptionMessage"] = crashData.exceptionMessage
        e["stackTrace"] = crashData.stackTrace
        e["threadName"] = crashData.threadName
        e["environment"] = crashData.environment
        e["platform"] = crashData.platform
        e["severity"] = crashData.severity
        e["issueTitle"] = crashData.issueTitle
        e["crashFingerprint"] = crashData.crashFingerprint ?? ""

        // Classification
        e["isANR"] = crashData.isANR
        e["isNativeCrash"] = crashData.isNativeCrash
        e["anrDurationMs"] = crashData.anrDurationMs ?? 0
        e["nativeSignal"] = crashData.nativeSignal ?? ""
        e["nativeFaultAddress"] = crashData.nativeFaultAddress ?? ""
        e["isInCrashLoop"] = crashData.isInCrashLoop
        e["crashLoopCount"] = crashData.crashLoopCount
        e["isStartupCrash"] = crashData.isStartupCrash

        // SDK attribution (SLO)
        e["isSDKRelated"] = crashData.isSDKRelated
        e["sdkConfidence"] = crashData.sdkConfidence ?? "none"
        e["faultingLibrary"] = crashData.faultingLibrary ?? ""
        e["responsibleSDKComponent"] = crashData.responsibleSDKComponent
        e["sdkVersion"] = crashData.sdkVersion
        e["crashReporterPluginVersion"] = crashData.crashReporterPluginVersion
        e["initFailurePoint"] = crashData.initFailurePoint
        e["currentOperation"] = crashData.currentOperation

        // Device/runtime flags
        e["powerSaveMode"] = crashData.powerSaveMode
        e["isDebugBuild"] = crashData.isDebugBuild
        e["bootTime"] = crashData.bootTime
        e["deviceUptime"] = crashData.deviceUptime
        e["timezone"] = crashData.timezone
        e["isVPNActive"] = crashData.isVPNActive
        e["isProxyActive"] = crashData.isProxyActive
        e["memoryPressure"] = crashData.memoryPressure
        e["wasNetworkRecentlyLost"] = crashData.wasNetworkRecentlyLost

        // Flattened: DeviceInfo
        e["deviceModel"] = crashData.deviceInfo.model
        e["deviceManufacturer"] = crashData.deviceInfo.manufacturer
        e["iosVersion"] = crashData.deviceInfo.iosVersion
        e["deviceApiLevel"] = crashData.deviceInfo.apiLevel
        e["deviceBrand"] = crashData.deviceInfo.brand
        e["screenWidth"] = crashData.deviceInfo.screenWidth
        e["screenHeight"] = crashData.deviceInfo.screenHeight

        // Flattened: AppInfo
        e["appVersion"] = crashData.appInfo.versionName
        e["appPackageName"] = crashData.appInfo.bundleId
        e["appVersionCode"] = crashData.appInfo.versionCode

        // Flattened: DeviceState
        e["batteryLevel"] = crashData.deviceState.batteryLevel
        e["isCharging"] = crashData.deviceState.isCharging
        e["availableMemoryMB"] = crashData.deviceState.availableMemoryMB
        e["totalMemoryMB"] = crashData.deviceState.totalMemoryMB
        e["lowMemory"] = crashData.deviceState.lowMemory
        e["orientation"] = crashData.deviceState.orientation
        e["thermalState"] = crashData.deviceState.thermalState

        // Flattened: NetworkInfo
        e["networkConnected"] = crashData.networkInfo.isConnected
        e["networkType"] = crashData.networkInfo.connectionType

        // Flattened: MemoryInfo
        e["heapSizeKB"] = crashData.memoryInfo.heapSizeKB
        e["heapFreeKB"] = crashData.memoryInfo.heapFreeKB

        // Flattened: CpuInfo
        e["cpuCores"] = crashData.cpuInfo.coreCount
        e["cpuArchitecture"] = crashData.cpuInfo.architecture

        // Flattened: ProcessInfo
        e["processName"] = crashData.processInfo.processName
        e["processForeground"] = crashData.processInfo.foreground

        // Operation context (best-effort, from customData / operationContext)
        let opCtx = crashData.customData.merging(crashData.operationContext) { current, _ in current }
        e["lastSuccessfulOperation"] = opCtx["lastSuccessfulOperation"] ?? "none"
        e["lastFailedOperation"] = opCtx["lastFailedOperation"] ?? "none"
        e["lastOperationError"] = opCtx["lastOperationError"] ?? "none"

        return e
    }

    // MARK: - Send All Pending Crashes (With Queue Management)

    func sendAllPendingCrashes() {
        print("🔍 [SEND] sendAllPendingCrashes() called")

        // Use lock to prevent concurrent sending (thread-safe)
        senderLock.lock()
        defer { senderLock.unlock() }

        // Prevent concurrent sending
        guard !isSending else {
            print("⚠️ [SEND] Already sending crashes, skipping...")
            CrashReporterLogger.info("Already sending crashes, skipping...", log: CrashReporterLogger.crashSender)
            return
        }

        isSending = true
        // NOTE: Do NOT use defer to reset isSending here. The actual send work is async
        // (URLSession callbacks + dispatchGroup), so a defer would reset the flag before
        // any network calls complete, defeating the concurrency guard entirely.
        // isSending is reset inside the dispatchGroup.notify block below.

        // Check network connectivity before attempting to send
        print("🔍 [SEND] Checking network availability...")
        guard isNetworkAvailable() else {
            print("❌ [SEND] Network unavailable!")
            CrashReporterLogger.info("Network unavailable, deferring crash delivery", log: CrashReporterLogger.crashSender)
            return
        }

        print("✅ [SEND] Network is available")

        // Get only pending crashes (with metadata)
        print("🔍 [SEND] Getting pending crashes from storage...")
        let pendingCrashes = crashStorage.getPendingCrashFiles()

        print("📊 [SEND] Found \(pendingCrashes.count) pending crash(es)")

        if pendingCrashes.isEmpty {
            print("❌ [SEND] No pending crashes to send")
            CrashReporterLogger.info("No pending crashes to send", log: CrashReporterLogger.crashSender)
            return
        }

        print("✅ [SEND] Starting to send \(pendingCrashes.count) crash(es)...")
        CrashReporterLogger.info("Sending \(pendingCrashes.count) pending crash(es)", log: CrashReporterLogger.crashSender)

        // Use dispatch group to track all sends
        let dispatchGroup = DispatchGroup()
        var successCount = 0
        var failedCount = 0

        for (fileURL, var metadata) in pendingCrashes {
            // Load crash data
            guard let crashData = crashStorage.loadCrash(from: fileURL) else {
                CrashReporterLogger.warning("Failed to load crash from \(fileURL.lastPathComponent)", log: CrashReporterLogger.crashSender)
                continue
            }

            // Mark as sending
            metadata.status = .sending
            crashStorage.updateMetadata(metadata)

            dispatchGroup.enter()

            // Send the crash
            sendCrash(crashData, metadata: metadata, fileURL: fileURL) { [weak self] success, errorMessage in
                defer { dispatchGroup.leave() }

                guard let self = self else { return }

                // Update metadata based on result
                metadata.recordSendAttempt(success: success, errorMessage: errorMessage)
                self.crashStorage.updateMetadata(metadata)

                if success {
                    // Delete crash after successful send
                    self.crashStorage.deleteCrash(fileURL: fileURL)
                    successCount += 1
                } else {
                    // Check if permanent error (HTTP status indicates no retry)
                    let isPermanent = errorMessage?.contains(":PERMANENT") ?? false

                    if isPermanent {
                        CrashReporterLogger.error("Crash \(crashData.crashId) failed with permanent error - deleting without retry", log: CrashReporterLogger.crashSender)
                        self.crashStorage.deleteCrash(fileURL: fileURL)
                    } else if metadata.shouldRetry(maxRetries: 3) {
                        CrashReporterLogger.info("Will retry crash \(crashData.crashId) (attempt \(metadata.retryCount)/3)", log: CrashReporterLogger.crashSender)
                        // Reset status to pending for next attempt
                        metadata.status = .pending
                        self.crashStorage.updateMetadata(metadata)
                    } else {
                        CrashReporterLogger.error("Crash \(crashData.crashId) failed after \(metadata.retryCount) attempts - deleting", log: CrashReporterLogger.crashSender)
                        // Delete after max retries
                        self.crashStorage.deleteCrash(fileURL: fileURL)
                    }
                    failedCount += 1
                }
            }
        }

        // Wait for all sends to complete, then reset isSending
        dispatchGroup.notify(queue: .main) { [weak self] in
            CrashReporterLogger.info("Finished processing crashes - Success: \(successCount), Failed: \(failedCount)", log: CrashReporterLogger.crashSender)

            // Reset concurrency guard only after all async work is truly done
            self?.senderLock.lock()
            self?.isSending = false
            self?.senderLock.unlock()

            // Perform cleanup after sending
            self?.crashStorage.performCleanup()
        }
    }

    // MARK: - Legacy Send Method (kept for backward compatibility)

    func sendCrash(_ crashData: CrashData, completion: @escaping (Bool) -> Void) {
        // Create temporary metadata
        let metadata = CrashMetadata(crashId: crashData.crashId)
        let tempURL = URL(fileURLWithPath: "/tmp/crash_\(crashData.crashId).json")

        sendCrash(crashData, metadata: metadata, fileURL: tempURL) { success, _ in
            completion(success)
        }
    }

    deinit {
        monitor.cancel()
        cancelAllPendingRequests()
    }
}
