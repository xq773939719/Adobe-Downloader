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
    
    static func checkComponentVersion() -> String {
        if let cachedVersion = cachedVersion {
            return cachedVersion
        }
        
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
        
        guard FileManager.default.fileExists(atPath: setupPath) else {
            let message = String(localized: "未找到 Setup 组件")
            cachedVersion = message
            return message
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

    static func isSetupBackup() -> Bool {
        return FileManager.default.fileExists(atPath: "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup.original")
    }
    
    static func backupSetupFile(completion: @escaping (Bool, String) -> Void) {
        let setupQueue = DispatchQueue(label: "com.x1a0he.adobedownloader.setup")
        
        setupQueue.async {
            let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
            let backupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup.original"

            let shellScript = """
#!/bin/bash
function hex() {
    echo ''$1'' | perl -0777pe 's|([0-9a-zA-Z]{2}+(?![^\\(]*\\)))|\\\\x${1}|gs'
}

function replace() {
    declare -r dom=$(hex "$2")
    declare -r sub=$(hex "$3")
    perl -0777pi -e 'BEGIN{$/=\\1e8} s|'$dom'|'$sub'|gs' "$1"
}

function prep() {
    codesign --remove-signature "$1"
    codesign -f -s - --timestamp=none --all-architectures --deep "$1"
    xattr -cr "$1"
}

cp '\(setupPath)' '\(backupPath)'

replace '\(setupPath)' '554889E553504889FB488B0570C70300488B00488945F0E824D7FEFF4883C3084839D80F' '6A0158C353504889FB488B0570C70300488B00488945F0E824D7FEFF4883C3084839D80F'
replace '\(setupPath)' 'FFC300D1F44F01A9FD7B02A9FD830091F30300AA1F2003D568A11D58080140F9E80700F9' '200080D2C0035FD6FD7B02A9FD830091F30300AA1F2003D568A11D58080140F9E80700F9'

prep '\(setupPath)'
"""

            let tempScriptPath = FileManager.default.temporaryDirectory.appendingPathComponent("setup_script.sh")
            do {
                try shellScript.write(to: tempScriptPath, atomically: true, encoding: .utf8)

                let script = """
                do shell script "sudo chmod 777 '\(tempScriptPath.path)' && sudo '\(tempScriptPath.path)'" with administrator privileges
                """

                var scriptError: NSDictionary?
                DispatchQueue.main.sync {
                    let appleScript = NSAppleScript(source: script)
                    scriptError = nil
                    _ = appleScript?.executeAndReturnError(&scriptError)
                }
                
                try? FileManager.default.removeItem(at: tempScriptPath)

                DispatchQueue.main.async {
                    if let error = scriptError {
                        completion(false, "操作执行时发生错误: \(error)")
                    } else {
                        completion(true, "所有操作已成功完成")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, "创建脚本文件时发生错误: \(error)")
                }
            }
        }
    }
}

