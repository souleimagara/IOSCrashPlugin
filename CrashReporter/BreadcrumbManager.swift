import Foundation

class BreadcrumbManager {
    static let shared = BreadcrumbManager()
    
    private let maxBreadcrumbs = 30  // Optimized from 100 to 30
    private var breadcrumbs: [Breadcrumb] = []
    private let queue = DispatchQueue(label: "com.crashreporter.breadcrumbs", attributes: .concurrent)
    
    private init() {}
    
    func addBreadcrumb(category: String, message: String, level: String = "info", data: [String: String] = [:]) {
        let breadcrumb = Breadcrumb(
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            category: category,
            message: message,
            level: level,
            data: data
        )
        
        queue.async(flags: .barrier) {
            self.breadcrumbs.append(breadcrumb)
            
            // Keep only last maxBreadcrumbs
            if self.breadcrumbs.count > self.maxBreadcrumbs {
                self.breadcrumbs.removeFirst()
            }
        }
    }
    
    func getBreadcrumbs() -> [Breadcrumb] {
        return queue.sync {
            return breadcrumbs
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.breadcrumbs.removeAll()
        }
    }
}
