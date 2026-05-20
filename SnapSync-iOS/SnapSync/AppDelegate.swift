// === AppDelegate.swift ===

import UIKit
import BackgroundTasks

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()

        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        return true
    }

    @objc private func willEnterForeground() {
        endBackgroundTask()
        ScreenshotMonitor.shared.checkForMissedScreenshots()
        WebSocketManager.shared.reconnect()
    }

    @objc private func didEnterBackground() {
        guard ScreenshotMonitor.shared.isActive else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            self?.endBackgroundTask()
        })
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard ScreenshotMonitor.shared.isActive else {
            completionHandler(.noData)
            return
        }
        ScreenshotMonitor.shared.performBackgroundCheck { hasNew in
            completionHandler(hasNew ? .newData : .noData)
        }
    }
}
