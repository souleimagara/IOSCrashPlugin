import Foundation
import CryptoKit

/// Generates and manages crash fingerprints for deduplication
///
/// Strategy:
/// - Hash first 5 stack frames with SHA256
/// - Store in UserDefaults with timestamp
/// - 24-hour TTL prevents sending duplicate crashes
/// - Prevents billing spikes from repeated identical crashes
class CrashFingerprinting {
    private static let userDefaults = UserDefaults.standard
    private static let fingerprintKeyPrefix = "crash_fingerprint_"
    private static let fingerprintTimestampSuffix = "_timestamp"
    private static let ttlSeconds: TimeInterval = 24 * 60 * 60  // 24 hours

    // MARK: - Generate Fingerprint

    /// Generate SHA256 fingerprint from stack trace (first 5 frames)
    /// - Parameter stackTrace: Full stack trace string
    /// - Returns: Hex string of SHA256 hash (first 16 chars)
    static func generateFingerprint(from stackTrace: String) -> String {
        let frames = parseStackFrames(stackTrace)
        let first5Frames = frames.prefix(5).joined(separator: "\n")

        // Hash with SHA256
        let data = first5Frames.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        let hashString = digest.map { String(format: "%02x", $0) }.joined()

        // Return first 16 characters for readable fingerprint
        return String(hashString.prefix(16))
    }

    /// Check if identical crash fingerprint exists within 24-hour window
    /// - Parameter fingerprint: Crash fingerprint to check
    /// - Returns: true if duplicate found (should skip sending), false if new crash
    static func isDuplicate(fingerprint: String) -> Bool {
        let key = fingerprintKeyPrefix + fingerprint

        guard let storedTimestamp = userDefaults.object(forKey: key) as? TimeInterval else {
            return false  // No previous crash with this fingerprint
        }

        let now = Date().timeIntervalSince1970
        let timeSincePrevious = now - storedTimestamp

        // Check if within TTL (24 hours)
        if timeSincePrevious < ttlSeconds {
            return true  // Duplicate within 24-hour window
        }

        return false  // Outside TTL, treat as new crash
    }

    /// Store fingerprint with timestamp for future deduplication checks
    /// - Parameter fingerprint: Crash fingerprint to store
    static func storeFingerprint(_ fingerprint: String) {
        let key = fingerprintKeyPrefix + fingerprint
        let timestamp = Date().timeIntervalSince1970

        userDefaults.set(timestamp, forKey: key)
        userDefaults.synchronize()
    }

    /// Clear old fingerprints outside TTL to avoid UserDefaults bloat
    static func cleanupExpiredFingerprints() {
        let now = Date().timeIntervalSince1970
        let allKeys = userDefaults.dictionaryRepresentation().keys

        for key in allKeys {
            // Only process fingerprint keys (skip other app data)
            guard key.hasPrefix(fingerprintKeyPrefix) else { continue }

            if let timestamp = userDefaults.object(forKey: key) as? TimeInterval {
                let age = now - timestamp

                // Remove if older than TTL
                if age > ttlSeconds {
                    userDefaults.removeObject(forKey: key)
                }
            }
        }

        userDefaults.synchronize()
    }

    // MARK: - Helper Methods

    /// Parse stack trace into individual frame lines
    /// - Parameter stackTrace: Full stack trace string
    /// - Returns: Array of frame strings
    private static func parseStackFrames(_ stackTrace: String) -> [String] {
        let lines = stackTrace.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.map { String($0) }
    }
}
