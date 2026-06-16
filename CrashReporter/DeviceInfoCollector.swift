import Foundation
import UIKit
import SystemConfiguration
import CFNetwork
import Darwin

class DeviceInfoCollector {
    
    // MARK: - Device Info
    
    func getDeviceInfo() -> DeviceInfo {
        let screenScale = UIScreen.main.scale
        let screenBounds = UIScreen.main.bounds
        
        return DeviceInfo(
            manufacturer: "Apple",
            model: getDeviceModel(),
            iosVersion: UIDevice.current.systemVersion,
            apiLevel: "iOS \(UIDevice.current.systemVersion)",
            brand: "Apple",
            device: getDeviceIdentifier(),
            board: getDeviceIdentifier(),
            hardware: getHardwareString(),
            screenDensity: Float(screenScale),
            screenWidth: Int(screenBounds.width * screenScale),
            screenHeight: Int(screenBounds.height * screenScale),
            locale: Locale.current.identifier
        )
    }
    
    // MARK: - App Info

    func getAppInfo() -> AppInfo {
        let bundle = Bundle.main
        let infoDictionary = bundle.infoDictionary ?? [:]

        let versionName = infoDictionary["CFBundleShortVersionString"] as? String ?? "1.0"
        let versionCode = infoDictionary["CFBundleVersion"] as? String ?? "1"
        let bundleId = bundle.bundleIdentifier ?? "unknown"

        return AppInfo(
            bundleId: bundleId,
            versionName: versionName,
            versionCode: versionCode,
            targetSdkVersion: UIDevice.current.systemVersion,
            minSdkVersion: getMinimumOSVersion()
        )
    }
    
    // MARK: - Device State

    func getDeviceState() -> DeviceState {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState

        let memoryInfo = getMemoryTuple()
        let storageInfo = getStorageInfo()

        return DeviceState(
            batteryLevel: batteryLevel >= 0 ? batteryLevel : 0,
            isCharging: batteryState == .charging || batteryState == .full,
            availableMemoryMB: memoryInfo.available,
            totalMemoryMB: memoryInfo.total,
            availableStorageMB: storageInfo.available,
            totalStorageMB: storageInfo.total,
            lowMemory: memoryInfo.available < 100,
            thermalState: getThermalState(),
            screenOn: UIApplication.shared.applicationState == .active,
            orientation: getOrientation()
        )
    }
    
    // MARK: - Network Info
    
    func getNetworkInfo() -> NetworkInfo {
        let reachability = SCNetworkReachabilityCreateWithName(nil, "www.apple.com")
        var flags = SCNetworkReachabilityFlags()
        var isConnected = false
        var connectionType = "none"
        
        if let reachability = reachability,
           SCNetworkReachabilityGetFlags(reachability, &flags) {
            isConnected = flags.contains(.reachable)
            
            if flags.contains(.isWWAN) {
                connectionType = "cellular"
            } else if flags.contains(.reachable) {
                connectionType = "wifi"
            }
        }
        
        return NetworkInfo(
            connectionType: connectionType,
            isConnected: isConnected,
            networkOperator: getCarrierName(),
            isRoaming: false, // Difficult to detect on iOS
            signalStrength: -1 // Not available without private APIs
        )
    }
    
    // MARK: - Memory Info
    
    func getMemoryInfo() -> MemoryInfo {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        var usedMemory: Int64 = 0
        if kerr == KERN_SUCCESS {
            usedMemory = Int64(info.resident_size / 1024) // Convert to KB
        }
        
        let totalMemory = Foundation.ProcessInfo.processInfo.physicalMemory / 1024 // KB
        
        return MemoryInfo(
            heapSizeKB: Int64(totalMemory),
            heapAllocatedKB: usedMemory,
            heapFreeKB: Int64(totalMemory) - usedMemory,
            nativeHeapSizeKB: usedMemory,
            nativeHeapAllocatedKB: usedMemory,
            memoryClass: Int(totalMemory / 1024), // MB
            largeMemoryClass: Int(totalMemory / 1024)
        )
    }
    
    // MARK: - CPU Info
    
    func getCpuInfo() -> CpuInfo {
        let coreCount = Foundation.ProcessInfo.processInfo.processorCount
        let architecture = getArchitecture()
        let cpuUsage = getCPUUsage()
        
        return CpuInfo(
            coreCount: coreCount,
            architecture: architecture,
            cpuUsagePercent: cpuUsage
        )
    }
    
