import Foundation

class AnalyticsEventManager {
    static let shared = AnalyticsEventManager()

    private var events: [AnalyticsEvent] = []
    private let maxEventsToKeep = 30  // CRITICAL FIX #4: Increased from 10 to 30 for better context retention
    private let queue = DispatchQueue(label: "com.crashreporter.analytics", attributes: .concurrent)

    private init() {}

    // MARK: - Record Event

    /// Record a user analytics event
    func recordEvent(
        name: String,
        category: String,
        properties: [String: String] = [:]
    ) {
        let event = AnalyticsEvent(
            eventName: name,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            category: category,
            properties: properties
        )

        queue.async(flags: .barrier) {
            self.events.append(event)

            // Keep only last N events
            if self.events.count > self.maxEventsToKeep {
                self.events.removeFirst(self.events.count - self.maxEventsToKeep)
            }
        }
    }

    // MARK: - Get Events

    /// Get all recorded events
    func getAllEvents() -> [AnalyticsEvent] {
        var result: [AnalyticsEvent] = []
        queue.sync {
            result = self.events
        }
        return result
    }

    /// Get last N events before crash
    func getRecentEvents(count: Int = 20) -> [AnalyticsEvent] {
        var result: [AnalyticsEvent] = []
        queue.sync {
            let startIndex = max(0, self.events.count - count)
            result = Array(self.events[startIndex...])
        }
        return result
    }

    /// Get events by category
    func getEventsByCategory(_ category: String) -> [AnalyticsEvent] {
        var result: [AnalyticsEvent] = []
        queue.sync {
            result = self.events.filter { $0.category == category }
        }
        return result
    }

    // MARK: - Clear Events

    /// Clear all events
    func clearAllEvents() {
        queue.async(flags: .barrier) {
            self.events.removeAll()
        }
    }

    /// Clear events older than specified time
    func clearEventsOlderThan(milliseconds: Int64) {
        let cutoffTime = Int64(Date().timeIntervalSince1970 * 1000) - milliseconds
        queue.async(flags: .barrier) {
            self.events.removeAll { $0.timestamp < cutoffTime }
        }
    }

    // MARK: - Event Counters

    /// Get count of events by category
    func getEventCountByCategory(_ category: String) -> Int {
        var count = 0
        queue.sync {
            count = self.events.filter { $0.category == category }.count
        }
        return count
    }

    /// Get total event count
    func getTotalEventCount() -> Int {
        var count = 0
        queue.sync {
            count = self.events.count
        }
        return count
    }

    // MARK: - Common Event Recording Methods

    /// Log a user interaction
    func logUserInteraction(_ description: String, properties: [String: String] = [:]) {
        var mergedProperties = properties
        mergedProperties["description"] = description
        recordEvent(name: "user_interaction", category: "ui", properties: mergedProperties)
    }

    /// Log a network request
    func logNetworkEvent(_ endpoint: String, success: Bool, statusCode: Int? = nil) {
        var properties: [String: String] = [
            "endpoint": endpoint,
            "success": String(success)
        ]
        if let statusCode = statusCode {
            properties["status_code"] = String(statusCode)
        }
        recordEvent(name: "network_request", category: "network", properties: properties)
    }

    /// Log a gameplay event
    func logGameplayEvent(_ eventName: String, properties: [String: String] = [:]) {
        recordEvent(name: eventName, category: "gameplay", properties: properties)
    }

    /// Log a screen navigation
    func logScreenNavigation(_ screenName: String) {
        recordEvent(name: "screen_view", category: "navigation", properties: ["screen": screenName])
    }

    /// Log an error
    func logErrorEvent(_ errorDescription: String, errorCode: String? = nil) {
        var properties: [String: String] = ["description": errorDescription]
        if let errorCode = errorCode {
            properties["error_code"] = errorCode
        }
        recordEvent(name: "error", category: "error", properties: properties)
    }

    /// Log a custom event
    func logCustomEvent(_ eventName: String, category: String, properties: [String: String] = [:]) {
        recordEvent(name: eventName, category: category, properties: properties)
    }
}
