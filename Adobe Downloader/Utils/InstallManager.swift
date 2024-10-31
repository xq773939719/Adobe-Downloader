//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

actor InstallManager {
    enum InstallError: Error {
        case setupNotFound
        case installationFailed(String)
        case cancelled
        case permissionDenied
    }
    
    private var installationProcess: Process?
    private var progressHandler: ((Double, String) -> Void)?
    
    func install(at appPath: URL, progressHandler: @escaping (Double, String) -> Void) async throws {
        self.progressHandler = progressHandler
        
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
        let driverPath = appPath.appendingPathComponent("Contents/Resources/products/driver.xml").path
        
        guard FileManager.default.fileExists(atPath: setupPath) else {
            throw InstallError.setupNotFound
        }

        let authProcess = Process()
        authProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let authScript = """
        tell application "System Events"
            display dialog "请输入管理员密码以继续安装" default answer "" with hidden answer ¬
                buttons {"取消", "确定"} default button "确定" ¬
                with icon caution ¬
                with title "需要管理员权限"
            if button returned of result is "确定" then
                return text returned of result
            else
                return ""
            end if
        end tell
        """
        
        let authPipe = Pipe()
        authProcess.standardOutput = authPipe
        authProcess.arguments = ["-e", authScript]
        
        try authProcess.run()
        authProcess.waitUntilExit()
        
        guard let passwordData = try? authPipe.fileHandleForReading.readToEnd(),
              let password = String(data: passwordData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !password.isEmpty else {
            throw InstallError.permissionDenied
        }

        let installProcess = Process()
        installProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        installProcess.arguments = ["-S", setupPath, "--install=1", "--driverXML=\(driverPath)"]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        installProcess.standardInput = inputPipe
        installProcess.standardOutput = outputPipe
        installProcess.standardError = outputPipe

        Task {
            do {
                for try await line in outputPipe.fileHandleForReading.bytes.lines {
                    // print("Install output:", line)
                    if let progress = parseProgress(from: line) {
                        await MainActor.run {
                            progressHandler(progress.progress, progress.status)
                        }
                    }
                }
            } catch {
                print("Error reading output:", error)
            }
        }

        installationProcess = installProcess
        
        do {
            await MainActor.run {
                progressHandler(0.0, "正在准备安装...")
            }

            try installProcess.run()

            try inputPipe.fileHandleForWriting.write(contentsOf: "\(password)\n".data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task.detached {
                    installProcess.waitUntilExit()

                    let terminationStatus = installProcess.terminationStatus
                    if terminationStatus != 0 {
                        if let errorData = try? outputPipe.fileHandleForReading.readToEnd(),
                           let errorOutput = String(data: errorData, encoding: .utf8) {
                            continuation.resume(throwing: InstallError.installationFailed("安装失败 (退出代码: \(terminationStatus)): \(errorOutput)"))
                        } else {
                            continuation.resume(throwing: InstallError.installationFailed("安装失败 (退出代码: \(terminationStatus))"))
                        }
                    } else {
                        continuation.resume()
                    }
                }
            }

            await MainActor.run {
                progressHandler(1.0, "安装完成")
            }
        } catch {
            if case InstallError.cancelled = error {
                throw error
            }
            throw InstallError.installationFailed(error.localizedDescription)
        }
    }
    
    func cancel() {
        installationProcess?.terminate()
    }
    
    private func parseProgress(from line: String) -> (progress: Double, status: String)? {
        if let range = line.range(of: "Exit Code: ([0-9]+)", options: .regularExpression),
           let codeStr = line[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
           let exitCode = Int(codeStr) {
            if exitCode == 0 {
                return (1.0, "安装完成")
            } else {
                return nil
            }
        }

        if let range = line.range(of: "Progress: ([0-9]{1,3})%", options: .regularExpression),
           let progressStr = line[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
           let progressValue = Double(progressStr.replacingOccurrences(of: "%", with: "")) {
            return (progressValue / 100.0, "正在安装...")
        }

        if line.contains("Installing packages") {
            return (0.0, "正在安装包...")
        } else if line.contains("Preparing") {
            return (0.0, "正在准备...")
        }
        
        return nil
    }
} 

