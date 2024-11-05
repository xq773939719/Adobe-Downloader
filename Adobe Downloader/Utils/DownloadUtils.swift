//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation
import Network
import Combine
import AppKit

class DownloadUtils {
    typealias ProgressUpdate = (bytesWritten: Int64, totalWritten: Int64, expectedToWrite: Int64)

    private weak var networkManager: NetworkManager?
    private let cancelTracker: CancelTracker

    init(networkManager: NetworkManager, cancelTracker: CancelTracker) {
        self.networkManager = networkManager
        self.cancelTracker = cancelTracker
    }

    private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        var completionHandler: (URL?, URLResponse?, Error?) -> Void
        var progressHandler: ((Int64, Int64, Int64) -> Void)?
        var destinationDirectory: URL
        var fileName: String
        private var hasCompleted = false
        private let completionLock = NSLock()
        
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
            completionLock.lock()
            defer { completionLock.unlock() }
            
            guard !hasCompleted else { return }
            hasCompleted = true
            
            do {
                if !FileManager.default.fileExists(atPath: destinationDirectory.path) {
                    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                }

                let destinationURL = destinationDirectory.appendingPathComponent(fileName)

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                try FileManager.default.moveItem(at: location, to: destinationURL)
                completionHandler(destinationURL, downloadTask.response, nil)
                
            } catch {
                print("File operation error in delegate: \(error.localizedDescription)")
                completionHandler(nil, downloadTask.response, error)
            }
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            completionLock.lock()
            defer { completionLock.unlock() }
            
            guard !hasCompleted else { return }
            hasCompleted = true
            
