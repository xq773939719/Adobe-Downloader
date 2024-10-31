//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation
import AppKit

extension FileManager {
    func volumeAvailableCapacity(for url: URL) throws -> Int64 {
        let resourceValues = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(resourceValues.volumeAvailableCapacity ?? 0)
    }
}

extension Product.ProductVersion {
    var size: Int64 {
        return 0
    }
}

extension DownloadTask {
    var startTime: Date {
        switch status {
        case .downloading(let info):
            return info.startTime
        case .completed(let info):
            return info.timestamp.addingTimeInterval(-info.totalTime)
        case .preparing(let info):
            return info.timestamp
        case .paused(let info):
            return info.timestamp
        case .retrying(let info):
            return info.nextRetryDate.addingTimeInterval(-60)
        case .failed(let info):
            return info.timestamp
        case .waiting:
            return Date()
        }
    }
}

extension NetworkManager {
    func handleDownloadCompletion(taskId: UUID, packageIndex: Int) async {
        await MainActor.run {
            guard let taskIndex = downloadTasks.firstIndex(where: { $0.id == taskId }) else { return }

            downloadTasks[taskIndex].packages[packageIndex].downloaded = true
            downloadTasks[taskIndex].packages[packageIndex].progress = 1.0
            downloadTasks[taskIndex].packages[packageIndex].status = .completed

            if let nextPackageIndex = downloadTasks[taskIndex].packages.firstIndex(where: { !$0.downloaded }) {
                downloadTasks[taskIndex].status = .downloading(DownloadTask.DownloadStatus.DownloadInfo(
                    fileName: downloadTasks[taskIndex].packages[nextPackageIndex].name,
                    currentPackageIndex: nextPackageIndex,
                    totalPackages: downloadTasks[taskIndex].packages.count,
                    startTime: Date(),
                    estimatedTimeRemaining: nil
                ))
                Task {
                    await resumeDownload(taskId: taskId)
                }
            } else {
                let startTime = downloadTasks[taskIndex].startTime
                let totalTime = Date().timeIntervalSince(startTime)
                
                downloadTasks[taskIndex].status = .completed(DownloadTask.DownloadStatus.CompletionInfo(
                    timestamp: Date(),
                    totalTime: totalTime,
                    totalSize: downloadTasks[taskIndex].totalSize
                ))
                downloadTasks[taskIndex].progress = 1.0
                progressObservers[taskId]?.invalidate()
                progressObservers.removeValue(forKey: taskId)
                
                if activeDownloadTaskId == taskId {
                    activeDownloadTaskId = nil
                }

                updateDockBadge()
                objectWillChange.send()
                Task {
                    do {
                        try await downloadUtils.clearExtendedAttributes(at: downloadTasks[taskIndex].destinationURL)
                        print("Successfully cleared extended attributes for \(downloadTasks[taskIndex].destinationURL.path)")
                    } catch {
                        print("Failed to clear extended attributes: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

extension NetworkManager {
    func getApplicationInfo(buildGuid: String) async throws -> ApplicationInfo {
        guard let url = URL(string: NetworkConstants.applicationJsonURL) else {
            throw NetworkError.invalidURL(NetworkConstants.applicationJsonURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        var headers = NetworkConstants.adobeRequestHeaders
        headers["x-adobe-build-guid"] = buildGuid
        headers["Accept"] = "application/json"
        headers["Connection"] = "keep-alive"
        headers["Cookie"] = generateCookie()
        
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        do {
            let decoder = JSONDecoder()
            let applicationInfo: ApplicationInfo = try decoder.decode(ApplicationInfo.self, from: data)
            return applicationInfo
        } catch {
            throw NetworkError.parsingError(error, "Failed to parse application info")
        }
    }
    
    func fetchProductsData() async throws -> ([String: Product], String) {
        var components = URLComponents(string: NetworkConstants.productsXmlURL)
        components?.queryItems = [
            URLQueryItem(name: "_type", value: "xml"),
            URLQueryItem(name: "channel", value: "ccm"),
            URLQueryItem(name: "channel", value: "sti"),
            URLQueryItem(name: "platform", value: "osx10-64,osx10,macarm64,macuniversal"),
            URLQueryItem(name: "productType", value: "Desktop")
        ]
        
        guard let url = components?.url else {
            throw NetworkError.invalidURL(NetworkConstants.productsXmlURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        NetworkConstants.adobeRequestHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode, nil)
        }
        
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidData("无法解码XML数据")
        }

        let result: ([String: Product], String) = try await Task.detached(priority: .userInitiated) {
            let parseResult = try XHXMLParser.parse(
                xmlString: xmlString,
                urlVersion: 6,
                allowedPlatforms: Set(["osx10-64", "osx10", "macuniversal", "macarm64"])
            )
            return (parseResult.products, parseResult.cdn)
        }.value
        
        return result
    }
    
    func getDownloadPath(for fileName: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.title = "选择保存位置"
                panel.canCreateDirectories = true
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                
                if panel.runModal() == .OK {
                    if let baseURL = panel.url {
                        continuation.resume(returning: baseURL)
                    } else {
                        continuation.resume(throwing: NetworkError.fileSystemError("未选择保存位置", nil))
                    }
                } else {
                    continuation.resume(throwing: NetworkError.fileSystemError("用户取消了操作", nil))
                }
            }
        }
    }
    func configureNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied

                if !wasConnected && self.isConnected {
                    for task in self.downloadTasks where task.status.isPaused {
                        if case .paused(let info) = task.status, 
                           info.reason == .networkIssue {
                            await self.resumeDownload(taskId: task.id)
                        }
                    }
                } else if wasConnected && !self.isConnected {
                    for task in self.downloadTasks where task.status.isActive {
                        await self.downloadUtils.pauseDownloadTask(
                            taskId: task.id, 
                            reason: DownloadTask.DownloadStatus.PauseInfo.PauseReason.networkIssue
                        )
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    func generateCookie() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomString = String((0..<26).map { _ in letters.randomElement()! })
        return "fg=\(randomString)======"
    }
    
    func updateDockBadge() {
        let activeCount = downloadTasks.filter { $0.status.isActive }.count
        if activeCount > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(activeCount)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }
} 
