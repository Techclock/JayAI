// === WebSocketServer.swift ===

import Network
import UserNotifications

final class WebSocketServer {
    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "snapsync.server", qos: .utility)
    var onConnectionChange: ((Bool) -> Void)?
    var onReady: ((UInt16) -> Void)?

    func start() {
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        listener = try? NWListener(using: parameters, on: 9527)

        let name = "SnapSync-Mac-\(Host.current().localizedName ?? "Unknown")"
        listener?.service = NWListener.Service(name: name, type: "_snapsync._tcp.")
        listener?.serviceRegistrationUpdateHandler = { change in
            switch change {
            case .add(let endpoint):
                let msg = "Bonjour advertised: \(endpoint)"
                print(msg)
                try? msg.write(toFile: "/tmp/snapsync-bonjour.log", atomically: true, encoding: .utf8)
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue, port > 0 {
                    let msg = "WebSocket server ready on port \(port)"
                    print(msg)
                    try? msg.write(toFile: "/tmp/snapsync-server.log", atomically: true, encoding: .utf8)
                    self?.onReady?(port)
                }
            case .failed(let error):
                let msg = "Listener failed: \(error)"
                print(msg)
                try? msg.write(toFile: "/tmp/snapsync-server.log", atomically: true, encoding: .utf8)
            default:
                break
            }
        }

        listener?.start(queue: queue)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.activeConnections.append(connection)
                self?.onConnectionChange?(true)
            case .failed, .cancelled:
                self?.activeConnections.removeAll { $0 === connection }
                self?.onConnectionChange?(!(self?.activeConnections.isEmpty ?? true))
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveMessage(from: connection)
    }

    private func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data {
                self?.saveScreenshot(data)
            }
            if error == nil, let self = self {
                self.receiveMessage(from: connection)
            }
        }
    }

    private func saveScreenshot(_ data: Data) {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/SnapSync")
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmssSSS"
        let filename = "screenshot-\(formatter.string(from: Date())).png"
        let fileURL = downloads.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            sendNotification(filename: filename)
        } catch {
            print("Failed to save screenshot: \(error)")
        }
    }

    private func sendNotification(filename: String) {
        let content = UNMutableNotificationContent()
        content.title = "截图已保存"
        content.body = filename
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
