import Foundation

class CrashStorage {
    private let crashDirectory: URL
    private let metadataDirectory: URL
    private let fileManager = FileManager.default

    // Configuration
    private let maxCrashCount = 50        // Keep only 50 most recent crashes
    private let expiryDays = 7            // Delete crashes older than 7 days
    private let maxRetries = 3            // Max retry attempts per crash

    init() {
        // Create crashes directory in app's documents folder
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("❌ CrashStorage: Unable to access Documents directory")
        }

        crashDirectory = documentsPath.appendingPathComponent("crashes", isDirectory: true)
        metadataDirectory = documentsPath.appendingPathComponent("crash_metadata", isDirectory: true)

        // Create directories if they don't exist
        createDirectoryIfNeeded(crashDirectory)
        createDirectoryIfNeeded(metadataDirectory)

        // Perform cleanup in background to avoid blocking startup
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performCleanup()
        }
    }

    private func createDirectoryIfNeeded(_ directory: URL) {
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // MARK: - Helper Methods

    /// Extract crash ID from filename (e.g., "crash_abc123.json" -> "abc123")
    private func extractCrashId(from fileURL: URL) -> String {
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        return fileName.replacingOccurrences(of: "crash_", with: "")
    }

    // MARK: - Disk Space Check

    private func getAvailableDiskSpace() -> Int64 {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let documentsPath = paths.first else { return 0 }

        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: documentsPath)
            if let availableSpace = attributes[.systemFreeSize] as? NSNumber {
                return availableSpace.int64Value
            }
        } catch {
            CrashReporterLogger.error("Error checking disk space - \(error)", log: CrashReporterLogger.crashStorage)
        }
        return 0
    }

    private func hasSufficientDiskSpace() -> Bool {
        // Require at least 1 MB free space
        let minRequiredSpace: Int64 = 1024 * 1024
        let available = getAvailableDiskSpace()
        return available > minRequiredSpace
    }

    // MARK: - Save Crash

    func saveCrash(_ crashData: CrashData, isSignalCrash: Bool = false) {
        print("🔍 [STORAGE] saveCrash called - crashId: \(crashData.crashId), isSignalCrash: \(isSignalCrash)")

        // Check available disk space before saving
        guard hasSufficientDiskSpace() else {
            let availableMB = getAvailableDiskSpace() / (1024 * 1024)
            print("❌ [STORAGE] Insufficient disk space - only \(availableMB)MB available")
            CrashReporterLogger.warning("Insufficient disk space - only \(availableMB)MB available, skipping crash save", log: CrashReporterLogger.crashStorage)
            return
        }

        let fileName = "crash_\(crashData.crashId).json"
        let fileURL = crashDirectory.appendingPathComponent(fileName)

        print("📝 [STORAGE] Saving to: \(fileURL.path)")

        do {
            // CRITICAL FIX #5: OOM Edge Case - Use autoreleasepool to free memory immediately
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted

            let jsonData = try encoder.encode(crashData)
            print("✅ [STORAGE] Encoded crash to JSON - size: \(jsonData.count) bytes")

            // For signal crashes, use synchronous write with data protection
            if isSignalCrash {
                print("🔍 [STORAGE] Writing signal crash with synchronous flush...")
                try jsonData.write(to: fileURL, options: [.atomic, .completeFileProtection])
                print("✅ [STORAGE] File written to disk")

                // Force flush to disk immediately (with proper cleanup using defer)
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer { try? fileHandle.close() }  // Guarantees close() is called even if synchronize() throws
                try fileHandle.synchronize()

                print("✅ [STORAGE] Signal crash saved (synchronous) - \(fileName)")
                CrashReporterLogger.info("Signal crash saved (synchronous) - \(fileName)", log: CrashReporterLogger.crashStorage)

                // Create metadata but skip cleanup (too slow for signal handler)
                let metadata = CrashMetadata(crashId: crashData.crashId)
                saveMetadata(metadata)
            } else {
                // Normal exception crash
                try jsonData.write(to: fileURL)
                CrashReporterLogger.info("Crash saved - \(fileName)", log: CrashReporterLogger.crashStorage)

                // Create metadata for this crash
                let metadata = CrashMetadata(crashId: crashData.crashId)
                saveMetadata(metadata)

                // Cleanup old crashes after saving new one
                performCleanup()
            }

        } catch let error as NSError {
            // CRITICAL FIX #5: Differentiate between OOM and other errors
            if error.code == NSFileWriteOutOfSpaceError {
                CrashReporterLogger.error("Out of disk space - cannot save crash", log: CrashReporterLogger.crashStorage)
            } else if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOMEM) {
                CrashReporterLogger.error("Out of memory - crash handler degrading gracefully", log: CrashReporterLogger.crashStorage)
            } else {
                CrashReporterLogger.error("Error saving crash - \(error.localizedDescription)", log: CrashReporterLogger.crashStorage)
            }
        } catch {
            CrashReporterLogger.error("Error saving crash - \(error)", log: CrashReporterLogger.crashStorage)
        }
    }

    // MARK: - Metadata Management

    private func saveMetadata(_ metadata: CrashMetadata) {
        let fileName = "meta_\(metadata.crashId).json"
        let fileURL = metadataDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(metadata)
            try jsonData.write(to: fileURL)
        } catch {
            print("❌ CrashStorage: Error saving metadata - \(error)")
        }
    }

    private func loadMetadata(crashId: String) -> CrashMetadata? {
        let fileName = "meta_\(crashId).json"
        let fileURL = metadataDirectory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(CrashMetadata.self, from: jsonData)
            return metadata
        } catch {
            print("❌ CrashStorage: Error loading metadata - \(error)")
            return nil
        }
    }

    func updateMetadata(_ metadata: CrashMetadata) {
        saveMetadata(metadata)
    }

    private func deleteMetadata(crashId: String) {
        let fileName = "meta_\(crashId).json"
        let fileURL = metadataDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    // MARK: - Get Pending Crashes (Only Unsent)

    func getPendingCrashFiles() -> [(fileURL: URL, metadata: CrashMetadata)] {
        var pendingCrashes: [(URL, CrashMetadata)] = []

        print("🔍 [STORAGE] getPendingCrashFiles - crash directory: \(crashDirectory.path)")

        do {
            let files = try fileManager.contentsOfDirectory(at: crashDirectory, includingPropertiesForKeys: nil)
            print("📊 [STORAGE] Total files in directory: \(files.count)")

            let crashFiles = files.filter { $0.pathExtension == "json" }
            print("📊 [STORAGE] JSON crash files found: \(crashFiles.count)")

            for fileURL in crashFiles {
                print("🔍 [STORAGE] Processing crash file: \(fileURL.lastPathComponent)")

                let crashId = extractCrashId(from: fileURL)
                print("   Crash ID: \(crashId)")

                // Load or create metadata
                let metadata = loadMetadata(crashId: crashId) ?? CrashMetadata(crashId: crashId)
                print("   Metadata status: \(metadata.status)")

                // Only include pending or failed (with retries left) crashes
                if metadata.status == .pending || (metadata.status == .failed && metadata.shouldRetry(maxRetries: maxRetries)) {
                    print("   ✅ Adding to pending list")
                    pendingCrashes.append((fileURL, metadata))
                } else {
                    print("   ⏭️ Skipping (status: \(metadata.status))")
                }
            }

            print("📊 [STORAGE] Total pending crashes to send: \(pendingCrashes.count)")

            // Sort by creation date (oldest first)
            pendingCrashes.sort { (crash1: (fileURL: URL, metadata: CrashMetadata), crash2: (fileURL: URL, metadata: CrashMetadata)) in
                crash1.metadata.createdAt < crash2.metadata.createdAt
            }

        } catch {
            print("❌ [STORAGE] Error getting pending crashes - \(error)")
        }

        return pendingCrashes
    }

    // MARK: - Load Crash

    func loadCrash(from fileURL: URL) -> CrashData? {
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let crashData = try decoder.decode(CrashData.self, from: jsonData)
            return crashData
        } catch {
            print("❌ CrashStorage: Error loading crash from \(fileURL.lastPathComponent) - \(error)")
            return nil
        }
    }

    // MARK: - Delete Crash

    func deleteCrash(fileURL: URL) {
        // Extract crash ID from filename
        let crashId = extractCrashId(from: fileURL)

        // Delete crash file
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                print("✅ CrashStorage: Crash deleted - \(fileURL.lastPathComponent)")
            }
        } catch {
            print("❌ CrashStorage: Error deleting crash \(fileURL.lastPathComponent) - \(error)")
        }

        // Delete metadata
        deleteMetadata(crashId: crashId)
    }

    func deleteCrashById(crashId: String) {
        let fileName = "crash_\(crashId).json"
        let fileURL = crashDirectory.appendingPathComponent(fileName)
        deleteCrash(fileURL: fileURL)
    }

    // MARK: - Get Pending Crash Count

    func getPendingCrashCount() -> Int {
        return getPendingCrashFiles().count
    }

    // MARK: - Cleanup Operations

    func performCleanup() {
        performOptimizedCleanup()
    }

    private func performOptimizedCleanup() {
        do {
            let files = try fileManager.contentsOfDirectory(at: crashDirectory, includingPropertiesForKeys: [.creationDateKey])
            var crashFilesWithDates: [(url: URL, date: Date)] = []
            var expiredCount = 0
            var failedCount = 0

            let expiryDate = Date().addingTimeInterval(TimeInterval(-expiryDays * 24 * 60 * 60))

            // Single pass: identify crashes to delete and collect dates
            for fileURL in files {
                guard fileURL.pathExtension == "json" else { continue }

                let crashId = extractCrashId(from: fileURL)
                var shouldDelete = false

                // Load metadata to check status and expiry
                if let metadata = loadMetadata(crashId: crashId) {
                    // Delete if expired
                    if metadata.isExpired(expiryDays: expiryDays) {
                        deleteCrash(fileURL: fileURL)
                        expiredCount += 1
                        shouldDelete = true
                    }
                    // Delete if failed with no retries left
                    else if metadata.status == .failed && !metadata.shouldRetry(maxRetries: maxRetries) {
                        deleteCrash(fileURL: fileURL)
                        failedCount += 1
                        shouldDelete = true
                    }
                } else {
                    // No metadata - check file creation date
                    if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                       let creationDate = attributes[.creationDate] as? Date {
                        if creationDate < expiryDate {
                            deleteCrash(fileURL: fileURL)
                            expiredCount += 1
                            shouldDelete = true
                        }
                    }
                }

                // Collect remaining files for excess cleanup check
                if !shouldDelete {
                    if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                       let creationDate = attributes[.creationDate] as? Date {
                        crashFilesWithDates.append((url: fileURL, date: creationDate))
                    }
                }
            }

            // Handle excess crashes (if still over limit after deletions)
            if crashFilesWithDates.count > maxCrashCount {
                // Sort by creation date (oldest first)
                crashFilesWithDates.sort { $0.date < $1.date }

                // Delete oldest crashes to get down to maxCrashCount
                let toDelete = crashFilesWithDates.count - maxCrashCount
                for i in 0..<toDelete {
                    deleteCrash(fileURL: crashFilesWithDates[i].url)
                }

                CrashReporterLogger.info("Cleaned up \(toDelete) excess crash(es) (max: \(maxCrashCount))", log: CrashReporterLogger.crashStorage)
            }

            // Log summary
            let totalDeleted = expiredCount + failedCount
            if totalDeleted > 0 {
                CrashReporterLogger.info("Cleanup complete - Expired: \(expiredCount), Failed: \(failedCount)", log: CrashReporterLogger.crashStorage)
            }

        } catch {
            CrashReporterLogger.error("Error during cleanup - \(error)", log: CrashReporterLogger.crashStorage)
        }
    }


    // MARK: - Delete All Crashes

    func deleteAllCrashes() {
        let files = getPendingCrashFiles()
        for (fileURL, _) in files {
            deleteCrash(fileURL: fileURL)
        }
        CrashReporterLogger.info("All crashes deleted", log: CrashReporterLogger.crashStorage)
    }
}
