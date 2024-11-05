//
//  ModifySetup.swift
//  Adobe Downloader
//
//  Created by X1a0He on 11/5/24.
//

import Foundation
import SwiftUI

class ModifySetup {
    static func checkSetupBackup() -> Bool {
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
        let backupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup.original"
        
        return FileManager.default.fileExists(atPath: setupPath) && 
               !FileManager.default.fileExists(atPath: backupPath)
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

# M 系列的修改，暂时缺少Intel机型的特征码
replace '\(setupPath)' 'FFC300D1F44F01A9FD7B02A9FD830091F30300AA1F2003D568A11D58080140F9E80700F9' '200080D2C0035FD6FD7B02A9FD830091F30300AA1F2003D568A11D58080140F9E80700F9'

prep '\(setupPath)'
"""

            let tempScriptPath = FileManager.default.temporaryDirectory.appendingPathComponent("setup_script.sh")
            do {
                try shellScript.write(to: tempScriptPath, atomically: true, encoding: .utf8)

                let script = """
                do shell script "chmod +x '\(tempScriptPath.path)' && sudo '\(tempScriptPath.path)'" with administrator privileges
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

