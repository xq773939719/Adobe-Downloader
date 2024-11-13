//
//  Untitled.swift
//  Adobe Downloader
//
//  Created by X1a0He on 11/12/24.
//

import AppKit
import Cocoa
import ServiceManagement

@objc protocol HelperToolProtocol {
    func executeCommand(_ command: String, withReply reply: @escaping (String) -> Void)
}

@objcMembers
class PrivilegedHelperManager: NSObject {

    enum HelperStatus {
        case installed
        case noFound
        case needUpdate
    }

    static let shared = PrivilegedHelperManager()
    static let machServiceName = "com.x1a0he.macOS.Adobe-Downloader.helper"
    var connectionSuccessBlock: (() -> Void)?

    private var useLegacyInstall = false
    private var connection: NSXPCConnection?

    @Published private(set) var connectionState: ConnectionState = .disconnected
    
    enum ConnectionState {
        case connected
        case disconnected
        case connecting
    }

    override init() {
        super.init()
        initAuthorizationRef()

        DispatchQueue.main.async { [weak self] in
            _ = self?.connectToHelper()
        }
    }

    func checkInstall() {
        getHelperStatus { [weak self] status in
            guard let self = self else {return}
            switch status {
            case .noFound:
                if #available(macOS 13, *) {
                    let url = URL(string: "/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist")!
                    let status = SMAppService.statusForLegacyPlist(at: url)
                    if status == .requiresApproval {
                        let alert = NSAlert()
                        let notice = "Adobe Downloader 需要通过后台Daemon进程来安装与移动文件，请在\"系统偏好设置->登录项->允许在后台 中\"允许当前App"
                        let addition = "如果在设置里没找到当前App，可以尝试重置守护程序"
                        alert.messageText = notice + "\n" + addition
                        alert.addButton(withTitle: "打开系统登录项设置")
                        alert.addButton(withTitle: "重置守护程序")
                        if alert.runModal() == .alertFirstButtonReturn {
                            SMAppService.openSystemSettingsLoginItems()
                        } else {
                             removeInstallHelper()
                        }
                    }
                }
                fallthrough
            case .needUpdate:
                if Thread.isMainThread {
                    self.notifyInstall()
                } else {
                    DispatchQueue.main.async {
                        self.notifyInstall()
                    }
                }
            case .installed:
                self.connectionSuccessBlock?()
            }
        }
    }

    private func initAuthorizationRef() {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, AuthorizationFlags(), &authRef)
        if status != OSStatus(errAuthorizationSuccess) {
            return
        }
    }

    private func installHelperDaemon() -> DaemonInstallResult {
        var authRef: AuthorizationRef?
        var authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        guard authStatus == errAuthorizationSuccess else {
            return .authorizationFail
        }

        var authItem = AuthorizationItem(name: (kSMRightBlessPrivilegedHelper as NSString).utf8String!, valueLength: 0, value: nil, flags: 0)
        var authRights = withUnsafeMutablePointer(to: &authItem) { pointer in
            AuthorizationRights(count: 1, items: pointer)
        }
        let flags: AuthorizationFlags = [[], .interactionAllowed, .extendRights, .preAuthorize]
        authStatus = AuthorizationCreate(&authRights, nil, flags, &authRef)
        defer {
            if let ref = authRef {
                AuthorizationFree(ref, [])
            }
        }
        guard authStatus == errAuthorizationSuccess else {
            return .getAdminFail
        }

        var error: Unmanaged<CFError>?
        
        if SMJobBless(kSMDomainSystemLaunchd, PrivilegedHelperManager.machServiceName as CFString, authRef, &error) == false {
            if let blessError = error?.takeRetainedValue() {
                let nsError = blessError as Error as NSError
                NSAlert.alert(with: "SMJobBless failed with error: \(blessError)\nError domain: \(nsError.domain)\nError code: \(nsError.code)\nError description: \(nsError.localizedDescription)\nError user info: \(nsError.userInfo)")
                return .blessError(nsError.code)
            }
        }

        return .success
    }

    func getHelperStatus(callback: @escaping ((HelperStatus) -> Void)) {
        var called = false
        let reply: ((HelperStatus) -> Void) = {
            status in
            if called {return}
            called = true
            callback(status)
        }

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchServices/" + PrivilegedHelperManager.machServiceName)
        guard
            let helperBundleInfo = CFBundleCopyInfoDictionaryForURL(helperURL as CFURL) as? [String: Any],
            let helperVersion = helperBundleInfo["CFBundleShortVersionString"] as? String else {
            reply(.noFound)
            return
        }
        let helperFileExists = FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)")
        if !helperFileExists {
            reply(.noFound)
            return
        }

        reply(.installed)

    }

    static var getHelperStatus: Bool {
        var status = false
        let semaphore = DispatchSemaphore(value: 0)
        
        shared.getHelperStatus { helperStatus in
            status = helperStatus == .installed
            semaphore.signal()
        }
        
        semaphore.wait()
        return status
    }
    
    func reinstallHelper(completion: @escaping (Bool, String) -> Void) {
        removeInstallHelper()
        let result = installHelperDaemon()
        
        switch result {
        case .success:
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }

                guard let connection = connectToHelper() else {
                    completion(false, "无法连接到Helper")
                    return
                }
                
                guard let helper = connection.remoteObjectProxy as? HelperToolProtocol else {
                    completion(false, "无法获取Helper代理")
                    return
                }

                helper.executeCommand("whoami") { result in
                    if result.contains("root") {
                        completion(true, "Helper 重新安装成功")
                    } else {
                        completion(false, "Helper未能获取root权限")
                    }
                }
            }
            
        case .authorizationFail:
            completion(false, "获取授权失败")
        case .getAdminFail:
            completion(false, "获取管理员权限失败")
        case let .blessError(code):
            completion(false, "安装失败: \(result.alertContent)")
        }
    }

    func removeInstallHelper() {
        try? FileManager.default.removeItem(atPath: "/Library/PrivilegedHelperTools/\(PrivilegedHelperManager.machServiceName)")
        try? FileManager.default.removeItem(atPath: "/Library/LaunchDaemons/\(PrivilegedHelperManager.machServiceName).plist")
    }

    private func connectToHelper() -> NSXPCConnection? {
        connectionState = .connecting
        
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        if let existingConnection = connection, 
           existingConnection.remoteObjectProxy != nil {
            connectionState = .connected
            return existingConnection
        }

        connection?.invalidate()
        connection = nil

        let newConnection = NSXPCConnection(machServiceName: PrivilegedHelperManager.machServiceName, 
                                          options: .privileged)
        
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperToolProtocol.self)
        
        newConnection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.connectionState = .disconnected
                self?.connection?.invalidate()
                self?.connection = nil
            }
        }
        
        newConnection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.connectionState = .disconnected
                self?.connection?.invalidate()
                self?.connection = nil
            }
        }
        
        newConnection.resume()
        connection = newConnection

        if let helper = newConnection.remoteObjectProxy as? HelperToolProtocol {
            helper.executeCommand("whoami") { [weak self] result in
                if result == "root" {
                    DispatchQueue.main.async {
                        self?.connectionState = .connected
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.connectionState = .disconnected
                    }
                }
            }
        }
        
        return newConnection
    }

    func executeCommand(_ command: String, completion: @escaping (String) -> Void) {
        guard let connection = connectToHelper() else {
            connectionState = .disconnected
            completion("Error: Could not connect to helper")
            return
        }
        
        guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
            self.connectionState = .disconnected
        }) as? HelperToolProtocol else {
            connectionState = .disconnected
            completion("Error: Could not get helper proxy")
            return
        }
        
        helper.executeCommand(command) { [weak self] result in
            DispatchQueue.main.async {
                if self?.connection == nil {
                    self?.connectionState = .disconnected
                    completion("Error: Connection lost")
                    return
                }
                
                if result.starts(with: "Error:") {
                    self?.connectionState = .disconnected
                } else {
                    self?.connectionState = .connected
                }
                
                completion(result)
            }
        }
    }

    func reconnectHelper(completion: @escaping (Bool, String) -> Void) {
        connection?.invalidate()
        connection = nil

        guard let newConnection = connectToHelper() else {
            print("重新连接失败")
            completion(false, "无法连接到 Helper")
            return
        }

        guard let helper = newConnection.remoteObjectProxyWithErrorHandler({ error in
            completion(false, "连接出现错误: \(error.localizedDescription)")
        }) as? HelperToolProtocol else {
            completion(false, "无法获取 Helper 代理")
            return
        }

        helper.executeCommand("whoami") { result in
            if result == "root" {
                completion(true, "Helper 重新连接成功")
            } else {
                completion(false, "Helper 响应异常")
            }
        }
    }
}

