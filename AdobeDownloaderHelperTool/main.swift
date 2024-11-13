//
//  main.swift
//  AdobeDownloaderHelperTool
//
//  Created by X1a0He on 11/12/24.
//

import Foundation

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
    
    override init() {
        listener = NSXPCListener(machServiceName: "com.x1a0he.macOS.Adobe-Downloader.helper")
        super.init()
        listener.delegate = self
    }
    
    func run() {
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Helper is running")

        listener.resume()

        RunLoop.current.run()
    }

    func executeCommand(_ command: String, withReply reply: @escaping (String) -> Void) {
        print("[Adobe Downloader Helper] 收到执行命令请求: \(command)")
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/sh")

        currentTask = task

        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                reply(output.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                reply("Error: Could not decode command output")
            }
        } catch {
            reply("Error: \(error.localizedDescription)")
        }
        
        currentTask = nil
    }
    
    func startInstallation(_ command: String, withReply reply: @escaping (String) -> Void) {
        print("[Adobe Downloader Helper] 收到安装请求: \(command)")
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        currentTask = task
        outputPipe = pipe
        
        do {
            try task.run()
            reply("Started")
        } catch {
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
                reply(lines)
            } else {
                reply("")
            }
        } else {
            reply("")
        }
    }
    
    func terminateCurrentTask() {
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

print("[Adobe Downloader Helper] 开始启动...")

autoreleasepool {
    print("[Adobe Downloader Helper] 初始化 HelperTool...")
    let helperTool = HelperTool()
    
    print("[Adobe Downloader Helper] 运行 Helper 服务...")
    helperTool.run()
}

