import Foundation
import UIKit

// MARK: - Main Crash Data Structure

struct CrashData: Codable {
    let crashId: String
    let timestamp: Int64
    let exceptionType: String
    let exceptionMessage: String
    let stackTrace: String
    let threadName: String
    let deviceInfo: DeviceInfo
    let appInfo: AppInfo
    let deviceState: DeviceState
    let networkInfo: NetworkInfo
    let memoryInfo: MemoryInfo
    let cpuInfo: CpuInfo
    let processInfo: ProcessInfo
    let allThreads: [ThreadInfo]
    let breadcrumbs: [Breadcrumb]
    let customData: [String: String]
    let environment: String
    let cpuRegisters: CPURegisters?
    let memoryState: MemoryState?
    let binaryImages: [BinaryImage]  // For symbolication support
    let sessionInfo: SessionInfo  // Session tracking for dashboards
    let sessionAnalytics: SessionAnalytics?  // Tier 2: Performance metrics and analytics events

    // MARK: - Crash Classification Fields (for parity with Android)
    let isANR: Bool  // Whether crash is Application Not Responding
    let isNativeCrash: Bool  // Whether crash is from native signal
    let anrDurationMs: Int?  // Duration of ANR if isANR=true
    let nativeSignal: String?  // Signal name if isNativeCrash=true (e.g., "SIGABRT (6)")
    let nativeFaultAddress: String?  // Memory address of fault if isNativeCrash=true

    // MARK: - Crash Deduplication & Grouping
    let crashFingerprint: String?  // SHA256 hash of first 5 stack frames (for dedup)
    let severity: String  // CRITICAL, HIGH, MEDIUM, LOW
    let issueTitle: String  // Human-readable title (e.g., "SIGSEGV at libunity.so")

    // MARK: - Tracking Fields
    let memoryWarnings: [MemoryWarningTracker.MemoryWarning]?  // Recent memory warnings
    let networkChanges: [NetworkReachabilityTracker.NetworkChange]?  // Recent network changes
    let isInCrashLoop: Bool  // Whether in crash loop (3+ crashes in 60s)
    let crashLoopCount: Int  // Number of crashes in current loop window

    // MARK: - SDK & Unity Context
    let sdk_info: SDKInfo?  // SDK-specific state (operations, API calls, config)
    let sdk_user_state: SDKUserState?  // SDK user-specific state (login, pending ops)
    let unity_info: UnityInfo?  // Unity engine info (version, backend, graphics)

    // MARK: - Android Parity Fields (SLO & Device Context)
    let isSDKRelated: Bool                   // Is crash related to ZBD SDK code (weak hint — see sdkConfidence)
    let sdkConfidence: String?               // Attribution confidence: high | medium | low | none
    let faultingLibrary: String?             // Native image where crash occurred (e.g. "libil2cpp.so"); nil/"" for managed
    let responsibleSDKComponent: String      // Which SDK component caused crash
    let sdkVersion: String                   // ZBD SDK version
    let crashReporterPluginVersion: String   // Crash reporter plugin version
    let platform: String                     // Platform identifier
    let initFailurePoint: String             // Where in SDK init crash occurred
    let currentOperation: String             // What SDK operation was running at crash time
    let operationContext: [String: String]   // Additional context about the operation
    let powerSaveMode: Bool                  // Is device in low power mode
    let isDebugBuild: Bool                   // Is this a debug build
    let bootTime: Int64                      // Device boot time (ms since epoch)
    let deviceUptime: Int64                  // Device uptime (ms since boot)
    let timezone: String                     // Device timezone identifier
    let isVPNActive: Bool                    // Is VPN active
    let isProxyActive: Bool                  // Is HTTP proxy active
    let memoryPressure: String               // CRITICAL, HIGH, MODERATE, LOW
    let wasNetworkRecentlyLost: Bool         // Was network lost in last 30s
    let isStartupCrash: Bool                 // Did crash occur during app startup
}

// MARK: - Device Info

struct DeviceInfo: Codable {
    let manufacturer: String // Always "Apple"
    let model: String // "iPhone 12 Pro"
    let iosVersion: String // "15.0"
    let apiLevel: String // "iOS 15.0"
    let brand: String // "Apple"
    let device: String // "iPhone13,3"
    let board: String
    let hardware: String
    let screenDensity: Float
    let screenWidth: Int
    let screenHeight: Int
    let locale: String
}

// MARK: - App Info

struct AppInfo: Codable {
    let bundleId: String
    let versionName: String
    let versionCode: String
    let targetSdkVersion: String
    let minSdkVersion: String
}

// MARK: - Device State

struct DeviceState: Codable {
    let batteryLevel: Float
    let isCharging: Bool
    let availableMemoryMB: Int64
    let totalMemoryMB: Int64
    let availableStorageMB: Int64
    let totalStorageMB: Int64
    let lowMemory: Bool
    let thermalState: String // Device thermal state (nominal, warm, critical, unknown)
    let screenOn: Bool
    let orientation: String
}

