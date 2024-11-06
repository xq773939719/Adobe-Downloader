import Foundation
import Network
import Combine
import AppKit
import SwiftUI

@MainActor
class NetworkManager: ObservableObject {
    typealias ProgressUpdate = (bytesWritten: Int64, totalWritten: Int64, expectedToWrite: Int64)
    @Published var isConnected = false
    @Published var saps: [String: Sap] = [:]
    @Published var cdn: String = ""
    @Published var allowedPlatform: [String]
    @Published var sapCodes: [SapCodes] = []
    @Published var loadingState: LoadingState = .idle
    @Published var downloadTasks: [NewDownloadTask] = []
    @Published var installationState: InstallationState = .idle
    @Published var installationLogs: [String] = []
    private let cancelTracker = CancelTracker()
    internal var downloadUtils: DownloadUtils!
    internal var progressObservers: [UUID: NSKeyValueObservation] = [:]
    internal var activeDownloadTaskId: UUID?
    internal var monitor = NWPathMonitor()
    internal var isFetchingProducts = false
    private let installManager = InstallManager()
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    
    enum InstallationState {
        case idle
        case installing(progress: Double, status: String)
        case completed
        case failed(Error)
    }

    init() {
        let useAppleSilicon = UserDefaults.standard.bool(forKey: "downloadAppleSilicon")
        self.allowedPlatform = useAppleSilicon ? ["macuniversal", "macarm64"] : ["macuniversal", "osx10-64"]
        
        self.downloadUtils = DownloadUtils(networkManager: self, cancelTracker: cancelTracker)
        setupNetworkMonitoring()
    }

    func fetchProducts() async {
        await fetchProductsWithRetry()
    }
    func startDownload(sap: Sap, selectedVersion: String, language: String, destinationURL: URL) async throws {
        guard let productInfo = self.saps[sap.sapCode]?.versions[selectedVersion] else { 
            throw NetworkError.invalidData("无法获取产品信息") 
        }
        
        let task = NewDownloadTask(
            sapCode: sap.sapCode,
            version: selectedVersion,
            language: language,
            displayName: sap.displayName,
            directory: destinationURL,
            productsToDownload: [],
            createAt: Date(),
            totalStatus: .preparing(DownloadStatus.PrepareInfo(message: "正在准备下载...", timestamp: Date(), stage: .initializing)),
            totalProgress: 0,
            totalDownloadedSize: 0,
            totalSize: 0,
            totalSpeed: 0
        )
        
        downloadTasks.append(task)
        updateDockBadge()
        
        do {
            try await downloadUtils.handleDownload(task: task, productInfo: productInfo, allowedPlatform: allowedPlatform, saps: saps)
        } catch {
            await MainActor.run {
                task.setStatus(.failed(DownloadStatus.FailureInfo(
                    message: error.localizedDescription,
                    error: error,
                    timestamp: Date(),
                    recoverable: true
                )))
                objectWillChange.send()
            }
            throw error
        }
    }

    var cdnUrl: String {
        get async {
            await MainActor.run { cdn }
        }
    }

   func removeTask(taskId: UUID, removeFiles: Bool = true) {
       Task {
           await cancelTracker.cancel(taskId)
           
           if let task = downloadTasks.first(where: { $0.id == taskId }) {
               if removeFiles {
                   try? FileManager.default.removeItem(at: task.directory)
               }
               
               await MainActor.run {
                   downloadTasks.removeAll { $0.id == taskId }
                   updateDockBadge()
                   objectWillChange.send()
               }
           }
       }
   }

