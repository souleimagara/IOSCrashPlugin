import Foundation

/// Async-safe crash marker handling
///
/// When a signal crash occurs, the signal handler writes a minimal marker file.
/// On app launch, CrashReporter detects this marker and reports the previous crash.
struct CrashMarkerHandler {
    private static let markerFileName = "crash_marker.json"

    // MARK: - Get Marker Path

    static func getMarkerFilePath() -> String {
        // Get Documents directory path
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let documentsPath = paths.first else {
            return ""
        }
        return (documentsPath as NSString).appendingPathComponent(markerFileName)
    }

    // MARK: - Write Marker (Async-Safe)

    /// Write a minimal crash marker file (async-safe for signal handlers)
    /// Only writes: signal number, timestamp, and a marker ID
    static func writeMarkerFile(signalNumber: Int32) {
        let markerPath = getMarkerFilePath()

        // DIAGNOSTIC: Log to stderr (async-safe)
        let diagMsg = "🔍 [CRASH_MARKER] writeMarkerFile called for signal \(signalNumber)\n"
        _ = write(STDERR_FILENO, diagMsg, diagMsg.count)

        // Async-safe write using Darwin C functions
        // Format: simple binary with signal number (Int32) and timestamp (Int64)
        var data: [UInt8] = []

        // Add marker magic number
        let magic: UInt32 = 0xDEADBEEF
        withUnsafeBytes(of: magic) { data.append(contentsOf: $0) }

        // Add signal number
        withUnsafeBytes(of: signalNumber) { data.append(contentsOf: $0) }

        // Add timestamp (seconds since epoch)
        let timestamp = time(nil)
        withUnsafeBytes(of: timestamp) { data.append(contentsOf: $0) }

        // Open file for writing (async-safe)
        let fd = open(markerPath, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard fd >= 0 else {
            let errMsg = "❌ [CRASH_MARKER] Failed to open marker file at: \(markerPath)\n"
            _ = write(STDERR_FILENO, errMsg, errMsg.count)
            return
        }

        defer { close(fd) }

        // Write data (async-safe)
        let bytesWritten = write(fd, data, data.count)
        if bytesWritten < 0 {
            let errMsg = "❌ [CRASH_MARKER] Failed to write data to marker file\n"
            _ = write(STDERR_FILENO, errMsg, errMsg.count)
            return
        }

        let writeMsg = "✅ [CRASH_MARKER] Wrote \(bytesWritten) bytes to marker file\n"
        _ = write(STDERR_FILENO, writeMsg, writeMsg.count)

        // CRITICAL: Flush data to disk immediately (async-safe)
        // Without this, the file may not be written before process termination
        let syncResult = fsync(fd)
        if syncResult < 0 {
            let syncErrMsg = "❌ [CRASH_MARKER] fsync() failed!\n"
            _ = write(STDERR_FILENO, syncErrMsg, syncErrMsg.count)
        } else {
            let syncMsg = "✅ [CRASH_MARKER] fsync() succeeded - marker flushed to disk\n"
            _ = write(STDERR_FILENO, syncMsg, syncMsg.count)
        }
    }

    // MARK: - Read and Process Marker

    /// Read marker file and convert to CrashData
    static func readMarkerFile() -> CrashMarkerData? {
        let markerPath = getMarkerFilePath()
        let fileManager = FileManager.default

        print("🔍 [CRASH_MARKER] Checking for marker file at: \(markerPath)")

        guard fileManager.fileExists(atPath: markerPath) else {
            print("❌ [CRASH_MARKER] Marker file does NOT exist at: \(markerPath)")
            return nil
        }

        print("✅ [CRASH_MARKER] Marker file EXISTS")

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: markerPath))
            print("✅ [CRASH_MARKER] Read marker file - size: \(data.count) bytes")

            guard data.count >= 12 else {
                print("❌ [CRASH_MARKER] Marker file too small: \(data.count) bytes (need 12)")
                return nil
            }

            // Read magic number
            let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
            print("🔍 [CRASH_MARKER] Magic number: 0x\(String(format: "%08X", magic))")

            guard magic == 0xDEADBEEF else {
                print("❌ [CRASH_MARKER] Invalid magic number - expected 0xDEADBEEF, got 0x\(String(format: "%08X", magic))")
                return nil
            }

            // Read signal number
            let signal = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: 4, as: Int32.self)
            }

            // Read timestamp
            let timestamp = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: 8, as: time_t.self)
            }

            print("✅ [CRASH_MARKER] Successfully parsed marker - signal: \(signal), timestamp: \(timestamp)")
            return CrashMarkerData(signal: signal, timestamp: timestamp)
        } catch {
            print("❌ [CRASH_MARKER] Error reading marker file: \(error)")
            return nil
        }
    }

    // MARK: - Delete Marker

    /// Delete the marker file after processing
    static func deleteMarkerFile() {
        let markerPath = getMarkerFilePath()
        try? FileManager.default.removeItem(atPath: markerPath)
    }
}

// MARK: - Marker Data Structure

struct CrashMarkerData {
    let signal: Int32
    let timestamp: time_t

    func getSignalName() -> String {
        switch signal {
        case SIGABRT: return "SIGABRT"
        case SIGILL: return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE: return "SIGFPE"
        case SIGBUS: return "SIGBUS"
        case SIGPIPE: return "SIGPIPE"
        default: return "UNKNOWN(\(signal))"
        }
    }
}
