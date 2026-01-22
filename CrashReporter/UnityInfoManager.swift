//
//  UnityInfoManager.swift
//  CrashReporter
//
//  Manages Unity engine-specific information for crash context
//

import Foundation

// MARK: - Unity Info Data Structure

struct UnityInfo: Codable {
    let unity_version: String
    let scripting_backend: String
    let graphics_api: String
    let rendering_path: String?
    let quality_level: String?
    let vsync_count: Int?
    let target_framerate: Int?
    let platform: String
}

// MARK: - Unity Info Manager

class UnityInfoManager {
    static let shared = UnityInfoManager()

    private var unityInfo: UnityInfo?
    private let queue = DispatchQueue(label: "com.crashreporter.unity-info", attributes: .concurrent)

    private init() {}

    // MARK: - Update Unity Info from JSON (called from Unity via C bridge)

    /// Update Unity info from JSON string sent by Unity
    func update(from jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ UnityInfoManager: Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        do {
            let decodedInfo = try decoder.decode(UnityInfo.self, from: jsonData)
            queue.async(flags: .barrier) {
                self.unityInfo = decodedInfo
                print("✅ UnityInfoManager: Updated Unity info - Version: \(decodedInfo.unity_version), Backend: \(decodedInfo.scripting_backend), Graphics: \(decodedInfo.graphics_api)")
            }
        } catch {
            print("❌ UnityInfoManager: Failed to decode Unity info JSON - \(error.localizedDescription)")
        }
    }

    // MARK: - Get Unity Info

    /// Get current Unity info
    func getUnityInfo() -> UnityInfo? {
        var result: UnityInfo?
        queue.sync {
            result = self.unityInfo
        }
        return result
    }

    // MARK: - Create Default Unity Info (fallback)

    /// Create default empty Unity info structure
    func createDefaultUnityInfo() -> UnityInfo {
        return UnityInfo(
            unity_version: "Unknown",
            scripting_backend: "Unknown",
            graphics_api: "Unknown",
            rendering_path: nil,
            quality_level: nil,
            vsync_count: nil,
            target_framerate: nil,
            platform: "iOS"
        )
    }

    // MARK: - Export to Dictionary

    /// Convert Unity info to dictionary for persistence
    func toDict() -> [String: Any]? {
        guard let info = getUnityInfo() else { return nil }

        var dict: [String: Any] = [
            "unity_version": info.unity_version,
            "scripting_backend": info.scripting_backend,
            "graphics_api": info.graphics_api,
            "platform": info.platform
        ]

        if let renderingPath = info.rendering_path {
            dict["rendering_path"] = renderingPath
        }
        if let qualityLevel = info.quality_level {
            dict["quality_level"] = qualityLevel
        }
        if let vsync = info.vsync_count {
            dict["vsync_count"] = vsync
        }
        if let framerate = info.target_framerate {
            dict["target_framerate"] = framerate
        }

        return dict
    }

    // MARK: - Reset (for testing)

    func reset() {
        queue.async(flags: .barrier) {
            self.unityInfo = nil
            print("🔄 UnityInfoManager: Reset Unity info")
        }
    }
}
