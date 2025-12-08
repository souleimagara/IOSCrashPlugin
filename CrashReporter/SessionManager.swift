//
//  SessionManager.swift
//  CrashReporter
//
//  Manages user session tracking for crash analytics
//

import Foundation
import UIKit

class SessionManager {
    static let shared = SessionManager()

    private var sessionId: String = UUID().uuidString
    private var sessionStartTime: Int64 = 0
    private var appOpenTime: Date?

    private init() {
        startNewSession()
        setupAppLifecycleListeners()
    }

    // MARK: - Session Lifecycle

    private func startNewSession() {
        sessionId = UUID().uuidString
        sessionStartTime = Int64(Date().timeIntervalSince1970 * 1000)
        appOpenTime = Date()
        print("📱 SessionManager: New session started - \(sessionId)")
    }

    private func setupAppLifecycleListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        print("📱 SessionManager: App entered background")
    }

    @objc private func appWillEnterForeground() {
        print("📱 SessionManager: App will enter foreground")
    }

    @objc private func appDidFinishLaunching() {
        print("📱 SessionManager: App did finish launching")
    }

    // MARK: - Get Session Info

    func getSessionInfo() -> SessionInfo {
        let currentTime = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionDurationMs = currentTime - sessionStartTime

        // Count breadcrumbs as events
        let eventCount = BreadcrumbManager.shared.getBreadcrumbs().count

        // Check if app is in foreground
        let isInForeground = UIApplication.shared.applicationState == .active

        return SessionInfo(
            sessionId: sessionId,
            sessionStartTime: sessionStartTime,
            sessionDurationMs: sessionDurationMs,
            isInForeground: isInForeground,
            eventsBeforeCrash: eventCount,
            appWasInBackground: UIApplication.shared.applicationState == .background
        )
    }

    // MARK: - Session Duration

    func getSessionDuration() -> TimeInterval {
        guard let openTime = appOpenTime else { return 0 }
        return Date().timeIntervalSince(openTime)
    }

    func getSessionDurationMs() -> Int64 {
        return Int64(getSessionDuration() * 1000)
    }

    // MARK: - Session ID

    func getCurrentSessionId() -> String {
        return sessionId
    }

    // MARK: - App State

    func isAppInForeground() -> Bool {
        return UIApplication.shared.applicationState == .active
    }

    func isAppInBackground() -> Bool {
        return UIApplication.shared.applicationState == .background
    }

    // MARK: - Reset Session (for testing)

    func resetSession() {
        startNewSession()
    }
}