extension PrivilegedHelperManager {
    private func notifyInstall() {
        if useLegacyInstall {
            useLegacyInstall = false
            checkInstall()
            return
        }

        let result = installHelperDaemon()
        if case .success = result {
            checkInstall()
            return
        }
        result.alertAction()
        let ret = result.shouldRetryLegacyWay()
        useLegacyInstall = ret.0
        let isCancle = ret.1
        if !isCancle, useLegacyInstall  {
            checkInstall()
        } else if isCancle, !useLegacyInstall {
            NSAlert.alert(with: "获取管理员授权失败，用户主动取消授权！")
        }
    }
}

private enum DaemonInstallResult {
    case success
    case authorizationFail
    case getAdminFail
    case blessError(Int)
    var alertContent: String {
        switch self {
        case .success:
            return ""
        case .authorizationFail: return "Failed to create authorization!"
        case .getAdminFail: return "The user actively cancels the authorization, Failed to get admin authorization! "
        case let .blessError(code):
            switch code {
            case kSMErrorInternalFailure: return "blessError: kSMErrorInternalFailure"
            case kSMErrorInvalidSignature: return "blessError: kSMErrorInvalidSignature"
            case kSMErrorAuthorizationFailure: return "blessError: kSMErrorAuthorizationFailure"
            case kSMErrorToolNotValid: return "blessError: kSMErrorToolNotValid"
            case kSMErrorJobNotFound: return "blessError: kSMErrorJobNotFound"
            case kSMErrorServiceUnavailable: return "blessError: kSMErrorServiceUnavailable"
            case kSMErrorJobMustBeEnabled: return "Adobe Downloader Helper is disabled by other process. Please run \"sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)\" in your terminal. The command has been copied to your pasteboard"
            case kSMErrorInvalidPlist: return "blessError: kSMErrorInvalidPlist"
            default:
                return "bless unknown error:\(code)"
            }
        }
    }

    func shouldRetryLegacyWay() -> (Bool, Bool) {
        switch self {
        case .success: return (false, false)
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                return (false, false)
            default:
                return (true, false)
            }
        case .authorizationFail:
            return (true, false)
        case .getAdminFail:
            return (false, true)
        }
    }

    func alertAction() {
        switch self {
        case let .blessError(code):
            switch code {
            case kSMErrorJobMustBeEnabled:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("sudo launchctl enable system/\(PrivilegedHelperManager.machServiceName)", forType: .string)
            default:
                break
            }
        default:
            break
        }
    }
}

extension NSAlert {
    static func alert(with text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }
}
