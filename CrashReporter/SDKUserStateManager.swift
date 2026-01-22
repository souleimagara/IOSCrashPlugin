//
//  SDKUserStateManager.swift
//  CrashReporter
//
//  Manages SDK user-specific state for crash context
//

import Foundation

// MARK: - SDK User State Data Structure

struct SDKUserState: Codable {
    let user_logged_in: Bool
    let user_id_hashed: String?
    let pending_operations: [String]
    let cache_status: String?
    let last_sync_time: String?
    let rewards_available: Int
    let balance_sats: Int?
    let user_status: String?
}

// MARK: - SDK User State Manager

class SDKUserStateManager {
    static let shared = SDKUserStateManager()

    private var userState: SDKUserState?
    private let queue = DispatchQueue(label: "com.crashreporter.user-state", attributes: .concurrent)

    private init() {}

    // MARK: - Update User State from JSON (called from Unity via C bridge)

    /// Update user state from JSON string sent by Unity
    func update(from jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ SDKUserStateManager: Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        do {
            let decodedState = try decoder.decode(SDKUserState.self, from: jsonData)
            queue.async(flags: .barrier) {
                self.userState = decodedState
                print("✅ SDKUserStateManager: Updated user state - Logged in: \(decodedState.user_logged_in), Pending ops: \(decodedState.pending_operations.count)")
            }
        } catch {
            print("❌ SDKUserStateManager: Failed to decode user state JSON - \(error.localizedDescription)")
        }
    }

    // MARK: - Get User State

    /// Get current user state
    func getUserState() -> SDKUserState? {
        var result: SDKUserState?
        queue.sync {
            result = self.userState
        }
        return result
    }

    // MARK: - Create Default User State (fallback)

    /// Create default empty user state structure
    func createDefaultUserState() -> SDKUserState {
        return SDKUserState(
            user_logged_in: false,
            user_id_hashed: nil,
            pending_operations: [],
            cache_status: nil,
            last_sync_time: nil,
            rewards_available: 0,
            balance_sats: nil,
            user_status: nil
        )
    }

    // MARK: - Export to Dictionary

    /// Convert user state to dictionary for persistence
    func toDict() -> [String: Any]? {
        guard let state = getUserState() else { return nil }

        var dict: [String: Any] = [
            "user_logged_in": state.user_logged_in,
            "pending_operations": state.pending_operations,
            "rewards_available": state.rewards_available
        ]

        if let userId = state.user_id_hashed {
            dict["user_id_hashed"] = userId
        }
        if let cacheStatus = state.cache_status {
            dict["cache_status"] = cacheStatus
        }
        if let lastSync = state.last_sync_time {
            dict["last_sync_time"] = lastSync
        }
        if let balance = state.balance_sats {
            dict["balance_sats"] = balance
        }
        if let status = state.user_status {
            dict["user_status"] = status
        }

        return dict
    }

    // MARK: - Reset (for testing)

    func reset() {
        queue.async(flags: .barrier) {
            self.userState = nil
            print("🔄 SDKUserStateManager: Reset user state")
        }
    }
}
