//
//  SDKInfoManager.swift
//  CrashReporter
//
//  Manages ZBD SDK-specific state tracking for crash context
//

import Foundation

// MARK: - SDK Info Data Structure

struct SDKInfo: Codable {
    let sdk_version: String
    let sdk_initialized: Bool
    let sdk_initialization_time_ms: Int64
    let sdk_last_operation: String?
    let sdk_uptime_seconds: Int64
    let active_operations: [String]
    let pending_requests: Int
    let last_successful_operation: String?
    let last_successful_operation_time: String?
    let last_api_error: String?
    let api_endpoint: String?
    let configuration: SDKConfiguration?
}

struct SDKConfiguration: Codable {
    let timeout_seconds: Int
    let retry_enabled: Bool
    let auto_claim_rewards: Bool
}

// MARK: - SDK Info Manager

class SDKInfoManager {
    static let shared = SDKInfoManager()

    private var sdkInfo: SDKInfo?
    private let queue = DispatchQueue(label: "com.crashreporter.sdk-info", attributes: .concurrent)
    private let dateFormatter = ISO8601DateFormatter()

    private init() {}

    // MARK: - Update SDK Info from JSON (called from Unity via C bridge)

    /// Update SDK info from JSON string sent by Unity
    func update(from jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ SDKInfoManager: Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        do {
            let decodedInfo = try decoder.decode(SDKInfo.self, from: jsonData)
            queue.async(flags: .barrier) {
                self.sdkInfo = decodedInfo
                print("✅ SDKInfoManager: Updated SDK info - Version: \(decodedInfo.sdk_version), Operation: \(decodedInfo.sdk_last_operation ?? "none")")
            }
        } catch {
            print("❌ SDKInfoManager: Failed to decode SDK info JSON - \(error.localizedDescription)")
        }
    }

    // MARK: - Get SDK Info

    /// Get current SDK info
    func getSDKInfo() -> SDKInfo? {
        var result: SDKInfo?
        queue.sync {
            result = self.sdkInfo
        }
        return result
    }

    // MARK: - Create Default SDK Info (fallback)

    /// Create default empty SDK info structure
    func createDefaultSDKInfo() -> SDKInfo {
        return SDKInfo(
            sdk_version: "0.0.0",
            sdk_initialized: false,
            sdk_initialization_time_ms: 0,
            sdk_last_operation: nil,
            sdk_uptime_seconds: 0,
            active_operations: [],
            pending_requests: 0,
            last_successful_operation: nil,
            last_successful_operation_time: nil,
            last_api_error: nil,
            api_endpoint: nil,
            configuration: nil
        )
    }

    // MARK: - Export to Dictionary

    /// Convert SDK info to dictionary for persistence
    func toDict() -> [String: Any]? {
        guard let info = getSDKInfo() else { return nil }

        var dict: [String: Any] = [
            "sdk_version": info.sdk_version,
            "sdk_initialized": info.sdk_initialized,
            "sdk_initialization_time_ms": info.sdk_initialization_time_ms,
            "sdk_uptime_seconds": info.sdk_uptime_seconds,
            "active_operations": info.active_operations,
            "pending_requests": info.pending_requests
        ]

        if let lastOp = info.sdk_last_operation {
            dict["sdk_last_operation"] = lastOp
        }
        if let lastSuccessOp = info.last_successful_operation {
            dict["last_successful_operation"] = lastSuccessOp
        }
        if let lastSuccessTime = info.last_successful_operation_time {
            dict["last_successful_operation_time"] = lastSuccessTime
        }
        if let lastError = info.last_api_error {
            dict["last_api_error"] = lastError
        }
        if let endpoint = info.api_endpoint {
            dict["api_endpoint"] = endpoint
        }
        if let config = info.configuration {
            dict["configuration"] = [
                "timeout_seconds": config.timeout_seconds,
                "retry_enabled": config.retry_enabled,
                "auto_claim_rewards": config.auto_claim_rewards
            ]
        }

        return dict
    }

    // MARK: - Reset (for testing)

    func reset() {
        queue.async(flags: .barrier) {
            self.sdkInfo = nil
            print("🔄 SDKInfoManager: Reset SDK info")
        }
    }
}
