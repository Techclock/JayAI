// === WebSocketManager.swift ===

import Foundation
import Starscream

final class WebSocketManager {
    static let shared = WebSocketManager()

    private var socket: WebSocket?
    private var currentURL: String?
    var onStatusChange: ((Bool) -> Void)?
    var onScreenshotSynced: (() -> Void)?

    private init() {}

    func connect(to url: String) {
        currentURL = url
        guard let requestURL = URL(string: url) else { return }

        socket?.disconnect()
        socket = nil

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 5

        socket = WebSocket(request: request)
        socket?.onEvent = { [weak self] event in
            switch event {
            case .connected:
                self?.onStatusChange?(true)
            case .disconnected, .cancelled:
                self?.onStatusChange?(false)
                self?.scheduleReconnect()
            case .error:
                self?.onStatusChange?(false)
                self?.scheduleReconnect()
            default:
                break
            }
        }
        socket?.connect()
    }

    func disconnect() {
        currentURL = nil
        socket?.disconnect()
        socket = nil
    }

    func reconnect() {
        guard let url = currentURL else { return }
        connect(to: url)
    }

    func send(data: Data) {
        socket?.write(data: data) { [weak self] in
            self?.onScreenshotSynced?()
        }
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let url = self?.currentURL else { return }
            self?.connect(to: url)
        }
    }
}
