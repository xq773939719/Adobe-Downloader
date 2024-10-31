//
//  Adobe-Downloader
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
                    print("File size verification - Expected: \(downloadTask.countOfBytesExpectedToReceive), Actual: \(fileSize)")

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
    }

    func pauseDownloadTask(taskId: UUID, reason: DownloadTask.DownloadStatus.PauseInfo.PauseReason = .userRequested) async {
        await cancelTracker.pause(taskId)
        await networkManager?.setTaskStatus(taskId, .paused(DownloadTask.DownloadStatus.PauseInfo(
            reason: reason,
            timestamp: Date(),
            resumable: true
        )))
    }
    
    func resumeDownloadTask(taskId: UUID) async {
        guard let networkManager = networkManager,
              let task = await networkManager.getTasks().first(where: { $0.id == taskId }) else { return }

        if let activeId = await networkManager.getActiveTaskId(), activeId != taskId {
            await cancelTracker.cancel(activeId)
        }

        guard let packageIndex = task.packages.firstIndex(where: { !$0.downloaded }) else {
            await networkManager.setTaskStatus(taskId, .completed(DownloadTask.DownloadStatus.CompletionInfo(
                timestamp: Date(),
                totalTime: Date().timeIntervalSince(task.startTime),
                totalSize: task.totalSize
            )))
            return
        }

        let package = task.packages[packageIndex]

        let delegate = DownloadDelegate(
            destinationDirectory: task.destinationURL.appendingPathComponent("Contents/Resources/products/\(task.sapCode)"),
            fileName: package.Path.components(separatedBy: "/").last ?? "",
            completionHandler: { [weak networkManager] localURL, response, error in
                guard let networkManager = networkManager else { return }
                
                Task {
                    if let error = error {
                        await networkManager.handleError(taskId, error)
                        return
                    }
                    
                    if let localURL = localURL {
                        do {
                            let fileSize = try FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0
                            guard fileSize >= package.size else {
                                throw NetworkError.dataValidationError("文件大小不正确")
                            }

                            await networkManager.handleDownloadCompletion(taskId: taskId, packageIndex: packageIndex)
                        } catch {
                            print("File validation error: \(error.localizedDescription)")
                            await networkManager.handleError(taskId, error)
                        }
                    }
                }
            },
            progressHandler: { [weak networkManager] bytesWritten, totalBytesWritten, totalBytesExpectedToWrite in
                guard let networkManager = networkManager else { return }
                
                Task { @MainActor in
                    networkManager.updateDownloadProgress(for: taskId, progress: (
                        bytesWritten: bytesWritten,
                        totalWritten: totalBytesWritten,
                        expectedToWrite: totalBytesExpectedToWrite
                    ))
                }
            }
        )

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = NetworkConstants.downloadTimeout
        config.timeoutIntervalForRequest = NetworkConstants.downloadTimeout

        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        var downloadTask: URLSessionDownloadTask

        if let resumeData = await cancelTracker.getResumeData(taskId) {
            downloadTask = session.downloadTask(withResumeData: resumeData)
        } else {
            let downloadURL: String
            if task.sapCode == "APRO" {
                downloadURL = await package.Path.hasPrefix("https://") ? package.Path : networkManager.cdn + package.Path
            } else {
                downloadURL = await networkManager.cdn + package.Path
            }

            guard let url = URL(string: downloadURL) else {
                await networkManager.handleError(taskId, NetworkError.invalidURL(downloadURL))
                return
            }
            
            var request = URLRequest(url: url)
            NetworkConstants.downloadHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

            downloadTask = session.downloadTask(with: request)
        }
        
        await cancelTracker.registerTask(taskId, task: downloadTask, session: session)

        await networkManager.setTaskStatus(taskId, .downloading(DownloadTask.DownloadStatus.DownloadInfo(
            fileName: package.name,
            currentPackageIndex: packageIndex,
            totalPackages: task.packages.count,
            startTime: Date(),
            estimatedTimeRemaining: nil
        )))
        
        downloadTask.resume()
    }
    
    func cancelDownloadTask(taskId: UUID, removeFiles: Bool = false) async {
        await cancelTracker.cancel(taskId)

        if removeFiles {
            if let task = await networkManager?.getTasks().first(where: { $0.id == taskId }) {
                try? FileManager.default.removeItem(at: task.destinationURL)
            }
        }
        
        await networkManager?.setTaskStatus(taskId, .failed(DownloadTask.DownloadStatus.FailureInfo(
            message: "下载已取消",
            error: NetworkError.downloadCancelled,
            timestamp: Date(),
            recoverable: false
        )))
    }
    
    func downloadAPRO(task: DownloadTask, productInfo: Product.ProductVersion) async throws {
        guard let networkManager = networkManager else { return }

        let manifestURL = await networkManager.cdnUrl + productInfo.buildGuid
        print("Manifest URL:", manifestURL)
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

        await MainActor.run {
            if let index = networkManager.downloadTasks.firstIndex(where: { $0.id == task.id }) {
                networkManager.downloadTasks[index].packages = [
                    DownloadTask.Package(
                        name: "Acrobat_DC_Web_WWMUI.dmg",
                        Path: downloadPath,
                        size: assetSize,
                        downloadedSize: 0,
                        progress: 0,
                        speed: 0,
                        status: .waiting,
                        type: "core",
                        downloaded: false,
                        lastUpdated: Date(),
                        lastRecordedSize: 0
                    )
                ]
                networkManager.downloadTasks[index].totalSize = assetSize
            }
        }

        await networkManager.resumeDownload(taskId: task.id)
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

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")

        let tempScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("installer.js")
        try NetworkConstants.INSTALL_APP_APPLE_SCRIPT.write(to: tempScriptURL, atomically: true, encoding: .utf8)

        process.arguments = [
            "-l", "JavaScript",
            "-o", destinationURL.path,
            tempScriptURL.path
        ]
        
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NetworkError.fileSystemError(
                "Failed to create installer app: Exit code \(process.terminationStatus)",
                nil
            )
        }
        
        try? FileManager.default.removeItem(at: tempScriptURL)

        let iconDestination = destinationURL.appendingPathComponent("Contents/Resources/applet.icns")
        if FileManager.default.fileExists(atPath: iconDestination.path) {
            try FileManager.default.removeItem(at: iconDestination)
        }
        
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
    
    func generateDriverXML(sapCode: String, version: String, language: String,
                         productInfo: Product.ProductVersion, displayName: String) -> String {
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
            
            print("Successfully cleared extended attributes for \(url.path)")
        } catch {
            print("Error executing xattr command:", error.localizedDescription)
        }
    }
}
