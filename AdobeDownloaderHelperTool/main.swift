//
//  main.swift
//  AdobeDownloaderHelperTool
//
//  Created by X1a0He on 11/12/24.
//

import Foundation

@objc(HelperToolProtocol) protocol HelperToolProtocol {
    func executeCommand(_ command: String, withReply reply: @escaping (String) -> Void)
}

class HelperTool: NSObject, HelperToolProtocol {
    private let listener: NSXPCListener
    private var connections: Set<NSXPCConnection> = []
    
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
        print("[Adobe Downloader Helper] 当前进程权限: \(geteuid())")

        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        
        do {
            print("[Adobe Downloader Helper] 开始执行命令")
            try task.run()
            task.waitUntilExit()
            
            let status = task.terminationStatus
            print("[Adobe Downloader Helper] 命令执行完成，退出状态: \(status)")

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[Adobe Downloader Helper] 命令执行成功，输出: \(trimmedOutput)")
                reply(trimmedOutput)
            } else {
                print("[Adobe Downloader Helper] 无法解码命令输出")
                reply("Error: Could not decode command output")
            }
        } catch {
            print("[Adobe Downloader Helper] 命令执行失败: \(error)")
            reply("Error: \(error.localizedDescription)")
        }
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

