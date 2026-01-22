import Foundation
import UIKit

/// Tracks system memory warnings for crash context
///
/// Listens to:
/// - UIApplication.didReceiveMemoryWarningNotification
/// - NSProcessInfo thermalStateDidChangeNotification
/// Stores last 10 warnings with timestamp, level, description
class MemoryWarningTracker {
    static let shared = MemoryWarningTracker()

    private var memoryWarnings: [MemoryWarning] = []
    private let maxWarnings = 10
    private let queue = DispatchQueue(label: "com.crashreporter.memorywarning")

    struct MemoryWarning: Codable {
        let timestamp: Int64      // Milliseconds since epoch
        let level: String         // TRIM_MEMORY_UI_HIDDEN, LOW, CRITICAL, etc.
        let description: String   // Human-readable description
    }

    // MARK: - Initialization

    init() {
        setupListeners()
    }

    private func setupListeners() {
        // Listen to memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // Listen to thermal state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: Foundation.ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Handle Memory Warning

    @objc private func handleMemoryWarning() {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let warning = MemoryWarning(
            timestamp: timestamp,
            level: "MEMORY_WARNING",
            description: "System memory warning received"
        )

        addWarning(warning)
    }

    @objc private func handleThermalStateChange() {
        let processInfo = Foundation.ProcessInfo.processInfo
        let thermalState = getThermalStateDescription(processInfo.thermalState)
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        let warning = MemoryWarning(
            timestamp: timestamp,
            level: thermalState,
            description: "Device thermal state changed to: \(thermalState)"
        )

        addWarning(warning)
    }

    // MARK: - Add Warning

    private func addWarning(_ warning: MemoryWarning) {
        queue.async {
            self.memoryWarnings.append(warning)

            // Keep only last 10 warnings
            if self.memoryWarnings.count > self.maxWarnings {
                self.memoryWarnings.removeFirst()
            }
        }
    }

    // MARK: - Get Warnings

    func getMemoryWarnings() -> [MemoryWarning] {
        var result: [MemoryWarning] = []
        queue.sync {
            result = self.memoryWarnings
        }
        return result
    }

    // MARK: - Clear Warnings

    func clearMemoryWarnings() {
        queue.async {
            self.memoryWarnings.removeAll()
        }
    }

    // MARK: - Helper Methods

    private func getThermalStateDescription(_ state: Foundation.ProcessInfo.ThermalState) -> String {
        switch state {
        case .critical:
            return "THERMAL_CRITICAL"
        case .serious:
            return "THERMAL_SERIOUS"
        case .fair:
            return "THERMAL_FAIR"
        case .nominal:
            return "THERMAL_NOMINAL"
        @unknown default:
            return "THERMAL_UNKNOWN"
        }
    }

    // MARK: - Get Current Memory Pressure

    func getCurrentMemoryPressure() -> String {
        let processInfo = Foundation.ProcessInfo.processInfo
        let availableMemory = processInfo.physicalMemory
        let activeMemory = availableMemory / 2  // Rough estimate

        if activeMemory > availableMemory * 9 / 10 {
            return "CRITICAL"
        } else if activeMemory > availableMemory * 7 / 10 {
            return "HIGH"
        } else if activeMemory > availableMemory / 2 {
            return "MODERATE"
        } else {
            return "LOW"
        }
    }
}