    // MARK: - Process Info
    
    func getProcessInfo() -> ProcessInfo {
        let processId = Int(Foundation.ProcessInfo.processInfo.processIdentifier)
        let processName = Foundation.ProcessInfo.processInfo.processName
        let isForeground = UIApplication.shared.applicationState == .active
        
        return ProcessInfo(
            processId: processId,
            processName: processName,
            importance: isForeground ? "foreground" : "background",
            foreground: isForeground
        )
    }
    
    // MARK: - Helper Methods
    
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapToDeviceName(identifier: identifier)
    }
    
    private func getDeviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
    
    private func getHardwareString() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }
    
    private func mapToDeviceName(identifier: String) -> String {
        switch identifier {
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        case "iPhone14,4": return "iPhone 13 Mini"
        case "iPhone14,5": return "iPhone 13"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone15,4": return "iPhone 14"
        case "iPhone15,5": return "iPhone 14 Plus"
        case "i386", "x86_64", "arm64": return "Simulator"
        default: return identifier
        }
    }
    
    private func getMinimumOSVersion() -> String {
        if let minVersion = Bundle.main.infoDictionary?["MinimumOSVersion"] as? String {
            return minVersion
        }
        return UIDevice.current.systemVersion
    }
    
    private func getOrientation() -> String {
        switch UIDevice.current.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        default: return "unknown"
        }
    }

    private func getMemoryTuple() -> (available: Int64, total: Int64) {
        let totalMemory = Int64(Foundation.ProcessInfo.processInfo.physicalMemory / (1024 * 1024)) // MB
        
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        var usedMemory: Int64 = 0
        if kerr == KERN_SUCCESS {
            usedMemory = Int64(info.resident_size / (1024 * 1024)) // MB
        }
        
        let availableMemory = totalMemory - usedMemory
        return (available: availableMemory, total: totalMemory)
    }
    
    private func getStorageInfo() -> (available: Int64, total: Int64) {
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            
            let totalSpace = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
            let freeSpace = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            
            let totalMB = totalSpace / (1024 * 1024)
            let freeMB = freeSpace / (1024 * 1024)
            
            return (available: freeMB, total: totalMB)
        } catch {
            return (available: 0, total: 0)
        }
    }
    
    private func getCarrierName() -> String {
        return "Unknown" // Requires CoreTelephony framework
    }
    
    private func getArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        if identifier.contains("arm64") {
            return "arm64"
        } else if identifier.contains("x86_64") {
            return "x86_64"
        }
        return identifier
    }
    
    // MARK: - Android Parity Collection Methods

    func getThermalState() -> String {
        switch Foundation.ProcessInfo.processInfo.thermalState {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    func isPowerSaveMode() -> Bool {
        return Foundation.ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    func isDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func getBootTime() -> Int64 {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        sysctlbyname("kern.boottime", &tv, &size, nil, 0)
        return Int64(tv.tv_sec) * 1000 + Int64(tv.tv_usec) / 1000
    }

    func getDeviceUptime() -> Int64 {
        return Int64(Foundation.ProcessInfo.processInfo.systemUptime * 1000)
    }

    func getTimezone() -> String {
        return TimeZone.current.identifier
    }

    func isVPNActive() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return false }
        defer { freeifaddrs(ifaddr) }
        var current = ifaddr
        while let addr = current {
            let name = String(cString: addr.pointee.ifa_name)
            if name.hasPrefix("utun") { return true }
            current = addr.pointee.ifa_next
        }
        return false
    }

    func isProxyActive() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }
        let httpEnabled = settings[kCFNetworkProxiesHTTPEnable as String] as? Int
        let httpProxy = settings[kCFNetworkProxiesHTTPProxy as String] as? String
        return (httpEnabled == 1) || !(httpProxy?.isEmpty ?? true)
    }

    func getMemoryPressure() -> String {
        let total = Foundation.ProcessInfo.processInfo.physicalMemory
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                _ = task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let used = Int64(info.resident_size)
        let available = Int64(total) - used
        let percentAvailable = Double(available) / Double(total) * 100
        switch percentAvailable {
        case ..<10: return "CRITICAL"
        case ..<20: return "HIGH"
        case ..<40: return "MODERATE"
        default:    return "LOW"
        }
    }

    private func getCPUUsage() -> Float {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else {
                    break
                }
                
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                }
            }
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        return Float(totalUsageOfCPU)
    }
}
