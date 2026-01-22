//
//  SDKPerformanceMetricsManager.swift
//  CrashReporter
//
//  Manages real-time performance metrics collection for crash context
//

import Foundation

// MARK: - SDK Performance Metrics Manager

class SDKPerformanceMetricsManager {
    static let shared = SDKPerformanceMetricsManager()

    private var performanceMetrics: PerformanceMetrics?
    private let queue = DispatchQueue(label: "com.crashreporter.performance-metrics", attributes: .concurrent)

    private init() {}

    // MARK: - Update Performance Metrics from JSON (called from Unity via C bridge)

    /// Update performance metrics from JSON string sent by Unity
    /// Called periodically (e.g., every frame or every 100ms) to update latest metrics
    func update(from jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ SDKPerformanceMetricsManager: Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        do {
            let decodedMetrics = try decoder.decode(PerformanceMetrics.self, from: jsonData)
            queue.async(flags: .barrier) {
                self.performanceMetrics = decodedMetrics
                print("✅ SDKPerformanceMetricsManager: Updated metrics - FPS: \(decodedMetrics.averageFps), Memory: \(decodedMetrics.memoryUsageMB)MB, CPU: \(decodedMetrics.cpuUsagePercent)%")
            }
        } catch {
            print("❌ SDKPerformanceMetricsManager: Failed to decode performance metrics JSON - \(error.localizedDescription)")
        }
    }

    // MARK: - Get Performance Metrics

    /// Get current performance metrics (snapshot at time of call)
    func getPerformanceMetrics() -> PerformanceMetrics? {
        var result: PerformanceMetrics?
        queue.sync {
            result = self.performanceMetrics
        }
        return result
    }

    // MARK: - Create Default Performance Metrics (fallback)

    /// Create default empty performance metrics structure
    func createDefaultPerformanceMetrics() -> PerformanceMetrics {
        return PerformanceMetrics(
            averageFps: 0,
            minimumFps: 0,
            maximumFps: 0,
            memoryUsageMB: 0,
            peakMemoryMB: 0,
            cpuUsagePercent: 0,
            thermalState: "nominal"
        )
    }

    // MARK: - Export to Dictionary

    /// Convert performance metrics to dictionary for persistence
    func toDict() -> [String: Any]? {
        guard let metrics = getPerformanceMetrics() else { return nil }

        return [
            "averageFps": metrics.averageFps,
            "minimumFps": metrics.minimumFps,
            "maximumFps": metrics.maximumFps,
            "memoryUsageMB": metrics.memoryUsageMB,
            "peakMemoryMB": metrics.peakMemoryMB,
            "cpuUsagePercent": metrics.cpuUsagePercent,
            "thermalState": metrics.thermalState
        ]
    }

    // MARK: - Reset (for testing)

    func reset() {
        queue.async(flags: .barrier) {
            self.performanceMetrics = nil
            print("🔄 SDKPerformanceMetricsManager: Reset performance metrics")
        }
    }
}
