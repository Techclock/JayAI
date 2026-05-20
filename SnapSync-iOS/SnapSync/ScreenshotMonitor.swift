// === ScreenshotMonitor.swift ===

import Photos
import UIKit

final class ScreenshotMonitor: NSObject, @preconcurrency PHPhotoLibraryChangeObserver {
    static let shared = ScreenshotMonitor()

    private var isMonitoring = false
    private var todayCount = 0
    private var lastCountDate: String?
    private var screenSize: CGSize = .zero
    private var syncedAssetIDs = Set<String>()
    var onCountChange: ((Int) -> Void)?
    var isActive: Bool { isMonitoring }

    private override init() {
        super.init()
        loadCount()
    }

    func start() {
        guard !isMonitoring else { return }
        screenSize = UIScreen.main.nativeBounds.size
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            registerObserver()
        } else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                guard let self else { return }
                if newStatus == .authorized || newStatus == .limited {
                    self.registerObserver()
                } else {
                    print("Photo library access denied")
                }
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )
        WebSocketManager.shared.onScreenshotSynced = { [weak self] in
            self?.incrementCount()
        }
    }

    func stop() {
        WebSocketManager.shared.onScreenshotSynced = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        guard isMonitoring else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        isMonitoring = false
    }

    private func registerObserver() {
        PHPhotoLibrary.shared().register(self)
        isMonitoring = true
    }

    func checkForMissedScreenshots() {
        guard isMonitoring else { return }
        processLatestPhoto()
    }

    func performBackgroundCheck(completion: @escaping (Bool) -> Void) {
        guard isMonitoring else {
            completion(false)
            return
        }
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = assets.firstObject,
              let creationDate = asset.creationDate,
              Date().timeIntervalSince(creationDate) < 15,
              asset.pixelWidth == Int(screenSize.width),
              asset.pixelHeight == Int(screenSize.height)
        else {
            completion(false)
            return
        }

        guard !syncedAssetIDs.contains(asset.localIdentifier) else {
            completion(false)
            return
        }

        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isSynchronous = true

        var synced = false
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: requestOptions) { [weak self] data, _, _, _ in
            if let data = data {
                self?.syncedAssetIDs.insert(asset.localIdentifier)
                WebSocketManager.shared.send(data: data)
                synced = true
            }
        }
        completion(synced)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard isMonitoring else { return }
        processLatestPhoto()
    }

    @objc private func didTakeScreenshot() {
        processLatestPhoto()
    }

    private func processLatestPhoto() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let asset = assets.firstObject else { return }

        guard !syncedAssetIDs.contains(asset.localIdentifier) else { return }

        guard let creationDate = asset.creationDate, Date().timeIntervalSince(creationDate) < 5 else { return }

        guard asset.pixelWidth == Int(screenSize.width) && asset.pixelHeight == Int(screenSize.height) else { return }

        syncedAssetIDs.insert(asset.localIdentifier)

        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: requestOptions) { [weak self] data, _, _, _ in
            guard let data = data else { return }
            WebSocketManager.shared.send(data: data)
        }
    }

    private func incrementCount() {
        let today = dateKey()
        if lastCountDate != today {
            lastCountDate = today
            todayCount = 0
        }
        todayCount += 1
        saveCount()
        onCountChange?(todayCount)
    }

    private func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private func saveCount() {
        UserDefaults.standard.set(todayCount, forKey: "snapSync_todayCount")
        UserDefaults.standard.set(lastCountDate, forKey: "snapSync_lastDate")
    }

    private func loadCount() {
        let today = dateKey()
        let savedDate = UserDefaults.standard.string(forKey: "snapSync_lastDate")
        if savedDate == today {
            todayCount = UserDefaults.standard.integer(forKey: "snapSync_todayCount")
        } else {
            todayCount = 0
        }
        lastCountDate = today
    }
}
