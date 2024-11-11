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
        let task = await cancelTracker.downloadTasks[taskId]
        if let downloadTask = task {
            let data = await withCheckedContinuation { continuation in
                downloadTask.cancel(byProducingResumeData: { data in
                    continuation.resume(returning: data)
                })
            }
            if let data = data {
                await cancelTracker.storeResumeData(taskId, data: data)
            }
        }
        
        await MainActor.run {
            if let task = networkManager?.downloadTasks.first(where: { $0.id == taskId }) {
                task.setStatus(.paused(DownloadStatus.PauseInfo(
                    reason: reason,
                    timestamp: Date(),
                    resumable: true
                )))
                networkManager?.saveTask(task)
            }
        }
    }
    
    func resumeDownloadTask(taskId: UUID) async {
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
    
    func generateDriverXML(sapCode: String, version: String, language: String, productInfo: Sap.Versions, displayName: String) -> String {
        let dependencies = productInfo.dependencies.map { dependency in
            """
                <Dependency>
                    <SAPCode>\(dependency.sapCode)</SAPCode>
                    <BaseVersion>\(dependency.version)</BaseVersion>
                    <EsdDirectory>\(dependency.sapCode)</EsdDirectory>
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
                <EsdDirectory>\(sapCode)</EsdDirectory>
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

    private func downloadPackage(package: Package, task: NewDownloadTask, product: ProductsToDownload, url: URL? = nil, resumeData: Data? = nil) async throws {
        var lastUpdateTime = Date()
        var lastBytes: Int64 = 0
        
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                destinationDirectory: task.directory.appendingPathComponent(product.sapCode),
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
                        
                        product.updateCompletedPackages()
                        networkManager?.saveTask(task)
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
                            
                            var totalDownloaded: Int64 = 0
                            var totalSize: Int64 = 0
                            var currentSpeed: Double = 0
                            
                            for prod in task.productsToDownload {
                                for pkg in prod.packages {
                                    totalSize += pkg.downloadSize
                                    if pkg.downloaded {
                                        totalDownloaded += pkg.downloadSize
                                    } else if pkg.id == package.id {
                                        totalDownloaded += totalBytesWritten
                                        currentSpeed = speed
                                    }
                                }
                            }
                            
                            task.totalSize = totalSize
                            task.totalDownloadedSize = totalDownloaded
                            task.totalProgress = totalSize > 0 ? Double(totalDownloaded) / Double(totalSize) : 0
                            task.totalSpeed = currentSpeed
                            
                            lastUpdateTime = now
                            lastBytes = totalBytesWritten
                            
                            networkManager?.objectWillChange.send()
                        }
                    }
                }
            )
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            
            Task {
                let downloadTask: URLSessionDownloadTask
                if let resumeData = resumeData {
                    downloadTask = session.downloadTask(withResumeData: resumeData)
                } else if let url = url {
                    var request = URLRequest(url: url)
                    NetworkConstants.downloadHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                    downloadTask = session.downloadTask(with: request)
                } else {
                    continuation.resume(throwing: NetworkError.invalidData("Neither URL nor resume data provided"))
                    return
                }
                
                await cancelTracker.registerTask(task.id, task: downloadTask, session: session)
                await cancelTracker.clearResumeData(task.id)
                downloadTask.resume()
            }
        }
    }

    private func startDownloadProcess(task: NewDownloadTask) async {
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

        let driverPath = task.directory.appendingPathComponent("driver.xml")
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
            let productDir = task.directory.appendingPathComponent(product.sapCode)
            if !FileManager.default.fileExists(atPath: productDir.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: productDir,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                } catch {
                    print("Error creating directory for \(product.sapCode): \(error)")
                    continue
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
                    networkManager?.saveTask(task)
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
                    if let resumeData = await cancelTracker.getResumeData(task.id) {
                        try await downloadPackage(package: package, task: task, product: product, resumeData: resumeData)
                    } else {
                        try await downloadPackage(package: package, task: task, product: product, url: url)
                    }
                } catch {
                    print("Error downloading package \(package.fullPackageName): \(error.localizedDescription)")
                    await handleError(task.id, error)
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
                networkManager?.saveTask(task)
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
            fullPackageName: "Adobe Downloader \(task.sapCode)_\(productInfo.productVersion)_\(productInfo.apPlatform).dmg",
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
                    message: String(localized: "正在处理 \(product.sapCode) 的包信息..."),
                    timestamp: Date(),
                    stage: .fetchingInfo
                )))
            }

            let productDir = task.directory.appendingPathComponent("\(product.sapCode)")
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
            throw NetworkError.invalidData(String(localized: "无法将响应数据转换为json字符串"))
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
                        .appendingPathComponent("\(task.sapCode)")
                    let fileURL = destinationDir.appendingPathComponent(currentPackage.fullPackageName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
                
                networkManager?.saveTask(task)
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
                    return (String(localized: "网络连接已断开"), true)
            case .timeout:
                return (String(localized: "下载超时"), true)
            case .serverUnreachable:
                return (String(localized: "服务器无法访问"), true)
            case .insufficientStorage:
                return (String(localized: "存储空间不足"), false)
            case .filePermissionDenied:
                return (String(localized: "没有写入权限"), false)
            default:
                return (networkError.localizedDescription, false)
            }
        case let urlError as URLError:
            switch urlError.code {
            case .notConnectedToInternet:
                return (String(localized: "网络连接已断开"), true)
            case .timedOut:
                return (String(localized: "连接超时"), true)
            case .cancelled:
                return (String(localized: "下载已取消"), false)
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

    func downloadSetupComponents(
        progressHandler: @escaping (Double, String) -> Void,
        cancellationHandler: @escaping () -> Bool
    ) async throws {
        let architecture = AppStatics.isAppleSilicon ? "arm" : "intel"
        let baseURLs = [
            "https://github.com/X1a0He/Adobe-Downloader/raw/refs/heads/main/X1a0HeCC/\(architecture)/HDBox/",
            "https://github.com/X1a0He/Adobe-Downloader/raw/refs/heads/develop/X1a0HeCC/\(architecture)/HDBox/"
        ]
        
        let components = [
            "HDHelper",
            "HDIM.dylib",
            "HDPIM.dylib",
            "HUM.dylib",
            "Setup"
        ]
        
        let targetDirectory = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox"
        
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration)

        for (index, component) in components.enumerated() {
            if cancellationHandler() {
                try? FileManager.default.removeItem(at: tempDirectory)
                throw NetworkError.cancelled
            }
            
            await MainActor.run {
                progressHandler(Double(index) / Double(components.count), "正在下载 \(component)...")
            }
            
            var lastError: Error? = nil
            var downloaded = false
            
            for baseURL in baseURLs {
                guard !downloaded else { break }
                if cancellationHandler() {
                    try? FileManager.default.removeItem(at: tempDirectory)
                    throw NetworkError.cancelled
                }
                
                let url = URL(string: baseURL + component)!
                let destinationURL = tempDirectory.appendingPathComponent(component)
                print(url)
                do {
                    let (downloadURL, response) = try await session.download(from: url)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NetworkError.invalidResponse
                    }
                    
                    if httpResponse.statusCode == 404 {
                        lastError = NetworkError.fileNotFound(component)
                        continue
                    }
                    
                    if !(200...299).contains(httpResponse.statusCode) {
                        lastError = NetworkError.httpError(httpResponse.statusCode, "下载 \(component) 失败")
                        continue
                    }
                    
                    try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
                    downloaded = true
                    
                } catch URLError.timedOut {
                    lastError = NetworkError.timeout
                    continue
                } catch {
                    lastError = error is NetworkError ? error : NetworkError.downloadError("下载 \(component) 失败: \(error.localizedDescription)", error)
                    continue
                }
            }
            
            if !downloaded {
                try? FileManager.default.removeItem(at: tempDirectory)
                throw lastError ?? NetworkError.downloadError("无法下载 \(component)", nil)
            }
        }
        
        await MainActor.run {
            progressHandler(1.0, "下载完成，正在安装...")
        }

        let bashScript = """
function hex() {
    echo \\"$1\\" | perl -0777pe 's|([0-9a-zA-Z]{2}+(?![^\\\\(]*\\\\)))|\\\\\\\\x${1}|gs'
}

function replace() {
    declare -r dom=$(hex \\"$2\\")
    declare -r sub=$(hex \\"$3\\")
    perl -0777pi -e 'BEGIN{$/=\\\\1e8} s|'$dom'|'$sub'|gs' \\"$1\\"
}

function prep() {
    codesign --remove-signature \\"$1\\"
    codesign -f -s - --timestamp=none --all-architectures --deep \\"$1\\"
    xattr -cr \\"$1\\"
}

cp \\"\(targetDirectory)/Setup\\" \\"\(targetDirectory)/Setup.original\\" &&
replace \\"\(targetDirectory)/Setup\\" \\"554889E553504889FB488B0570C70300488B00488945F0E824D7FEFF4883C3084839D80F\\" \\"6A0158C353504889FB488B0570C70300488B00488945F0E824D7FEFF4883C3084839D80F\\" &&
replace \\"\(targetDirectory)/Setup\\" \\"FFC300D1F44F01A9FD7B02A9FD830091F30300AA1F2003D568A11D58080140F9E80700F9\\" \\"200080D2C0035FD6FD7B02A9FD830091F30300AA1F2003D568A11D58080140F9E80700F9\\" &&
prep \\"\(targetDirectory)/Setup\\"
"""

        let script = """
        tell application "System Events"
            set thePassword to text returned of (display dialog "请输入管理员密码以继续安装" default answer "" with hidden answer buttons {"取消", "确定"} default button "确定" with icon caution with title "需要管理员权限")
            do shell script "cat > /tmp/setup_script.sh << 'EOL'
        \(bashScript)
        EOL
        chmod +x /tmp/setup_script.sh &&
        mkdir -p '\(targetDirectory)' && 
        chmod 755 '\(targetDirectory)' && 
        cp -f '\(tempDirectory.path)/'* '\(targetDirectory)/' && 
        chmod 755 '\(targetDirectory)/'* && 
        chown -R root:wheel '\(targetDirectory)' &&
        /tmp/setup_script.sh &&
        rm -f /tmp/setup_script.sh" password thePassword with administrator privileges
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            
            try? FileManager.default.removeItem(at: tempDirectory)
            
            if let error = error {
                if let errorMessage = error["NSAppleScriptErrorMessage"] as? String,
                   errorMessage.contains("User canceled") {
                    throw NSError(domain: "SetupComponentsError",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "用户取消了操作"])
                }
                throw NSError(domain: "SetupComponentsError",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "安装组件失败: \(error)"])
            }

            ModifySetup.clearVersionCache()
            
            await MainActor.run {
                progressHandler(1.0, "安装完成")
            }
        } else {
            throw NSError(domain: "SetupComponentsError",
                         code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "创建安装脚本失败"])
        }
    }
}
