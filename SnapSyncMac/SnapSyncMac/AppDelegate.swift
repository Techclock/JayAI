// === AppDelegate.swift ===

import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private let server = WebSocketServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.contentTintColor = .gray
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "等待连接", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "打开截图文件夹", action: #selector(openFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(terminate), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        server.onConnectionChange = { [weak self] connected in
            DispatchQueue.main.async {
                self?.statusMenuItem.title = connected ? "已连接" : "等待连接"
                self?.statusItem.button?.contentTintColor = connected ? .systemGreen : .gray
            }
        }

        server.start()
    }

    @objc private func openFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/SnapSync")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func terminate() {
        NSApplication.shared.terminate(nil)
    }
}
