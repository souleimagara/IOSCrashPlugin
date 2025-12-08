import Foundation
import UIKit

class PerformanceMetricsCollector {
    static let shared = PerformanceMetricsCollector()

    // Thread-safe lock for accessing shared data
    private let metricsLock = NSLock()

    // FPS tracking
    private var displayLink: CADisplayLink?
    private var frameCount = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var currentFps: Float = 60.0
    private var minimumFps: Float = 60.0
    private var maximumFps: Float = 60.0
    private var fpsReadings: [Float] = []

    // Memory tracking
    private var peakMemoryMB: Int64 = 0

    // CPU tracking (simplified)
    private var cpuUsagePercent: Float = 0.0

    private init() {
        setupDisplayLink()
    }

    // MARK: - Display Link Setup (for FPS tracking)

    private func setupDisplayLink() {
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateFPS)
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateFPS() {
        // Thread-safe FPS tracking (called from main thread via CADisplayLink)
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let currentTime = CACurrentMediaTime()

        if lastFrameTime == 0 {
            lastFrameTime = currentTime
            return
        }

        frameCount += 1

        let deltaTime = currentTime - lastFrameTime
        if deltaTime >= 1.0 {
            // Calculate FPS over 1-second interval
            let fps = Float(frameCount) / Float(deltaTime)
            currentFps = fps

            // Track min/max
            minimumFps = min(minimumFps, fps)
            maximumFps = max(maximumFps, fps)

            // Keep rolling average
            fpsReadings.append(fps)
            if fpsReadings.count > 60 {  // Keep last 60 readings
                fpsReadings.removeFirst()
            }

            frameCount = 0
            lastFrameTime = currentTime
        }
    }

    // MARK: - Memory Collection

    private func getCurrentMemoryMB() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size/MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        let residentSize = Int64(info.resident_size)
        let memoryMB = residentSize / (1024 * 1024)

        // Track peak memory
        peakMemoryMB = max(peakMemoryMB, memoryMB)

        return memoryMB
    }

    // MARK: - CPU Collection

    private func calculateCPUUsage() -> Float {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size/MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(
                    mach_thread_self(),
                    thread_flavor_t(THREAD_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0.0
        }

        // CPU usage is in percentage * TH_USAGE_SCALE
        let cpuUsage = Float(info.cpu_usage) / Float(TH_USAGE_SCALE) * 100.0
        return min(cpuUsage, 100.0)  // Cap at 100%
    }

    // MARK: - Thermal State

    private func getThermalState() -> String {
        if #available(iOS 11.0, *) {
            let processInfo = Foundation.ProcessInfo.processInfo
            switch processInfo.thermalState {
            case .critical:
                return "critical"
            case .serious:
                return "serious"
            case .nominal:
                return "nominal"
            case .fair:
                return "fair"
            @unknown default:
                return "unknown"
            }
        }
        return "nominal"  // Fallback for older iOS versions
    }

    // MARK: - Public API: Get Current Metrics

    func getCurrentMetrics() -> PerformanceMetrics {
        // Thread-safe access (can be called from signal handler or any thread)
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let averageFps = fpsReadings.isEmpty ? 60.0 : Float(fpsReadings.reduce(0, +)) / Float(fpsReadings.count)

        return PerformanceMetrics(
            averageFps: averageFps,
            minimumFps: minimumFps,
            maximumFps: maximumFps,
            memoryUsageMB: getCurrentMemoryMB(),
            peakMemoryMB: peakMemoryMB,
            cpuUsagePercent: calculateCPUUsage(),
            thermalState: getThermalState()
        )
    }

    // MARK: - Reset Tracking

    func resetPeakMemory() {
        // Thread-safe reset
        metricsLock.lock()
        defer { metricsLock.unlock() }
        peakMemoryMB = getCurrentMemoryMB()
    }

    func resetMetrics() {
        // Thread-safe reset
        metricsLock.lock()
        defer { metricsLock.unlock() }
        frameCount = 0
        lastFrameTime = 0
        currentFps = 60.0
        minimumFps = 60.0
        maximumFps = 60.0
        fpsReadings.removeAll()
        peakMemoryMB = getCurrentMemoryMB()
    }

    deinit {
        displayLink?.invalidate()
    }
}
