// === BonjourBrowser.swift ===

import Foundation
import Network

final class BonjourBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var resolvingService: NetService?
    private var isBrowsing = false

    private var nwBrowser: NWBrowser?
    private var resolvedEndpoints = Set<String>()

    private var fallbackTimer: DispatchWorkItem?
    private var isScanning = false

    private static let fixedPort: UInt16 = 9527

    var onStatusChange: ((String) -> Void)?

    func startBrowsing() {
        guard !isBrowsing else { return }
        isBrowsing = true
        resolvingService = nil
        isScanning = false

        browser.delegate = self
        browser.searchForServices(ofType: "_snapsync._tcp.", inDomain: "local.")
        onStatusChange?("搜索Mac中(Wi-Fi+USB)...")

        let nwParams = NWParameters()
        nwParams.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_snapsync._tcp.", domain: "local.")
        nwBrowser = NWBrowser(for: descriptor, using: nwParams)
        nwBrowser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                self?.resolveNWEndpoint(result.endpoint)
            }
        }
        nwBrowser?.start(queue: .main)

        scheduleFallback()
    }

    func stopBrowsing() {
        isBrowsing = false
        isScanning = false
        fallbackTimer?.cancel()
        fallbackTimer = nil
        browser.stop()
        resolvingService?.stop()
        resolvingService = nil
        nwBrowser?.cancel()
        nwBrowser = nil
        resolvedEndpoints.removeAll()
    }

    // MARK: - Fallback: Subnet Scan

    private func scheduleFallback() {
        fallbackTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startSubnetScan()
        }
        fallbackTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func startSubnetScan() {
        guard isBrowsing, !isScanning else { return }
        isScanning = true
        onStatusChange?("热点模式，扫描局域网...")

        let hotspotIPs = (2...14).map { "172.20.10.\($0)" }
        scanNext(ips: hotspotIPs, index: 0) { [weak self] found in
            if !found {
                self?.onStatusChange?("扫描完成，未找到Mac")
            }
        }
    }

    private func scanNext(ips: [String], index: Int, completion: @escaping (Bool) -> Void) {
        guard isBrowsing, isScanning, index < ips.count else {
            completion(false)
            return
        }

        let ip = ips[index]
        let host = NWEndpoint.Host(ip)
        let connection = NWConnection(host: host, port: NWEndpoint.Port(rawValue: Self.fixedPort)!, using: .tcp)

        var done = false
        connection.stateUpdateHandler = { [weak self] state in
            guard !done else { return }
            switch state {
            case .ready:
                done = true
                connection.cancel()
                DispatchQueue.main.async {
                    guard self?.isBrowsing == true else { return }
                    let url = "ws://\(ip):\(Self.fixedPort)/snap-sync"
                    self?.onStatusChange?("热点: 发现Mac \(ip)")
                    self?.isScanning = false
                    WebSocketManager.shared.connect(to: url)
                    completion(true)
                }
            case .failed, .cancelled:
                done = true
                connection.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.scanNext(ips: ips, index: index + 1, completion: completion)
                }
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    // MARK: - Wi-Fi / Bonjour (NetServiceBrowser)

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        fallbackTimer?.cancel()
        guard resolvingService == nil else { return }
        onStatusChange?("发现Mac，解析中...")
        let ns = NetService(domain: service.domain, type: service.type, name: service.name)
        ns.delegate = self
        ns.resolve(withTimeout: 5)
        resolvingService = ns
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        onStatusChange?("Wi-Fi搜索失败")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        resolvingService = nil
        isScanning = false
        let host = resolveHost(from: sender)
        guard let host else {
            onStatusChange?("无法解析Mac地址")
            return
        }
        let port = sender.port
        let url = "ws://\(host):\(port)/snap-sync"
        onStatusChange?("正在连接 \(host)...")
        WebSocketManager.shared.connect(to: url)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingService = nil
        onStatusChange?("解析失败，重试中...")
    }

    // MARK: - USB / Peer-to-Peer (NWBrowser)

    private func resolveNWEndpoint(_ endpoint: NWEndpoint) {
        let key = "\(endpoint)"
        guard !resolvedEndpoints.contains(key) else { return }
        resolvedEndpoints.insert(key)
        fallbackTimer?.cancel()

        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let remote = connection.currentPath?.remoteEndpoint {
                    let host = self?.hostFromEndpoint(remote)
                    let port = self?.portFromEndpoint(remote)
                    if let host, let port {
                        let url = "ws://\(host):\(port)/snap-sync"
                        DispatchQueue.main.async {
                            self?.isScanning = false
                            self?.onStatusChange?("USB: 正在连接 \(host)...")
                            WebSocketManager.shared.connect(to: url)
                        }
                    }
                }
                connection.cancel()
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    private func hostFromEndpoint(_ endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr): return addr.debugDescription
            case .ipv6(let addr): return addr.debugDescription
            case .name(let name, _): return name
            @unknown default: return nil
            }
        default:
            return nil
        }
    }

    private func portFromEndpoint(_ endpoint: NWEndpoint) -> UInt16? {
        switch endpoint {
        case .hostPort(_, let port): return port.rawValue
        default: return nil
        }
    }

    // MARK: - Helpers

    private func resolveHost(from service: NetService) -> String? {
        if let hostName = service.hostName, !hostName.isEmpty {
            return hostName
        }
        guard let addresses = service.addresses else { return nil }
        for data in addresses {
            let family = data.withUnsafeBytes { $0.load(as: sockaddr.self).sa_family }
            if family == sa_family_t(AF_INET) {
                var addr4 = data.withUnsafeBytes { $0.load(as: sockaddr_in.self) }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sin = addr4.sin_addr
                inet_ntop(AF_INET, &sin, &buf, socklen_t(buf.count))
                return String(cString: buf)
            }
        }
        return nil
    }
}
