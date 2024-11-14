//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
/*
    Adobe Exit Code
    107: 架构或者版本不一致
    103: 权限问题
    182: 可能是文件不全或者出错了
 */
import Foundation

actor InstallManager {
    enum InstallError: Error, LocalizedError {
        case setupNotFound
        case installationFailed(String)
        case cancelled
        case permissionDenied
        
        var errorDescription: String? {
            switch self {
                case .setupNotFound: return String(localized: "找不到安装程序")
                case .installationFailed(let message): return message
                case .cancelled: return String(localized: "安装已取消")
                case .permissionDenied: return String(localized: "权限被拒绝")
            }
        }
    }
    
    private var installationProcess: Process?
    private var progressHandler: ((Double, String) -> Void)?
    private let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
    
    private func executeInstallation(
        at appPath: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: setupPath) else {
            throw InstallError.setupNotFound
        }

        let driverPath = appPath.appendingPathComponent("driver.xml").path
        let installCommand = "\"\(setupPath)\" --install=1 --driverXML=\"\(driverPath)\""
        
        await MainActor.run {
            progressHandler(0.0, String(localized: "正在准备安装..."))
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached {
                do {
                    try await PrivilegedHelperManager.shared.executeInstallation(installCommand) { output in
                        Task { @MainActor in
                            if let range = output.range(of: "Exit Code: (-?[0-9]+)", options: .regularExpression),
                               let codeStr = output[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                               let exitCode = Int(codeStr) {
                                
                                if exitCode == 0 {
                                    progressHandler(1.0, String(localized: "安装完成"))
                                    PrivilegedHelperManager.shared.executeCommand("pkill -f Setup") { _ in }
                                    continuation.resume()
                                } else {
                                    let errorMessage: String
                                    switch exitCode {
                                    case 107:
                                            errorMessage = String(localized: "安装失败: 架构或版本不一致 (退出代码: \(exitCode))")
                                    case 103:
                                        errorMessage = String(localized: "安装失败: 权限问题 (退出代码: \(exitCode))")
                                    case 182:
                                        errorMessage = String(localized: "安装失败: 安装文件不完整或损坏 (退出代码: \(exitCode))")
                                    case -1:
                                        errorMessage = String(localized: "安装失败: Setup 组件未被处理 (退出代码: \(exitCode))")
                                    default:
                                        errorMessage = String(localized: "安装失败 (退出代码: \(exitCode))")
                                    }
                                    progressHandler(0.0, errorMessage)
                                    continuation.resume(throwing: InstallError.installationFailed(errorMessage))
                                }
                                return
                            }

                            if let progress = await self.parseProgress(from: output) {
                                progressHandler(progress, String(localized: "正在安装..."))
                            }
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func parseProgress(from output: String) -> Double? {
        if let range = output.range(of: "Progress: ([0-9]{1,3})%", options: .regularExpression),
           let progressStr = output[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
           let progressValue = Double(progressStr.replacingOccurrences(of: "%", with: "")) {
            return progressValue / 100.0
        }
        return nil
    }
    
    func install(
        at appPath: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        try await executeInstallation(
            at: appPath,
            progressHandler: progressHandler
        )
    }
    
    func cancel() {
        PrivilegedHelperManager.shared.executeCommand("pkill -f Setup") { _ in }
    }

    func getInstallCommand(for driverPath: String) -> String {
        return "sudo \"\(setupPath)\" --install=1 --driverXML=\"\(driverPath)\""
    }

    func retry(
        at appPath: URL,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        try await executeInstallation(
            at: appPath,
            progressHandler: progressHandler
        )
    }
}

