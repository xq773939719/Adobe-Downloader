import Foundation
import os.log

@objc(HelperToolProtocol) protocol HelperToolProtocol {
    func executeCommand(_ command: String, withReply reply: @escaping (String) -> Void)
    func startInstallation(_ command: String, withReply reply: @escaping (String) -> Void)
    func getInstallationOutput(withReply reply: @escaping (String) -> Void)
}

class HelperTool: NSObject, HelperToolProtocol {
    private let listener: NSXPCListener
    private var connections: Set<NSXPCConnection> = []
    private var currentTask: Process?
    private var outputPipe: Pipe?
    private let logger = Logger(subsystem: "com.x1a0he.macOS.Adobe-Downloader.helper", category: "Helper")

    override init() {
        listener = NSXPCListener(machServiceName: "com.x1a0he.macOS.Adobe-Downloader.helper")
        super.init()
        listener.delegate = self
        logger.notice("HelperTool 初始化完成")
    }
    
    func run() {
        logger.notice("Helper 服务开始运行")
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Helper is running")

        listener.resume()
        logger.notice("XPC Listener 已启动")

        RunLoop.current.run()
    }

    func executeCommand(_ command: String, withReply reply: @escaping (String) -> Void) {
        logger.notice("收到命令执行请求: \(command, privacy: .public)")
        
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        do {
            try task.run()
            logger.debug("命令开始执行: \(command, privacy: .public)")
        } catch {
            let errorMsg = "Error: \(error.localizedDescription)"
            logger.error("执行失败: \(errorMsg, privacy: .public)")
            reply(errorMsg)
            return
        }

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.logger.debug("命令输出: \(trimmedOutput, privacy: .public)")
                reply(trimmedOutput)
            }
        }

        let errorHandle = errorPipe.fileHandleForReading
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let errorOutput = String(data: data, encoding: .utf8), !errorOutput.isEmpty {
                self.logger.error("命令错误输出: \(errorOutput, privacy: .public)")
            }
        }

        task.terminationHandler = { process in
            self.logger.debug("命令执行完成，退出码: \(process.terminationStatus, privacy: .public)")
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
        }
    }

    func startInstallation(_ command: String, withReply reply: @escaping (String) -> Void) {
        logger.notice("收到安装请求: \(command, privacy: .public)")
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        task.terminationHandler = { [weak self] process in
            guard let self = self else { return }
            self.logger.notice("Setup 进程终止，退出码: \(process.terminationStatus, privacy: .public)")
            if let pipe = self.outputPipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
            self.currentTask = nil
            self.outputPipe = nil
        }
        
        currentTask = task
        outputPipe = pipe
        
        do {
            try task.run()
            logger.notice("Setup 进程已启动")
            reply("Started")
        } catch {
            logger.error("启动安装失败: \(error.localizedDescription, privacy: .public)")
            currentTask = nil
            outputPipe = nil
            reply("Error: \(error.localizedDescription)")
        }
    }
    
    func getInstallationOutput(withReply reply: @escaping (String) -> Void) {
        guard let pipe = outputPipe else {
            reply("")
            return
        }
        
        let data = pipe.fileHandleForReading.availableData
        if data.isEmpty {
            if let task = currentTask, !task.isRunning {
                logger.notice("Setup 进程已结束")
                currentTask = nil
                outputPipe = nil
                reply("Completed")
            } else {
                reply("")
            }
            return
        }
        
        if let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            if !lines.isEmpty {
                logger.notice("Setup 实时输出: \(lines, privacy: .public)")
                reply(lines)
            } else {
                reply("")
            }
        } else {
            reply("")
        }
    }

    func cleanup() {
        if let pipe = outputPipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        currentTask?.terminate()
        currentTask = nil
        outputPipe = nil
    }
}

extension HelperTool: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        newConnection.exportedObject = self
        
        newConnection.invalidationHandler = { [weak self] in
            self?.connections.remove(newConnection)
        }
        
        connections.insert(newConnection)
        newConnection.resume()
        
        return true
    }
}

autoreleasepool {
    let helperTool = HelperTool()
    helperTool.run()
}
