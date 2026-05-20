// === ViewController.swift ===

import UIKit

final class ViewController: UIViewController {
    private let toggleSwitch = UISwitch()
    private let statusLabel = UILabel()
    private let countLabel = UILabel()
    private let debugLabel = UILabel()

    private let bonjourBrowser = BonjourBrowser()
    private let screenshotMonitor = ScreenshotMonitor.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        toggleSwitch.isOn = false
        toggleSwitch.transform = CGAffineTransform(scaleX: 1.8, y: 1.8)
        toggleSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)

        statusLabel.text = "未连接"
        statusLabel.font = .systemFont(ofSize: 16)
        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel

        countLabel.text = "今日同步: 0"
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textAlignment = .center
        countLabel.textColor = .tertiaryLabel

        debugLabel.text = ""
        debugLabel.font = .systemFont(ofSize: 11)
        debugLabel.textAlignment = .center
        debugLabel.textColor = .systemGray
        debugLabel.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [toggleSwitch, statusLabel, countLabel, debugLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        WebSocketManager.shared.onStatusChange = { [weak self] connected in
            DispatchQueue.main.async {
                self?.statusLabel.text = connected ? "已连接到Mac" : "连接断开"
                self?.debugLabel.text = connected ? "" : self?.debugLabel.text
            }
        }

        bonjourBrowser.onStatusChange = { [weak self] msg in
            DispatchQueue.main.async {
                self?.debugLabel.text = msg
            }
        }

        screenshotMonitor.onCountChange = { [weak self] count in
            DispatchQueue.main.async {
                self?.countLabel.text = "今日同步: \(count)"
            }
        }
    }

    @objc private func switchChanged() {
        if toggleSwitch.isOn {
            bonjourBrowser.startBrowsing()
            screenshotMonitor.start()
        } else {
            bonjourBrowser.stopBrowsing()
            screenshotMonitor.stop()
            WebSocketManager.shared.disconnect()
            statusLabel.text = "未连接"
            debugLabel.text = ""
        }
    }
}
