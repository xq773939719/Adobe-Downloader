//
//  ModifySetup.swift
//  Adobe Downloader
//
//  Created by X1a0He on 11/5/24.
//

import Foundation
import SwiftUI

class ModifySetup {
    private static var cachedVersion: String?

    static func isSetupExists() -> Bool {
        return FileManager.default.fileExists(atPath: "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup")
    }

    static func isSetupBackup() -> Bool {
        return FileManager.default.fileExists(atPath: "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup.original")
    }

    static func checkComponentVersion() -> String {
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"

        guard isSetupExists() else {
            cachedVersion = nil
            return String(localized: "未找到 Setup 组件")
        }

        if let cachedVersion = cachedVersion {
            return cachedVersion
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
        process.arguments = [setupPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if let output = try pipe.fileHandleForReading.readToEnd(),
               let outputString = String(data: output, encoding: .utf8) {
                let lines = outputString.components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() {
                    if line == "Adobe Setup Version: %s" && index + 1 < lines.count {
                        let version = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                        if version.range(of: "^[0-9.]+$", options: .regularExpression) != nil {
                            cachedVersion = version
                            return version
                        }
                    }
                }
            }

            let message = String(localized: "未知 Setup 组件版本号")
            cachedVersion = message
            return message
        } catch {
            print("Error checking Setup version: \(error)")
            let message = String(localized: "未知 Setup 组件版本号")
            cachedVersion = message
            return message
        }
    }

    static func clearVersionCache() {
        cachedVersion = nil
    }

    static func backupSetupFile(completion: @escaping (Bool) -> Void) {
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
        let backupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup.original"

        if isSetupBackup() {
            let command = "cp '\(backupPath)' '\(setupPath)'"
            PrivilegedHelperManager.shared.executeCommand(command) { result in
                completion(!result.starts(with: "Error:"))
            }
        } else {
            let command = "cp '\(setupPath)' '\(backupPath)'"
            PrivilegedHelperManager.shared.executeCommand(command) { result in
                completion(!result.starts(with: "Error:"))
            }
        }
    }

    static func modifySetupFile(completion: @escaping (Bool) -> Void) {
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"

        let commands = [
            """
            perl -0777pi -e 'BEGIN{$/=\\1e8} s|\\x55\\x48\\x89\\xE5\\x53\\x50\\x48\\x89\\xFB\\x48\\x8B\\x05\\x70\\xC7\\x03\\x00\\x48\\x8B\\x00\\x48\\x89\\x45\\xF0\\xE8\\x24\\xD7\\xFE\\xFF\\x48\\x83\\xC3\\x08\\x48\\x39\\xD8\\x0F|\\x6A\\x01\\x58\\xC3\\x53\\x50\\x48\\x89\\xFB\\x48\\x8B\\x05\\x70\\xC7\\x03\\x00\\x48\\x8B\\x00\\x48\\x89\\x45\\xF0\\xE8\\x24\\xD7\\xFE\\xFF\\x48\\x83\\xC3\\x08\\x48\\x39\\xD8\\x0F|gs' '\(setupPath)'
            """,
            """
            perl -0777pi -e 'BEGIN{$/=\\1e8} s|\\xFF\\xC3\\x00\\xD1\\xF4\\x4F\\x01\\xA9\\xFD\\x7B\\x02\\xA9\\xFD\\x83\\x00\\x91\\xF3\\x03\\x00\\xAA\\x1F\\x20\\x03\\xD5\\x68\\xA1\\x1D\\x58\\x08\\x01\\x40\\xF9\\xE8\\x07\\x00\\xF9|\\x20\\x00\\x80\\xD2\\xC0\\x03\\x5F\\xD6\\xFD\\x7B\\x02\\xA9\\xFD\\x83\\x00\\x91\\xF3\\x03\\x00\\xAA\\x1F\\x20\\x03\\xD5\\x68\\xA1\\x1D\\x58\\x08\\x01\\x40\\xF9\\xE8\\x07\\x00\\xF9|gs' '\(setupPath)'
            """,
            "codesign --remove-signature '\(setupPath)'",
            "codesign -f -s - --timestamp=none --all-architectures --deep '\(setupPath)'",
            "xattr -cr '\(setupPath)'"
        ]

        func executeNextCommand(_ index: Int) {
            guard index < commands.count else {
                completion(true)
                return
            }

            PrivilegedHelperManager.shared.executeCommand(commands[index]) { result in
                if result.starts(with: "Error:") {
                    print("Command failed: \(commands[index])")
                    completion(false)
                    return
                }
                executeNextCommand(index + 1)
            }
        }

        executeNextCommand(0)
    }

    static func backupAndModifySetupFile(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if !isSetupExists() {
                DispatchQueue.main.async {
                    completion(false, "未找到 Setup 组件")
                }
                return
            }

            backupSetupFile { backupSuccess in
                if !backupSuccess {
                    DispatchQueue.main.async {
                        completion(false, "备份 Setup 组件失败")
                    }
                    return
                }

                modifySetupFile { modifySuccess in
                    DispatchQueue.main.async {
                        if modifySuccess {
                            completion(true, "所有操作已成功完成")
                        } else {
                            completion(false, "修改 Setup 组件失败")
                        }
                    }
                }
            }
        }
    }
}

