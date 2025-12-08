import Foundation

// MARK: - Crash Send Status

enum CrashSendStatus: String, Codable {
    case pending    // Not yet sent
    case sending    // Currently being sent
    case sent       // Successfully sent and confirmed by server
    case failed     // Failed after max retries
}

// MARK: - Crash Metadata

struct CrashMetadata: Codable {
    let crashId: String
    let createdAt: Date
    var status: CrashSendStatus
    var retryCount: Int
    var lastAttemptAt: Date?
    var lastErrorMessage: String?

    init(crashId: String) {
        self.crashId = crashId
        self.createdAt = Date()
        self.status = .pending
        self.retryCount = 0
        self.lastAttemptAt = nil
        self.lastErrorMessage = nil
    }

    // MARK: - Expiry Check

    func isExpired(expiryDays: Int = 7) -> Bool {
        let expiryDate = Date().addingTimeInterval(TimeInterval(-expiryDays * 24 * 60 * 60))
        return createdAt < expiryDate
    }

    // MARK: - Should Retry

    func shouldRetry(maxRetries: Int = 3) -> Bool {
        return status == .failed && retryCount < maxRetries
    }

    // MARK: - Update for Send Attempt

    mutating func recordSendAttempt(success: Bool, errorMessage: String? = nil) {
        lastAttemptAt = Date()
        retryCount += 1

        if success {
            status = .sent
            lastErrorMessage = nil
        } else {
            status = .failed
            lastErrorMessage = errorMessage
        }
    }
}
