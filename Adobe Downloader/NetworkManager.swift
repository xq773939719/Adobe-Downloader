import Foundation
import Network
import Combine
import AppKit
import SwiftUI


private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var completionHandler: (URL?, URLResponse?, Error?) -> Void
    var progressHandler: ((Int64, Int64, Int64) -> Void)?
    var destinationDirectory: URL
    var fileName: String
    
    init(destinationDirectory: URL,
         fileName: String,
         completionHandler: @escaping (URL?, URLResponse?, Error?) -> Void,
         progressHandler: ((Int64, Int64, Int64) -> Void)? = nil) {
        self.destinationDirectory = destinationDirectory
        self.fileName = fileName
        self.completionHandler = completionHandler
        self.progressHandler = progressHandler
        super.init()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            }
            let destinationURL = destinationDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: location, to: destinationURL)
            Thread.sleep(forTimeInterval: 0.5)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let fileSize = try FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64 ?? 0
                completionHandler(destinationURL, downloadTask.response, nil)
            } else {
                completionHandler(nil, downloadTask.response, NetworkError.fileSystemError("文件移动后不存在", nil))
            }
        } catch {
            print("File operation error in delegate: \(error.localizedDescription)")
            completionHandler(nil, downloadTask.response, error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        switch (error as NSError).code {
        case NSURLErrorCancelled:
            return
        case NSURLErrorTimedOut:
            completionHandler(nil, task.response, NetworkError.downloadError("下载超时", error))
        case NSURLErrorNotConnectedToInternet:
            completionHandler(nil, task.response, NetworkError.noConnection)
        default:
            completionHandler(nil, task.response, error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, 
                   didWriteData bytesWritten: Int64, 
                   totalBytesWritten: Int64, 
                   totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        guard bytesWritten > 0 else { return }
        
        progressHandler?(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }
    func cleanup() {
        completionHandler = { _, _, _ in }
        progressHandler = nil
    }
}

@MainActor
class NetworkManager: ObservableObject {
    typealias ProgressUpdate = (bytesWritten: Int64, totalWritten: Int64, expectedToWrite: Int64)
    @Published var isConnected = false
    @Published var products: [String: Product] = [:]
    @Published var cdn: String = ""
    @Published var loadingState: LoadingState = .idle
    @Published var downloadTasks: [DownloadTask] = []
    @Published var installationState: InstallationState = .idle
    private let cancelTracker = CancelTracker()
    internal var downloadUtils: DownloadUtils!
    internal var progressObservers: [UUID: NSKeyValueObservation] = [:]
    internal var activeDownloadTaskId: UUID?
    internal var monitor = NWPathMonitor()
    internal var isFetchingProducts = false
    private let installManager = InstallManager()
    
    enum InstallationState {
        case idle
        case installing(progress: Double, status: String)
        case completed
        case failed(Error)
    }

    init() {
        self.downloadUtils = DownloadUtils(networkManager: self, cancelTracker: cancelTracker)
        setupNetworkMonitoring()
    }

    func fetchProducts() async {
        await fetchProductsWithRetry()
    }
    
    func startDownload(sapCode: String, version: String, language: String, destinationURL: URL) async throws {
        try await validateAndStartDownload(sapCode: sapCode, version: version, language: language, destinationURL: destinationURL)
    }
    
    func pauseDownload(taskId: UUID) {
        Task { 
            await downloadUtils.pauseDownloadTask(
                taskId: taskId, 
                reason: DownloadTask.DownloadStatus.PauseInfo.PauseReason.userRequested
            ) 
        }
    }
    
    func resumeDownload(taskId: UUID) async {
        await downloadUtils.resumeDownloadTask(taskId: taskId)
    }
    
    func cancelDownload(taskId: UUID, removeFiles: Bool = false) {
        Task { 
            await downloadUtils.cancelDownloadTask(taskId: taskId, removeFiles: removeFiles)
        }
    }
    
    func clearCompletedTasks() {
        Task {
            await clearCompletedDownloadTasks()
        }
    }

    private func setupNetworkMonitoring() {
        configureNetworkMonitor()
    }

    private func validateAndStartDownload(sapCode: String, version: String, language: String, destinationURL: URL) async throws {
        if downloadTasks.contains(where: { task in
            task.sapCode == sapCode && 
            task.version == version && 
            !({
                if case .failed = task.status {
                    return true
                }
                return false
            }())
        }) {
            throw NetworkError.downloadError("该版本已在下载队列中", nil)
        }

        guard let productInfo = products[sapCode]?.versions[version] else {
            throw NetworkError.invalidData("无法获取产品信息")
        }

        let installerURL: URL
        if sapCode == "APRO" {
            let fileName = "Acrobat_DC_Web_WWMUI.dmg"
            installerURL = destinationURL.appendingPathComponent(fileName)
        } else {
            let appName = "Install \(sapCode)_\(version)-\(language)-\(productInfo.apPlatform).app"
            let baseDirectory: URL
            if destinationURL.pathExtension == "app" {
                baseDirectory = destinationURL.deletingLastPathComponent()
            } else {
                baseDirectory = destinationURL
            }
            installerURL = baseDirectory.appendingPathComponent(appName)
        }

        if FileManager.default.fileExists(atPath: installerURL.path) {
            let alert = NSAlert()
            alert.messageText = "安装程序已存在"
            alert.informativeText = "在目标位置已找到相同版本的安装程序，您想要如何处理？"
            alert.addButton(withTitle: "使用已有程序")
            alert.addButton(withTitle: "重新下载")
            alert.addButton(withTitle: "取消")
            
            let response = await MainActor.run {
                alert.runModal()
            }
            
            switch response {
            case .alertFirstButtonReturn:
                let task = DownloadTask(
                    sapCode: sapCode,
                    version: version,
                    language: language,
                    productName: products[sapCode]?.displayName ?? "",
                    status: .completed(DownloadTask.DownloadStatus.CompletionInfo(
                        timestamp: Date(),
                        totalTime: 0,
                        totalSize: 0
                    )),
                    progress: 1.0,
                    downloadedSize: 0,
                    totalSize: 0,
                    speed: 0,
                    currentFileName: "",
                    destinationURL: installerURL,
                    packages: []
                )
                downloadTasks.append(task)
                return
                
            case .alertSecondButtonReturn:
                try? FileManager.default.removeItem(at: installerURL)
            default:
                throw NetworkError.downloadCancelled
            }
        }

        let task = DownloadTask(
            sapCode: sapCode,
            version: version,
            language: language,
            productName: products[sapCode]?.displayName ?? "",
            status: .preparing(DownloadTask.DownloadStatus.PrepareInfo(
                message: "正在初始化...",
                timestamp: Date(),
                stage: .initializing
            )),
            progress: 0,
            downloadedSize: 0,
            totalSize: 0,
            speed: 0,
            currentFileName: "",
            destinationURL: installerURL,
            packages: []
        )

        await MainActor.run {
            downloadTasks.append(task)
            updateDockBadge()
        }

        try await performDownload(task: task, productInfo: productInfo)
    }
    
    private func performDownload(task: DownloadTask, productInfo: Product.ProductVersion) async throws {
        if task.sapCode == "APRO" {
            try await downloadUtils.downloadAPRO(task: task, productInfo: productInfo)
            return
        }

        try downloadUtils.createInstallerApp(
            for: task.sapCode,
            version: task.version,
            language: task.language,
            at: task.destinationURL
        )

        try await downloadUtils.signApp(at: task.destinationURL)

        await updateTaskStatus(task.id, .preparing(DownloadTask.DownloadStatus.PrepareInfo(
            message: "正在获取 \(task.productName) 的下载信息...",
            timestamp: Date(),
            stage: .fetchingInfo
        )))
        let appInfo = try await getApplicationInfo(buildGuid: productInfo.buildGuid)

        let packages = appInfo.Packages.Package.map { package in
            DownloadTask.Package(
                name: package.PackageName ?? "",
                Path: package.Path,
                size: package.size,
                downloadedSize: 0,
                progress: 0,
                speed: 0,
                status: .waiting,
                type: package.PackageType ?? "",
                downloaded: false,
                lastUpdated: Date(),
                lastRecordedSize: 0
            )
        }

        await MainActor.run {
            if let index = downloadTasks.firstIndex(where: { $0.id == task.id }) {
                downloadTasks[index].packages = packages
                downloadTasks[index].totalSize = packages.reduce(0) { $0 + $1.size }
            }
        }

        let productDir = task.destinationURL.appendingPathComponent("Contents/Resources/products/\(task.sapCode)")
        try FileManager.default.createDirectory(at: productDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(appInfo)
        try jsonData.write(to: productDir.appendingPathComponent("application.json"))

        await MainActor.run {
            if let taskIndex = downloadTasks.firstIndex(where: { $0.id == task.id }) {
                downloadTasks[taskIndex].status = .downloading(DownloadTask.DownloadStatus.DownloadInfo(
                    fileName: packages[0].name,
                    currentPackageIndex: 0,
                    totalPackages: packages.count,
                    startTime: Date(),
                    estimatedTimeRemaining: nil
                ))
            }
        }

        await resumeDownload(taskId: task.id)

        let driverXml = downloadUtils.generateDriverXML(
            sapCode: task.sapCode,
            version: task.version,
            language: task.language,
            productInfo: productInfo,
            displayName: task.productName
        )

        let productsDir = task.destinationURL.appendingPathComponent("Contents/Resources/products")
        try driverXml.write(to: productsDir.appendingPathComponent("driver.xml"), 
                          atomically: true, 
                          encoding: .utf8)
    }

    private func handleDownloadError(taskId: UUID, error: Error) async {
        await MainActor.run {
            guard let index = downloadTasks.firstIndex(where: { $0.id == taskId }) else { return }

            let (errorMessage, isRecoverable) = classifyError(error)

            if isRecoverable && downloadTasks[index].retryCount < NetworkConstants.maxRetryAttempts {
                downloadTasks[index].retryCount += 1
                let nextRetryDate = Date().addingTimeInterval(TimeInterval(NetworkConstants.retryDelay / 1_000_000_000))
                downloadTasks[index].status = .retrying(DownloadTask.DownloadStatus.RetryInfo(
                    attempt: downloadTasks[index].retryCount,
                    maxAttempts: NetworkConstants.maxRetryAttempts,
                    reason: errorMessage,
                    nextRetryDate: nextRetryDate
                ))

                Task {
                    do {
                        try await Task.sleep(nanoseconds: NetworkConstants.retryDelay)
                        if await !cancelTracker.isCancelled(taskId) {
                            await downloadUtils.resumeDownloadTask(taskId: taskId)
                        }
                    } catch {
                        print("Retry cancelled for task: \(taskId)")
                    }
                }
            } else {
                downloadTasks[index].status = .failed(DownloadTask.DownloadStatus.FailureInfo(
                    message: errorMessage,
                    error: error,
                    timestamp: Date(),
                    recoverable: isRecoverable
                ))

                progressObservers[taskId]?.invalidate()
                progressObservers.removeValue(forKey: taskId)

                if let currentPackage = downloadTasks[index].packages.first(where: { !$0.downloaded }) {
                    let destinationDir = downloadTasks[index].destinationURL
                        .appendingPathComponent("Contents/Resources/products/\(downloadTasks[index].sapCode)")
                    let fileName = currentPackage.Path.components(separatedBy: "/").last ?? ""
                    let fileURL = destinationDir.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }

                updateDockBadge()
                objectWillChange.send()
            }
        }
    }
    
    private func classifyError(_ error: Error) -> (message: String, recoverable: Bool) {
        switch error {
        case let networkError as NetworkError:
            switch networkError {
            case .noConnection:
                return ("网络连接已断开", true)
            case .timeout:
                return ("下载超时", true)
            case .serverUnreachable:
                return ("服务器无法访问", true)
            case .insufficientStorage:
                return ("存储空间不足", false)
            case .filePermissionDenied:
                return ("没有入权限", false)
            default:
                return (networkError.localizedDescription, false)
            }
        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet:
                return ("网络连接已断开", true)
            case .timedOut:
                return ("连接超时", true)
            case .cancelled:
                return ("下载已取消", false)
            default:
                return (urlError.localizedDescription, true)
            }
        default:
            return (error.localizedDescription, false)
        }
    }

    private func updateProgress(for taskId: UUID, progress: ProgressUpdate) {
        guard let index = downloadTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let task = downloadTasks[index]
        guard let packageIndex = task.packages.firstIndex(where: { !$0.downloaded }) else { return }
        let now = Date()
        let timeDiff = now.timeIntervalSince(task.packages[packageIndex].lastUpdated)
        guard timeDiff >= NetworkConstants.progressUpdateInterval else { return }
        downloadTasks[index].packages[packageIndex].downloadedSize = progress.totalWritten
        downloadTasks[index].packages[packageIndex].progress = 
            clampProgress(Double(progress.totalWritten) / Double(progress.expectedToWrite))
        let byteDiff = progress.totalWritten - task.packages[packageIndex].lastRecordedSize
        if byteDiff > 0 {
            let speed = Double(byteDiff) / timeDiff
            downloadTasks[index].packages[packageIndex].speed = speed
            downloadTasks[index].speed = speed
        }
        var totalDownloaded: Int64 = 0
        for (i, package) in task.packages.enumerated() {
            if package.downloaded {
                totalDownloaded += package.size
            } else if i == packageIndex {
                totalDownloaded += min(progress.totalWritten, package.size)
            }
        }
        downloadTasks[index].downloadedSize = totalDownloaded
        downloadTasks[index].progress = clampProgress(Double(totalDownloaded) / Double(task.totalSize))
        if progress.totalWritten >= progress.expectedToWrite {
            downloadTasks[index].packages[packageIndex].downloaded = true
            downloadTasks[index].packages[packageIndex].downloadedSize = downloadTasks[index].packages[packageIndex].size
            downloadTasks[index].packages[packageIndex].progress = 1.0
            downloadTasks[index].packages[packageIndex].speed = 0
        }
        downloadTasks[index].packages[packageIndex].lastRecordedSize = progress.totalWritten
        downloadTasks[index].packages[packageIndex].lastUpdated = now
        objectWillChange.send()
    }

    private func updateTaskStatus(_ taskId: UUID, _ status: DownloadTask.DownloadStatus) async {
        await MainActor.run {
            guard let index = downloadTasks.firstIndex(where: { $0.id == taskId }) else { return }
            downloadTasks[index].status = status
            switch status {
            case .completed:
                progressObservers[taskId]?.invalidate()
                progressObservers.removeValue(forKey: taskId)
                if activeDownloadTaskId == taskId {
                    activeDownloadTaskId = nil
                }
                
            case .failed:
                progressObservers[taskId]?.invalidate()
                progressObservers.removeValue(forKey: taskId)
                if activeDownloadTaskId == taskId {
                    activeDownloadTaskId = nil
                }
                
            case .downloading:
                activeDownloadTaskId = taskId
                
            case .paused:
                if activeDownloadTaskId == taskId {
                    activeDownloadTaskId = nil
                }
                
            default:
                break
            }

            updateDockBadge()
            objectWillChange.send()
        }
    }

    private func clampProgress(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    func retryFetchData() {
        Task {
            isFetchingProducts = false
            loadingState = .idle
            await fetchProducts()
        }
    }

    func getActiveTaskId() async -> UUID? {
        await MainActor.run { activeDownloadTaskId }
    }
    
    func setTaskStatus(_ taskId: UUID, _ status: DownloadTask.DownloadStatus) async {
        await updateTaskStatus(taskId, status)
    }
    
    func getTasks() async -> [DownloadTask] {
        await MainActor.run { downloadTasks }
    }
    
    func handleError(_ taskId: UUID, _ error: Error) async {
        await handleDownloadError(taskId: taskId, error: error)
    }
    func updateDownloadProgress(for taskId: UUID, progress: ProgressUpdate) {
        updateProgress(for: taskId, progress: progress)
    }

    var cdnUrl: String {
        get async {
            await MainActor.run { cdn }
        }
    }

    func removeTask(taskId: UUID, removeFiles: Bool = false) {
        Task {
            if removeFiles {
                if let task = downloadTasks.first(where: { $0.id == taskId }) {
                    try? FileManager.default.removeItem(at: task.destinationURL)
                }
            }

            await MainActor.run {
                downloadTasks.removeAll { $0.id == taskId }
                updateDockBadge()
                objectWillChange.send()
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
                let (products, cdn) = try await fetchProductsData()
                await MainActor.run {
                    self.products = products
                    self.cdn = cdn
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
                task.status.isCompleted || task.status.isFailed
            }
            updateDockBadge()
            objectWillChange.send()
        }
    }

    func installProduct(at path: URL) async {
        await MainActor.run {
            installationState = .installing(progress: 0, status: "准备安装...")
        }
        
        do {
            try await installManager.install(at: path) { progress, status in
                Task { @MainActor in
                    if status.contains("完成") || status.contains("成功") {
                        self.installationState = .completed
                    } else if progress >= 1.0 {
                        self.installationState = .completed
                    } else {
                        self.installationState = .installing(progress: progress, status: status)
                    }
                }
            }

            await MainActor.run {
                installationState = .completed
            }
        } catch {
            await MainActor.run {
                installationState = .failed(error)
            }
        }
    }

    func cancelInstallation() {
        Task {
            await installManager.cancel()
        }
    }
}