            if let error = error {
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

    func pauseDownloadTask(taskId: UUID, reason: DownloadStatus.PauseInfo.PauseReason) async {
        await MainActor.run {
            if let task = networkManager?.downloadTasks.first(where: { $0.id == taskId }) {
                task.setStatus(.paused(DownloadStatus.PauseInfo(
                    reason: reason,
                    timestamp: Date(),
                    resumable: true
                )))
            }
        }
        await cancelTracker.pause(taskId)
    }
    
    func resumeDownloadTask(taskId: UUID) async {
        await MainActor.run {
            if let task = networkManager?.downloadTasks.first(where: { $0.id == taskId }) {
                task.setStatus(.downloading(DownloadStatus.DownloadInfo(
                    fileName: task.currentPackage?.fullPackageName ?? "",
                    currentPackageIndex: 0,
                    totalPackages: task.productsToDownload.reduce(0) { $0 + $1.packages.count },
                    startTime: Date(),
                    estimatedTimeRemaining: nil
                )))
            }
        }
        
        if let task = await networkManager?.downloadTasks.first(where: { $0.id == taskId }) {
            await startDownloadProcess(task: task)
        }
    }
    
    func cancelDownloadTask(taskId: UUID, removeFiles: Bool = false) async {
        await cancelTracker.cancel(taskId)
        
        await MainActor.run {
            if let task = networkManager?.downloadTasks.first(where: { $0.id == taskId }) {
                if removeFiles {
                    try? FileManager.default.removeItem(at: task.directory)
                }
                
                task.setStatus(.failed(DownloadStatus.FailureInfo(
                    message: "下载已取消",
                    error: NetworkError.downloadCancelled,
                    timestamp: Date(),
                    recoverable: false
                )))
                
                networkManager?.updateDockBadge()
                networkManager?.objectWillChange.send()
            }
        }
    }
    
    func signApp(at url: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--deep", "--sign", "-", url.path]
        try process.run()
        process.waitUntilExit()
    }
    
    func createInstallerApp(for sapCode: String, version: String, language: String, at destinationURL: URL) throws {
        let parentDirectory = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) { try FileManager.default.removeItem(at: destinationURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")

        let tempScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("installer.js")
        try NetworkConstants.INSTALL_APP_APPLE_SCRIPT.write(to: tempScriptURL, atomically: true, encoding: .utf8)

        process.arguments = ["-l", "JavaScript", "-o", destinationURL.path, tempScriptURL.path]
        
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NetworkError.fileSystemError("Failed to create installer app: Exit code \(process.terminationStatus)", nil)
        }
        
        try? FileManager.default.removeItem(at: tempScriptURL)

        let iconDestination = destinationURL.appendingPathComponent("Contents/Resources/applet.icns")
        if FileManager.default.fileExists(atPath: iconDestination.path) { try FileManager.default.removeItem(at: iconDestination) }

        if FileManager.default.fileExists(atPath: NetworkConstants.ADOBE_CC_MAC_ICON_PATH) {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: NetworkConstants.ADOBE_CC_MAC_ICON_PATH),
                to: iconDestination
            )
        } else {
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: NetworkConstants.MAC_VOLUME_ICON_PATH),
                to: iconDestination
            )
        }

        try FileManager.default.createDirectory(
            at: destinationURL.appendingPathComponent("Contents/Resources/products"),
            withIntermediateDirectories: true
        )
    }
    
    func generateDriverXML(sapCode: String, version: String, language: String, productInfo: Sap.Versions, displayName: String) -> String {
        let dependencies = productInfo.dependencies.map { dependency in
            """
                <Dependency>
                    <SAPCode>\(dependency.sapCode)</SAPCode>
                    <BaseVersion>\(dependency.version)</BaseVersion>
                    <EsdDirectory>./\(dependency.sapCode)</EsdDirectory>
                </Dependency>
            """
        }.joined(separator: "\n")
        
        return """
        <DriverInfo>
            <ProductInfo>
                <Name>Adobe \(displayName)</Name>
                <SAPCode>\(sapCode)</SAPCode>
                <CodexVersion>\(version)</CodexVersion>
                <Platform>\(productInfo.apPlatform)</Platform>
                <EsdDirectory>./\(sapCode)</EsdDirectory>
                <Dependencies>
                    \(dependencies)
                </Dependencies>
            </ProductInfo>
            <RequestInfo>
                <InstallDir>/Applications</InstallDir>
                <InstallLanguage>\(language)</InstallLanguage>
            </RequestInfo>
        </DriverInfo>
        """
    }
    
    func clearExtendedAttributes(at url: URL) async throws {
        let escapedPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        do shell script "sudo xattr -cr '\(escapedPath)'" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
                if let output = String(data: data, encoding: .utf8) {
                    print("xattr command output:", output)
                }
            }
        } catch {
            print("Error executing xattr command:", error.localizedDescription)
        }
    }

    internal func startDownloadProcess(task: NewDownloadTask) async {
        actor DownloadProgress {
            var currentPackageIndex: Int = 0
            func increment() { currentPackageIndex += 1 }
            func get() -> Int { return currentPackageIndex }
        }
        
        let progress = DownloadProgress()
        
        await MainActor.run {
            let totalPackages = task.productsToDownload.reduce(0) { $0 + $1.packages.count }
            task.setStatus(.downloading(DownloadStatus.DownloadInfo(
                fileName: task.currentPackage?.fullPackageName ?? "",
                currentPackageIndex: 0,
                totalPackages: totalPackages,
                startTime: Date(),
                estimatedTimeRemaining: nil
            )))
            task.objectWillChange.send()
        }

        let driverPath = task.directory.appendingPathComponent("Contents/Resources/products/driver.xml")
        if !FileManager.default.fileExists(atPath: driverPath.path) {
            if let productInfo = await networkManager?.saps[task.sapCode]?.versions[task.version] {
                let driverXml = generateDriverXML(
                    sapCode: task.sapCode,
                    version: task.version,
                    language: task.language,
                    productInfo: productInfo,
                    displayName: task.displayName
                )
                do {
                    try driverXml.write(to: driverPath, atomically: true, encoding: .utf8)
                } catch {
                    print("Error generating driver.xml:", error.localizedDescription)
                    await MainActor.run {
                        task.setStatus(.failed(DownloadStatus.FailureInfo(
                            message: "生成 driver.xml 失败: \(error.localizedDescription)",
                            error: error,
                            timestamp: Date(),
                            recoverable: false
                        )))
                    }
                    return
                }
            }
        }

        for product in task.productsToDownload {
            for package in product.packages where !package.downloaded {
                let currentIndex = await progress.get()
                
                await MainActor.run {
                    task.currentPackage = package
                    task.setStatus(.downloading(DownloadStatus.DownloadInfo(
                        fileName: package.fullPackageName,
                        currentPackageIndex: currentIndex,
                        totalPackages: task.productsToDownload.reduce(0) { $0 + $1.packages.count },
                        startTime: Date(),
                        estimatedTimeRemaining: nil
                    )))
                }
                
                await progress.increment()
                
                guard !package.fullPackageName.isEmpty,
                      !package.downloadURL.isEmpty,
                      package.downloadSize > 0 else {
                    continue
                }

                let cdn = await networkManager?.cdn ?? ""
                let cleanCdn = cdn.hasSuffix("/") ? String(cdn.dropLast()) : cdn
                let cleanPath = package.downloadURL.hasPrefix("/") ? package.downloadURL : "/\(package.downloadURL)"
                let downloadURL = cleanCdn + cleanPath
                
                guard let url = URL(string: downloadURL) else { continue }

                do {
                    try await downloadPackage(package: package, task: task, product: product, url: url)
                } catch {
                    print("Error downloading \(package.fullPackageName): \(error.localizedDescription)")
                    await self.handleError(task.id, error)
                    return
                }
            }
        }

        let allPackagesDownloaded = task.productsToDownload.allSatisfy { product in
            product.packages.allSatisfy { $0.downloaded }
        }
        
        if allPackagesDownloaded {
            await MainActor.run {
                task.setStatus(.completed(DownloadStatus.CompletionInfo(
                    timestamp: Date(),
                    totalTime: Date().timeIntervalSince(task.createAt),
                    totalSize: task.totalSize
                )))
            }
        }
    }

    private func downloadPackage(package: Package, task: NewDownloadTask, product: ProductsToDownload, url: URL) async throws {
        var lastUpdateTime = Date()
        var lastBytes: Int64 = 0
        
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                destinationDirectory: task.directory.appendingPathComponent("Contents/Resources/products/\(product.sapCode)"),
                fileName: package.fullPackageName,
                completionHandler: { [weak networkManager] localURL, response, error in
                    if let error = error {
                        if (error as NSError).code == NSURLErrorCancelled {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }

                    Task { @MainActor in
                        package.downloadedSize = package.downloadSize
                        package.progress = 1.0
                        package.status = .completed
                        package.downloaded = true

                        var totalDownloaded: Int64 = 0
                        var totalSize: Int64 = 0

                        for prod in task.productsToDownload {
                            for pkg in prod.packages {
                                totalSize += pkg.downloadSize
                                if pkg.downloaded {
                                    totalDownloaded += pkg.downloadSize
                                }
                            }
                        }

                        task.totalSize = totalSize
                        task.totalDownloadedSize = totalDownloaded
                        task.totalProgress = Double(totalDownloaded) / Double(totalSize)
                        task.totalSpeed = 0

                        let allCompleted = task.productsToDownload.allSatisfy {
                            product in product.packages.allSatisfy { $0.downloaded }
                        }

                        if allCompleted {
                            task.setStatus(.completed(DownloadStatus.CompletionInfo(
                                timestamp: Date(),
                                totalTime: Date().timeIntervalSince(task.createAt),
                                totalSize: totalSize
                            )))
                        }

                        task.objectWillChange.send()
                        networkManager?.objectWillChange.send()
                    }

                    continuation.resume()
                },
                progressHandler: { [weak networkManager] bytesWritten, totalBytesWritten, totalBytesExpectedToWrite in
                    Task { @MainActor in
                        let now = Date()
                        let timeDiff = now.timeIntervalSince(lastUpdateTime)

                        if timeDiff >= 1.0 {
                            let bytesDiff = totalBytesWritten - lastBytes
                            let speed = Double(bytesDiff) / timeDiff
                            
                            package.updateProgress(
                                downloadedSize: totalBytesWritten,
                                speed: speed
                            )
                            
                            var completedSize: Int64 = 0
                            var totalSize: Int64 = 0
                            
                            for prod in task.productsToDownload {
                                for pkg in prod.packages {
                                    totalSize += pkg.downloadSize
                                    if pkg.downloaded {
                                        completedSize += pkg.downloadSize
                                    } else if pkg.id == package.id {
                                        completedSize += totalBytesWritten
                                    }
                                }
                            }
                            
                            task.totalSize = totalSize
                            task.totalDownloadedSize = completedSize
                            task.totalProgress = Double(completedSize) / Double(totalSize)
                            task.totalSpeed = speed
                            
                            lastUpdateTime = now
                            lastBytes = totalBytesWritten
                            
                            task.objectWillChange.send()
                            networkManager?.objectWillChange.send()
                        }
                    }
                }
            )
            
            var request = URLRequest(url: url)
            NetworkConstants.downloadHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

            Task {
                if let resumeData = await cancelTracker.getResumeData(task.id) {
                    let downloadTask = session.downloadTask(withResumeData: resumeData)
                    await cancelTracker.registerTask(task.id, task: downloadTask, session: session)
                    await cancelTracker.clearResumeData(task.id)
                    downloadTask.resume()
                } else {
                    let downloadTask = session.downloadTask(with: request)
                    await cancelTracker.registerTask(task.id, task: downloadTask, session: session)
                    downloadTask.resume()
                }
            }
        }
    }

    func retryPackage(task: NewDownloadTask, package: Package) async throws {
        guard package.canRetry else { return }
        
        package.prepareForRetry()

        if let product = task.productsToDownload.first(where: { $0.packages.contains(where: { $0.id == package.id }) }) {
            await MainActor.run {
                task.currentPackage = package
            }

            if let cdn = await networkManager?.cdnUrl {
                try await downloadPackage(package: package, task: task, product: product, url: URL(string: cdn + package.downloadURL)!)
            } else {
                throw NetworkError.invalidData("无法取 CDN 地址")
            }
        }
    }

    func downloadAPRO(task: NewDownloadTask, productInfo: Sap.Versions) async throws {
        guard let networkManager = networkManager else { return }
        
        let manifestURL = await networkManager.cdnUrl + productInfo.buildGuid
        guard let url = URL(string: manifestURL) else {
            throw NetworkError.invalidURL(manifestURL)
        }
        
        var request = URLRequest(url: url)
        NetworkConstants.adobeRequestHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let (manifestData, _) = try await URLSession.shared.data(for: request)
        
        let manifestXML = try XMLDocument(data: manifestData)
        
        guard let downloadPath = try manifestXML.nodes(forXPath: "//asset_list/asset/asset_path").first?.stringValue,
              let assetSizeStr = try manifestXML.nodes(forXPath: "//asset_list/asset/asset_size").first?.stringValue,
              let assetSize = Int64(assetSizeStr) else {
            throw NetworkError.invalidData("无法从manifest中获取下载信息")
        }

        let aproPackage = Package(
            type: "dmg",
            fullPackageName: "Install \(task.sapCode)_\(productInfo.productVersion)_\(productInfo.apPlatform).dmg",
            downloadSize: assetSize,
            downloadURL: downloadPath
        )

        await MainActor.run {
            let product = ProductsToDownload(
                sapCode: task.sapCode,
                version: task.version,
                buildGuid: productInfo.buildGuid
            )
            product.packages = [aproPackage]
            task.productsToDownload = [product]
            task.totalSize = assetSize
            task.currentPackage = aproPackage
            task.setStatus(.downloading(DownloadStatus.DownloadInfo(
                fileName: aproPackage.fullPackageName,
                currentPackageIndex: 0,
                totalPackages: 1,
                startTime: Date(),
                estimatedTimeRemaining: nil
            )))
        }

        let tempDownloadDir = task.directory.deletingLastPathComponent()

        var lastUpdateTime = Date()
        var lastBytes: Int64 = 0

        let delegate = DownloadDelegate(
            destinationDirectory: tempDownloadDir,
            fileName: aproPackage.fullPackageName,
            completionHandler: { [weak networkManager] (localURL: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    print("Download error:", error)
                    return
                }
                Task { @MainActor in
                    aproPackage.downloadedSize = aproPackage.downloadSize
                    aproPackage.progress = 1.0
                    aproPackage.status = .completed
                    aproPackage.downloaded = true
                    
                    var totalDownloaded: Int64 = 0
                    var totalSize: Int64 = 0
                    
                    totalSize += aproPackage.downloadSize
                    if aproPackage.downloaded {
                        totalDownloaded += aproPackage.downloadSize
                    }
                    
                    task.totalSize = totalSize
                    task.totalDownloadedSize = totalDownloaded
                    task.totalProgress = Double(totalDownloaded) / Double(totalSize)
                    task.totalSpeed = 0
                    
                    let allCompleted = task.productsToDownload.allSatisfy { product in
                        product.packages.allSatisfy { $0.downloaded }
                    }
                    
                    if allCompleted {
                        task.setStatus(.completed(DownloadStatus.CompletionInfo(
                            timestamp: Date(),
                            totalTime: Date().timeIntervalSince(task.createAt),
                            totalSize: totalSize
                        )))
                    }
                    
                    task.objectWillChange.send()
                    networkManager?.objectWillChange.send()
                }
            },
            progressHandler: { [weak networkManager] (bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) in
                Task { @MainActor in
                    let now = Date()
                    let timeDiff = now.timeIntervalSince(lastUpdateTime)

                    if timeDiff >= 1.0 {
                        let bytesDiff = totalBytesWritten - lastBytes
                        let speed = Double(bytesDiff) / timeDiff

                        aproPackage.updateProgress(
                            downloadedSize: totalBytesWritten,
                            speed: speed
                        )

                        task.totalDownloadedSize = totalBytesWritten
                        task.totalProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                        task.totalSpeed = speed
                        
                        lastUpdateTime = now
                        lastBytes = totalBytesWritten
                        
                        task.objectWillChange.send()
                        networkManager?.objectWillChange.send()
                    }
                }
            }
        )

        guard let fullURL = URL(string: downloadPath) else {
            throw NetworkError.invalidURL(downloadPath)
        }
        
        var request2 = URLRequest(url: fullURL)
        NetworkConstants.downloadHeaders.forEach { request2.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: request2)
        downloadTask.resume()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let originalCompletionHandler = delegate.completionHandler
            
            delegate.completionHandler = { (url: URL?, response: URLResponse?, error: Error?) in
                originalCompletionHandler(url, response, error)
                
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func handleDownload(task: NewDownloadTask, productInfo: Sap.Versions, allowedPlatform: [String], saps: [String: Sap]) async throws {
        if task.sapCode == "APRO" {
            try await downloadAPRO(task: task, productInfo: productInfo)
            return
        }
        
        try createInstallerApp(
            for: task.sapCode,
            version: task.version,
            language: task.language,
            at: task.directory
        )
        
        var productsToDownload: [ProductsToDownload] = []

        productsToDownload.append(ProductsToDownload(
            sapCode: task.sapCode,
            version: task.version,
            buildGuid: productInfo.buildGuid
        ))

        for dependency in productInfo.dependencies {
            if let dependencyVersions = saps[dependency.sapCode]?.versions {
                let sortedVersions = dependencyVersions.sorted { first, second in
                    first.value.productVersion.compare(second.value.productVersion, options: .numeric) == .orderedDescending
                }
                
                var firstGuid = "", buildGuid = ""
                
                for (_, versionInfo) in sortedVersions where versionInfo.baseVersion == dependency.version {
                    if firstGuid.isEmpty { firstGuid = versionInfo.buildGuid }
                    
                    if allowedPlatform.contains(versionInfo.apPlatform) {
                        buildGuid = versionInfo.buildGuid
                        break
                    }
                }
                
                if buildGuid.isEmpty { buildGuid = firstGuid }
                
                if !buildGuid.isEmpty {
                    productsToDownload.append(ProductsToDownload(
                        sapCode: dependency.sapCode,
                        version: dependency.version,
                        buildGuid: buildGuid
                    ))
                }
            }
        }

        for product in productsToDownload {
            await MainActor.run {
                task.setStatus(.preparing(DownloadStatus.PrepareInfo(
                    message: "正在处理 \(product.sapCode) 的包信息...",
                    timestamp: Date(),
                    stage: .fetchingInfo
                )))
            }

            let productDir = task.directory.appendingPathComponent("Contents/Resources/products/\(product.sapCode)")
            if !FileManager.default.fileExists(atPath: productDir.path) {
                try FileManager.default.createDirectory(at: productDir, withIntermediateDirectories: true)
            }

            let jsonString = try await getApplicationInfo(buildGuid: product.buildGuid)
            let jsonURL = productDir.appendingPathComponent("application.json")
            try jsonString.write(to: jsonURL, atomically: true, encoding: .utf8)

            guard let jsonData = jsonString.data(using: .utf8),
                  let appInfo = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let packages = appInfo["Packages"] as? [String: Any],
                  let packageArray = packages["Package"] as? [[String: Any]] else {
                throw NetworkError.invalidData("无法解析产品信息")
            }

            for package in packageArray {
                let fullPackageName: String
                if let name = package["fullPackageName"] as? String, !name.isEmpty {
                    fullPackageName = name
                } else if let name = package["PackageName"] as? String, !name.isEmpty {
                    fullPackageName = "\(name).zip"
                } else { continue }

                let packageType = package["Type"] as? String ?? "non-core"
                let isLanguageSuitable: Bool
                if packageType == "core" {
                    isLanguageSuitable = true
                } else {
                    let condition = package["Condition"] as? String ?? ""
                    let osLang = Locale.current.identifier
                    isLanguageSuitable = (
                        task.language == "ALL" || condition.isEmpty ||
                        !condition.contains("[installLanguage]") || condition.contains("[installLanguage]==\(task.language)") ||
                        condition.contains("[installLanguage]==\(osLang)")
                    )
                }

                if isLanguageSuitable {
                    let downloadSize: Int64
                    if let sizeNumber = package["DownloadSize"] as? NSNumber {
                        downloadSize = sizeNumber.int64Value
                    } else if let sizeString = package["DownloadSize"] as? String,
                              let parsedSize = Int64(sizeString) {
                        downloadSize = parsedSize
                    } else if let sizeInt = package["DownloadSize"] as? Int {
                        downloadSize = Int64(sizeInt)
                    } else { continue }

                    guard let downloadURL = package["Path"] as? String, !downloadURL.isEmpty else { continue }

                    let newPackage = Package(
                        type: packageType,
                        fullPackageName: fullPackageName,
                        downloadSize: downloadSize,
                        downloadURL: downloadURL
                    )
                    product.packages.append(newPackage)
                }
            }
        }

        let finalProducts = productsToDownload
        let totalSize = finalProducts.reduce(0) { productSum, product in
            productSum + product.packages.reduce(0) { packageSum, pkg in
                packageSum + (pkg.downloadSize > 0 ? pkg.downloadSize : 0)
            }
        }

        await MainActor.run {
            task.productsToDownload = finalProducts
            task.totalSize = totalSize
        }
        
        await startDownloadProcess(task: task)
    }

    func getApplicationInfo(buildGuid: String) async throws -> String {
        guard let url = URL(string: NetworkConstants.applicationJsonURL) else {
            throw NetworkError.invalidURL(NetworkConstants.applicationJsonURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        var headers = NetworkConstants.adobeRequestHeaders
        headers["x-adobe-build-guid"] = buildGuid
        headers["Cookie"] = await networkManager?.generateCookie() ?? ""
        
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.invalidData("无法将响应数据转换为json字符串")
        }
        
        return jsonString
    }

    func handleError(_ taskId: UUID, _ error: Error) async {
        guard let task = await networkManager?.downloadTasks.first(where: { $0.id == taskId }) else { return }
        
        let (errorMessage, isRecoverable) = classifyError(error)
        
        if isRecoverable && task.retryCount < NetworkConstants.maxRetryAttempts {
            task.retryCount += 1
            let nextRetryDate = Date().addingTimeInterval(TimeInterval(NetworkConstants.retryDelay / 1_000_000_000))
            task.setStatus(.retrying(DownloadStatus.RetryInfo(
                attempt: task.retryCount,
                maxAttempts: NetworkConstants.maxRetryAttempts,
                reason: errorMessage,
                nextRetryDate: nextRetryDate
            )))
            
            Task {
                do {
                    try await Task.sleep(nanoseconds: NetworkConstants.retryDelay)
                    if await !cancelTracker.isCancelled(taskId) {
                        await resumeDownloadTask(taskId: taskId)
                    }
                } catch {
                    print("Retry cancelled for task: \(taskId)")
                }
            }
        } else {
            await MainActor.run {
                task.setStatus(.failed(DownloadStatus.FailureInfo(
                    message: errorMessage,
                    error: error,
                    timestamp: Date(),
                    recoverable: isRecoverable
                )))
                
                if let currentPackage = task.currentPackage {
                    let destinationDir = task.directory
                        .appendingPathComponent("Contents/Resources/products/\(task.sapCode)")
                    let fileURL = destinationDir.appendingPathComponent(currentPackage.fullPackageName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                
                networkManager?.updateDockBadge()
                networkManager?.objectWillChange.send()
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
                return ("网络连接已开", true)
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

    @MainActor
    func updateProgress(for taskId: UUID, progress: ProgressUpdate) {
        guard let task = networkManager?.downloadTasks.first(where: { $0.id == taskId }),
              let currentPackage = task.currentPackage else { return }
        
        let now = Date()
        let timeDiff = now.timeIntervalSince(currentPackage.lastUpdated)

        if timeDiff >= NetworkConstants.progressUpdateInterval {
            currentPackage.updateProgress(
                downloadedSize: progress.totalWritten,
                speed: Double(progress.bytesWritten)
            )

            let totalDownloaded = task.productsToDownload.reduce(Int64(0)) { sum, prod in
                sum + prod.packages.reduce(Int64(0)) { sum, pkg in
                    if pkg.downloaded {
                        return sum + pkg.downloadSize
                    } else if pkg.id == currentPackage.id {
                        return sum + progress.totalWritten
                    }
                    return sum
                }
            }
            
            task.totalDownloadedSize = totalDownloaded
            task.totalProgress = Double(totalDownloaded) / Double(task.totalSize)
            task.totalSpeed = currentPackage.speed

            currentPackage.lastRecordedSize = progress.totalWritten
            currentPackage.lastUpdated = now

            task.objectWillChange.send()
            networkManager?.objectWillChange.send()
        }
    }

    @MainActor
    func updateTaskStatus(_ taskId: UUID, _ status: DownloadStatus) async {
        guard let networkManager = networkManager else { return }
        
        if let index = networkManager.downloadTasks.firstIndex(where: { $0.id == taskId }) {
            networkManager.downloadTasks[index].setStatus(status)
            
            switch status {
            case .completed, .failed:
                networkManager.progressObservers[taskId]?.invalidate()
                networkManager.progressObservers.removeValue(forKey: taskId)
                if networkManager.activeDownloadTaskId == taskId {
                    networkManager.activeDownloadTaskId = nil
                }
                
            case .downloading:
                networkManager.activeDownloadTaskId = taskId
                
            case .paused:
                if networkManager.activeDownloadTaskId == taskId {
                    networkManager.activeDownloadTaskId = nil
                }
                
            default:
                break
            }
            
            networkManager.updateDockBadge()
            networkManager.objectWillChange.send()
        }
    }
}