    private func fetchProductsWithRetry() async {
        guard !isFetchingProducts else { return }
        
        isFetchingProducts = true
        loadingState = .loading
        
        let maxRetries = 3
        var retryCount = 0
        
        while retryCount < maxRetries {
            do {
                let (saps, cdn, sapCodes) = try await fetchProductsData()

                await MainActor.run {
                    self.saps = saps
                    self.cdn = cdn
                    self.sapCodes = sapCodes
                    self.loadingState = .success
                    self.isFetchingProducts = false
                }
                return
            } catch {
                retryCount += 1
                if retryCount == maxRetries {
                    await MainActor.run {
                        self.loadingState = .failed(error)
                        self.isFetchingProducts = false
                    }
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000)
                }
            }
        }
    }

   private func clearCompletedDownloadTasks() async {
       await MainActor.run {
           downloadTasks.removeAll { task in
               if task.status.isCompleted || task.status.isFailed {
                   try? FileManager.default.removeItem(at: task.directory)
                   return true
               }
               return false
           }
           updateDockBadge()
           objectWillChange.send()
       }
   }

    func installProduct(at path: URL) async {
        await MainActor.run {
            installationState = .installing(progress: 0, status: "准备安装...")
            installationLogs.removeAll()
        }
        
        do {
            try await installManager.install(
                at: path,
                progressHandler: { progress, status in
                    Task { @MainActor in
                        if status.contains("完成") || status.contains("成功") {
                            self.installationState = .completed
                        } else {
                            self.installationState = .installing(progress: progress, status: status)
                        }
                    }
                },
                logHandler: { log in
                    Task { @MainActor in
                        self.installationLogs.append(log)
                    }
                }
            )
            
            await MainActor.run {
                installationState = .completed
            }
        } catch {
            await MainActor.run {
                if let installError = error as? InstallManager.InstallError {
                    switch installError {
                    case .installationFailed(let message):
                        if message.contains("需要重新输入密码") {
                            Task {
                                await installProduct(at: path)
                            }
                        } else {
                            installationState = .failed(InstallManager.InstallError.installationFailed(message))
                        }
                    case .cancelled:
                        installationState = .failed(InstallManager.InstallError.cancelled)
                    case .setupNotFound:
                        installationState = .failed(InstallManager.InstallError.setupNotFound)
                    case .permissionDenied:
                        installationState = .failed(InstallManager.InstallError.permissionDenied)
                    }
                } else {
                    installationState = .failed(InstallManager.InstallError.installationFailed(error.localizedDescription))
                }
            }
        }
    }

    func cancelInstallation() {
        Task {
            await installManager.cancel()
        }
    }

    func retryInstallation(at path: URL) async {
        await MainActor.run {
            installationState = .installing(progress: 0, status: "正在重试安装...")
        }
        
        do {
            try await installManager.retry(
                at: path,
                progressHandler: { progress, status in
                    Task { @MainActor in
                        if status.contains("完成") || status.contains("成功") {
                            self.installationState = .completed
                        } else {
                            self.installationState = .installing(progress: progress, status: status)
                        }
                    }
                },
                logHandler: { log in
                    Task { @MainActor in
                        self.installationLogs.append(log)
                    }
                }
            )
            
            await MainActor.run {
                installationState = .completed
            }
        } catch {
            if case InstallManager.InstallError.installationFailed(let message) = error,
               message.contains("需要重新输入密码") {
                await installProduct(at: path)
            } else {
                await MainActor.run {
                    if let installError = error as? InstallManager.InstallError {
                        installationState = .failed(installError)
                    } else {
                        installationState = .failed(error)
                    }
                }
            }
        }
    }

    func getApplicationInfo(buildGuid: String) async throws -> String {
        guard let url = URL(string: NetworkConstants.applicationJsonURL) else {
            throw NetworkError.invalidURL(NetworkConstants.applicationJsonURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        var headers = NetworkConstants.adobeRequestHeaders
        headers["x-adobe-build-guid"] = buildGuid
        headers["Cookie"] = generateCookie()
        
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidData("无法将响应数据转换为json符串")
        }
        
        return jsonString
    }

    func fetchProductsData() async throws -> ([String: Sap], String, [SapCodes]) {
        var components = URLComponents(string: NetworkConstants.productsXmlURL)
        components?.queryItems = [
            URLQueryItem(name: "_type", value: "xml"),
            URLQueryItem(name: "channel", value: "ccm"),
            URLQueryItem(name: "channel", value: "sti"),
            URLQueryItem(name: "platform", value: allowedPlatform.joined(separator: ",")),
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

        let result: ([String: Sap], String, [SapCodes]) = try await Task.detached(priority: .userInitiated) {
            let parseResult = try XHXMLParser.parse(xmlString: xmlString)
            let products = parseResult.products, cdn = parseResult.cdn
            var sapCodes: [SapCodes] = []
            let allowedPlatforms = ["macuniversal", "macarm64", "osx10-64", "osx10"]
            for product in products.values {
                if product.isValid {
                    var lastVersion: String? = nil
                    for version in product.versions.values.reversed() {
                        if !version.buildGuid.isEmpty && allowedPlatforms.contains(version.apPlatform) {
                            lastVersion = version.productVersion
                            break
                        }
                    }
                    if lastVersion != nil {
                        sapCodes.append(SapCodes(
                            sapCode: product.sapCode,
                            displayName: product.displayName
                        ))
                    }
                }
            }
            return (products, cdn, sapCodes)
        }.value
        
        return result
    }

    func isVersionDownloaded(sap: Sap, version: String, language: String) -> URL? {
        let platform = sap.versions[version]?.apPlatform ?? "unknown"
        var fileName = ""
        if(sap.sapCode=="APRO") {
            fileName = "Install \(sap.sapCode)_\(version)_\(platform).dmg"
        } else {
            fileName = "Install \(sap.sapCode)_\(version)-\(language)-\(platform).app"
        }

        let useDefaultDirectory = UserDefaults.standard.bool(forKey: "useDefaultDirectory")
        if useDefaultDirectory && !defaultDirectory.isEmpty {
            let defaultPath = URL(fileURLWithPath: defaultDirectory)
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: defaultPath.path) {
                return defaultPath
            }
        }

        if let task = downloadTasks.first(where: {
            $0.sapCode == sap.sapCode &&
            $0.version == version &&
            $0.language == language
        }) {
            if FileManager.default.fileExists(atPath: task.directory.path) {
                return task.directory
            }
        }

        return nil
    }

    func updateDockBadge() {
        let activeCount = downloadTasks.filter { task in
            if case .completed = task.totalStatus {
                return false
            }
            return true
        }.count

        if activeCount > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(activeCount)"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    private func setupNetworkMonitoring() {
        configureNetworkMonitor()
    }

    func retryFetchData() {
        Task {
            isFetchingProducts = false
            loadingState = .idle
            await fetchProducts()
        }
    }

    func updateAllowedPlatform(useAppleSilicon: Bool) {
        allowedPlatform = useAppleSilicon ? ["macuniversal", "macarm64"] : ["macuniversal", "osx10-64"]
    }
}
