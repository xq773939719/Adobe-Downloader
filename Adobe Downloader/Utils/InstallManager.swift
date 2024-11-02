//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

actor InstallManager {
    enum InstallError: LocalizedError {
        case setupNotFound
        case installationFailed(String)
        case cancelled
        case permissionDenied
        
        var errorDescription: String? {
            switch self {
            case .setupNotFound:
                return "找不到安装程序"
            case .installationFailed(let message):
                return message
            case .cancelled:
                return "安装已取消"
            case .permissionDenied:
                return "权限被拒绝"
            }
        }
        
        static func == (lhs: InstallError, rhs: InstallError) -> Bool {
            switch (lhs, rhs) {
            case (.setupNotFound, .setupNotFound):
                return true
            case (.cancelled, .cancelled):
                return true
            case (.permissionDenied, .permissionDenied):
                return true
            case (.installationFailed(let lhsMessage), .installationFailed(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
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
                error "用户取消了操作"
            end if
        end tell
        """
        
        let authPipe = Pipe()
        authProcess.standardOutput = authPipe
        authProcess.standardError = Pipe()
        authProcess.arguments = ["-e", authScript]
        
        do {
            try authProcess.run()
            authProcess.waitUntilExit()
            
            if authProcess.terminationStatus != 0 {
                throw InstallError.cancelled
            }
            
            guard let passwordData = try? authPipe.fileHandleForReading.readToEnd(),
                  let password = String(data: passwordData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !password.isEmpty else {
                throw InstallError.cancelled
            }

            let installProcess = Process()
            installProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            installProcess.arguments = ["-S", setupPath, "--install=1", "--driverXML=\(driverPath)"]

            print("执行安装命令: \(installProcess.executableURL!.path) \(installProcess.arguments!.joined(separator: " "))")

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            installProcess.standardInput = inputPipe
            installProcess.standardOutput = outputPipe
            installProcess.standardError = outputPipe

            var installationOutput = ""
            installationProcess = installProcess

            await MainActor.run {
                progressHandler(0.0, "正在准备安装...")
            }

            try installProcess.run()
            try inputPipe.fileHandleForWriting.write(contentsOf: "\(password)\n".data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task.detached {
                    do {
                        for try await line in outputPipe.fileHandleForReading.bytes.lines {
                            print("Install output:", line)
                            installationOutput += line + "\n"
                            
                            if line.contains("incorrect password") || line.contains("sudo: 1 incorrect password attempt") {
                                installProcess.terminate()
                                continuation.resume(throwing: InstallError.permissionDenied)
                                return
                            }
                            
                            if let range = line.range(of: "Exit Code: (-?[0-9]+)", options: .regularExpression),
                               let codeStr = line[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                               let code = Int32(codeStr) {
                                if code != 0 {
                                    let errorMessage = code == -1 
                                        ? "安装程序调用失败，请联系X1a0He"
                                        : "(退出代码: \(code))"
                                    
                                    installProcess.terminate()
                                    continuation.resume(throwing: InstallError.installationFailed(errorMessage))
                                    return
                                }
                            }
                            
                            if let progress = await self.parseProgress(from: line) {
                                await MainActor.run {
                                    progressHandler(progress.progress, progress.status)
                                }
                            }
                        }
                        
                        installProcess.waitUntilExit()
                        
                        if installProcess.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: InstallError.installationFailed(
                                "安装失败 (退出代码: \(installProcess.terminationStatus))"
                            ))
                        }
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            await MainActor.run {
                progressHandler(1.0, "安装完成")
            }

        } catch {
            if error.localizedDescription.contains("用户取消了操作") {
                throw InstallError.cancelled
            }
            if let installError = error as? InstallError {
                throw installError
            }
            throw InstallError.installationFailed(error.localizedDescription)
        }
    }
    
    func cancel() {
        installationProcess?.terminate()
    }
    
    private func parseProgress(from line: String) -> (progress: Double, status: String)? {
        if let range = line.range(of: "Exit Code: (-?[0-9]+)", options: .regularExpression),
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

    // 添加新的重试方法
    func retry(at appPath: URL, progressHandler: @escaping (Double, String) -> Void) async throws {
        self.progressHandler = progressHandler
        
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
        let driverPath = appPath.appendingPathComponent("Contents/Resources/products/driver.xml").path
        
        guard FileManager.default.fileExists(atPath: setupPath) else {
            throw InstallError.setupNotFound
        }

        let installProcess = Process()
        installProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        installProcess.arguments = [setupPath, "--install=1", "--driverXML=\(driverPath)"]

        print("执行重试命令: \(installProcess.executableURL!.path) \(installProcess.arguments!.joined(separator: " "))")

        let outputPipe = Pipe()
        installProcess.standardOutput = outputPipe
        installProcess.standardError = outputPipe

        var installationOutput = ""
        installationProcess = installProcess

        await MainActor.run {
            progressHandler(0.0, "正在重试安装...")
        }

        try installProcess.run()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached {
                do {
                    for try await line in outputPipe.fileHandleForReading.bytes.lines {
                        print("Install output:", line)
                        installationOutput += line + "\n"
                        
                        if let range = line.range(of: "Exit Code: (-?[0-9]+)", options: .regularExpression),
                           let codeStr = line[range].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
                           let code = Int32(codeStr) {
                            if code != 0 {
                                let errorMessage = code == -1 
                                    ? "安装程序调用失败，请联系X1a0He"
                                    : "(退出代码: \(code))"
                                
                                installProcess.terminate()
                                continuation.resume(throwing: InstallError.installationFailed(errorMessage))
                                return
                            }
                        }
                        
                        if let progress = await self.parseProgress(from: line) {
                            await MainActor.run {
                                progressHandler(progress.progress, progress.status)
                            }
                        }
                    }
                    
                    installProcess.waitUntilExit()
                    
                    if installProcess.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        // 如果重试失败，抛出错误让外层处理
                        throw InstallError.installationFailed(
                            "重试失败，需要重新输入密码"
                        )
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        await MainActor.run {
            progressHandler(1.0, "安装完成")
        }
    }
} 