// MARK: - Network Info

struct NetworkInfo: Codable {
    let connectionType: String
    let isConnected: Bool
    let networkOperator: String
    let isRoaming: Bool
    let signalStrength: Int // Limited on iOS
}

// MARK: - Memory Info

struct MemoryInfo: Codable {
    let heapSizeKB: Int64
    let heapAllocatedKB: Int64
    let heapFreeKB: Int64
    let nativeHeapSizeKB: Int64
    let nativeHeapAllocatedKB: Int64
    let memoryClass: Int
    let largeMemoryClass: Int
}

// MARK: - CPU Info

struct CpuInfo: Codable {
    let coreCount: Int
    let architecture: String
    let cpuUsagePercent: Float
}

// MARK: - Process Info

struct ProcessInfo: Codable {
    let processId: Int
    let processName: String
    let importance: String
    let foreground: Bool
}

// MARK: - Thread Info

struct ThreadInfo: Codable {
    let id: UInt64
    let name: String
    let state: String
    let priority: Int
    let isDaemon: Bool
    let stackTrace: String
}

// MARK: - Breadcrumb

struct Breadcrumb: Codable {
    let timestamp: Int64
    let category: String
    let message: String
    let level: String
    let data: [String: String]
}

// MARK: - CPU Registers (ARM64)

struct CPURegisters: Codable {
    // General purpose registers
    let x0: UInt64?
    let x1: UInt64?
    let x2: UInt64?
    let x3: UInt64?
    let x4: UInt64?
    let x5: UInt64?
    let x6: UInt64?
    let x7: UInt64?
    let x8: UInt64?
    let x9: UInt64?
    let x10: UInt64?
    let x11: UInt64?
    let x12: UInt64?
    let x13: UInt64?
    let x14: UInt64?
    let x15: UInt64?
    let x16: UInt64?
    let x17: UInt64?
    let x18: UInt64?
    let x19: UInt64?
    let x20: UInt64?
    let x21: UInt64?
    let x22: UInt64?
    let x23: UInt64?
    let x24: UInt64?
    let x25: UInt64?
    let x26: UInt64?
    let x27: UInt64?
    let x28: UInt64?

    // Special registers
    let fp: UInt64?  // Frame pointer (x29)
    let lr: UInt64?  // Link register (x30)
    let sp: UInt64?  // Stack pointer
    let pc: UInt64?  // Program counter
    let cpsr: UInt64? // Current program status register
}

// MARK: - Memory State

struct MemoryState: Codable {
    let usedMemoryMB: Int64
    let freeMemoryMB: Int64
    let activeMemoryMB: Int64
    let inactiveMemoryMB: Int64
    let wiredMemoryMB: Int64
    let compressedMemoryMB: Int64
    let pageSize: Int
    let pageIns: Int64
    let pageOuts: Int64
}

// MARK: - Binary Image (for Symbolication)

struct BinaryImage: Codable {
    let name: String           // Library/framework name (e.g., "UIKitCore", "libsystem_c.dylib")
    let uuid: String           // UUID to match with dSYM file
    let architecture: String   // "arm64", "arm64e", etc.
    let loadAddress: String    // Hex address where image is loaded (e.g., "0x1a2b3c000")
    let maxAddress: String     // Hex address where image ends
    let path: String           // Full path to the image
}

// MARK: - Session Info (for Dashboard Analytics)

struct SessionInfo: Codable {
    let sessionId: String           // Unique session ID (UUID)
    let sessionStartTime: Int64     // When app was opened (milliseconds since epoch)
    let sessionDurationMs: Int64    // How long app was open (milliseconds)
    let isInForeground: Bool        // Was app active/foreground when crash occurred?
    let eventsBeforeCrash: Int      // Number of user actions/breadcrumbs before crash
    let appWasInBackground: Bool    // Is app currently in background?
}

// MARK: - Tier 2: Performance Metrics

struct PerformanceMetrics: Codable {
    let averageFps: Float           // Average frames per second
    let minimumFps: Float           // Minimum FPS observed
    let maximumFps: Float           // Maximum FPS observed
    let memoryUsageMB: Int64        // Current memory usage in MB
    let peakMemoryMB: Int64         // Peak memory usage in MB
    let cpuUsagePercent: Float      // Current CPU usage percentage
    let thermalState: String        // Device thermal state (critical, nominal, etc.)
}

// MARK: - Tier 2: User Analytics Event

struct AnalyticsEvent: Codable {
    let eventName: String           // Event name (e.g., "level_started", "boss_defeated")
    let timestamp: Int64            // When event occurred (milliseconds since epoch)
    let category: String            // Event category (gameplay, ui, network, etc.)
    let properties: [String: String]// Custom event properties
}

// MARK: - Tier 2: Session Analytics (for Tier 2 dashboard features)

struct SessionAnalytics: Codable {
    let performanceMetrics: PerformanceMetrics?  // Performance data at crash time
    let recentEvents: [AnalyticsEvent]           // Last N user analytics events before crash
}
