//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation
import SwiftUI

enum PackageStatus: Equatable, Codable {
    case waiting
    case downloading
    case paused
    case completed
    case failed(String)

    var description: LocalizedStringKey {
        switch self {
        case .waiting: return "等待中"
        case .downloading: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed(let message): return "失败: \(message)"
        }
    }
    
    static func == (lhs: PackageStatus, rhs: PackageStatus) -> Bool {
        switch (lhs, rhs) {
        case (.waiting, .waiting):
            return true
        case (.downloading, .downloading):
            return true
        case (.paused, .paused):
            return true
        case (.completed, .completed):
            return true
        case (.failed(let lhsMessage), .failed(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

enum NetworkError: Error, LocalizedError {
    case noConnection
    case timeout
    case serverUnreachable(String)

    case invalidURL(String)
    case invalidRequest(String)
    case invalidResponse

    case invalidData(String)
    case parsingError(Error, String)
    case dataValidationError(String)

    case httpError(Int, String?)
    case serverError(Int)
    case clientError(Int)

    case downloadError(String, Error?)
    case downloadCancelled
    case insufficientStorage(Int64, Int64)

    case fileSystemError(String, Error?)
    case fileExists(String)
    case fileNotFound(String)
    case filePermissionDenied(String)

    case applicationInfoError(String, Error?)
    case unsupportedPlatform(String)
    case incompatibleVersion(String, String)
    case cancelled
    case installError(String)

    var errorCode: Int {
        switch self {
        case .noConnection: return 1001
        case .timeout: return 1002
        case .serverUnreachable: return 1003
        case .invalidURL: return 2001
        case .invalidRequest: return 2002
        case .invalidResponse: return 2003
        case .invalidData: return 3001
        case .parsingError: return 3002
        case .dataValidationError: return 3003
        case .httpError: return 4001
        case .serverError: return 4002
        case .clientError: return 4003
        case .downloadError: return 5001
        case .downloadCancelled: return 5002
        case .insufficientStorage: return 5003
        case .fileSystemError: return 6001
        case .fileExists: return 6002
        case .fileNotFound: return 6003
        case .filePermissionDenied: return 6004
        case .applicationInfoError: return 7001
        case .unsupportedPlatform: return 7002
        case .incompatibleVersion: return 7003
        case .cancelled: return 5004
        case .installError: return 8001
        }
    }

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return NSLocalizedString("没有网络连接", comment: "Network error")
        case .timeout:
            return NSLocalizedString("请求超时，请检查网络连接后重试", comment: "Network timeout")
        case .serverUnreachable(let server):
            return NSLocalizedString("无法连接到服务器: \(server)", comment: "Server unreachable")
        case .invalidURL(let url):
            return NSLocalizedString("无效的URL: \(url)", comment: "Invalid URL")
        case .invalidRequest(let reason):
            return NSLocalizedString("无效的请求: \(reason)", comment: "Invalid request")
        case .invalidResponse:
            return NSLocalizedString("服务器响应无效", comment: "Invalid response")
        case .invalidData(let detail):
            return NSLocalizedString("数据无效: \(detail)", comment: "Invalid data")
        case .parsingError(let error, let context):
            return NSLocalizedString("解析错误: \(context) - \(error.localizedDescription)", comment: "Parsing error")
        case .dataValidationError(let reason):
            return NSLocalizedString("数据验证失败: \(reason)", comment: "Data validation error")
        case .httpError(let code, let message):
            return NSLocalizedString("HTTP错误 \(code): \(message ?? "")", comment: "HTTP error")
        case .serverError(let code):
            return NSLocalizedString("服务器错误: \(code)", comment: "Server error")
        case .clientError(let code):
            return NSLocalizedString("客户端错误: \(code)", comment: "Client error")
        case .downloadError(let message, let error):
            if let error = error {
                return NSLocalizedString("\(message): \(error.localizedDescription)", comment: "Download error")
            }
            return NSLocalizedString(message, comment: "Download error")
        case .downloadCancelled:
            return NSLocalizedString("下载已取消", comment: "Download cancelled")
        case .insufficientStorage(let needed, let available):
            return NSLocalizedString("存储空间不足: 需要 \(needed)字节, 可用 \(available)字节", comment: "Insufficient storage")
        case .fileSystemError(let operation, let error):
            if let error = error {
                return NSLocalizedString("文件系统错误(\(operation)): \(error.localizedDescription)", comment: "File system error")
            }
            return NSLocalizedString("文件系统错误: \(operation)", comment: "File system error")
        case .fileExists(let path):
            return NSLocalizedString("文件已存在: \(path)", comment: "File exists")
        case .fileNotFound(let path):
            return NSLocalizedString("文件不存在: \(path)", comment: "File not found")
        case .filePermissionDenied(let path):
            return NSLocalizedString("文件访问权限被拒绝: \(path)", comment: "File permission denied")
        case .applicationInfoError(let message, let error):
            if let error = error {
                return NSLocalizedString("应用信息错误(\(message)): \(error.localizedDescription)", comment: "Application info error")
            }
            return NSLocalizedString("应用信息错误: \(message)", comment: "Application info error")
        case .unsupportedPlatform(let platform):
            return NSLocalizedString("不支持的平台: \(platform)", comment: "Unsupported platform")
        case .incompatibleVersion(let current, let required):
            return NSLocalizedString("版本不兼容: 当前版本 \(current), 需要版本 \(required)", comment: "Incompatible version")
        case .cancelled:
            return NSLocalizedString("下载已取消", comment: "Download cancelled")
        case .installError(let message):
            return NSLocalizedString("安装错误: \(message)", comment: "Install error")
        }
    }
    
    var debugDescription: String {
        return "Error \(errorCode): \(errorDescription ?? "")"
    }
}

enum DownloadStatus: Equatable, Codable {
    case waiting
    case preparing(PrepareInfo)
    case downloading(DownloadInfo)
    case paused(PauseInfo)
    case completed(CompletionInfo)
    case failed(FailureInfo)
    case retrying(RetryInfo)

    struct PrepareInfo: Codable {
        let message: String
        let timestamp: Date
        let stage: PrepareStage
        
        enum PrepareStage: Codable {
            case initializing
            case creatingInstaller
            case signingApp
            case fetchingInfo
            case validatingSetup
        }
    }
    
    struct DownloadInfo: Codable {
        let fileName: String
        let currentPackageIndex: Int
        let totalPackages: Int
        let startTime: Date
        let estimatedTimeRemaining: TimeInterval?
    }
    
    struct PauseInfo: Codable {
        let reason: PauseReason
        let timestamp: Date
        let resumable: Bool
        
        enum PauseReason: Codable {
            case userRequested
            case networkIssue
            case systemSleep
            case other(String)
        }
    }
    
    struct CompletionInfo: Codable {
        let timestamp: Date
        let totalTime: TimeInterval
        let totalSize: Int64
    }
    
    struct FailureInfo: Codable {
        let message: String
        let error: Error?
        let timestamp: Date
        let recoverable: Bool
        
        enum CodingKeys: CodingKey {
            case message
            case timestamp
            case recoverable
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(recoverable, forKey: .recoverable)
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            recoverable = try container.decode(Bool.self, forKey: .recoverable)
            error = nil
        }
        
        init(message: String, error: Error?, timestamp: Date, recoverable: Bool) {
            self.message = message
            self.error = error
            self.timestamp = timestamp
            self.recoverable = recoverable
        }
    }
    
    struct RetryInfo: Codable {
        let attempt: Int
        let maxAttempts: Int
        let reason: String
        let nextRetryDate: Date
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case info
    }
    
    private enum StatusType: String, Codable {
        case waiting
        case preparing
        case downloading
        case paused
        case completed
        case failed
        case retrying
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .waiting:
            try container.encode(StatusType.waiting, forKey: .type)
        case .preparing(let info):
            try container.encode(StatusType.preparing, forKey: .type)
            try container.encode(info, forKey: .info)
        case .downloading(let info):
            try container.encode(StatusType.downloading, forKey: .type)
            try container.encode(info, forKey: .info)
        case .paused(let info):
            try container.encode(StatusType.paused, forKey: .type)
            try container.encode(info, forKey: .info)
        case .completed(let info):
            try container.encode(StatusType.completed, forKey: .type)
            try container.encode(info, forKey: .info)
        case .failed(let info):
            try container.encode(StatusType.failed, forKey: .type)
            try container.encode(info, forKey: .info)
        case .retrying(let info):
            try container.encode(StatusType.retrying, forKey: .type)
            try container.encode(info, forKey: .info)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StatusType.self, forKey: .type)
        
        switch type {
        case .waiting:
            self = .waiting
        case .preparing:
            let info = try container.decode(PrepareInfo.self, forKey: .info)
            self = .preparing(info)
        case .downloading:
            let info = try container.decode(DownloadInfo.self, forKey: .info)
            self = .downloading(info)
        case .paused:
            let info = try container.decode(PauseInfo.self, forKey: .info)
            self = .paused(info)
        case .completed:
            let info = try container.decode(CompletionInfo.self, forKey: .info)
            self = .completed(info)
        case .failed:
            let info = try container.decode(FailureInfo.self, forKey: .info)
            self = .failed(info)
        case .retrying:
            let info = try container.decode(RetryInfo.self, forKey: .info)
            self = .retrying(info)
        }
    }
    
    var description: String {
        switch self {
        case .waiting:
            return NSLocalizedString("等待中", comment: "Download status waiting")
        case .preparing(let info):
            return NSLocalizedString("准备中: \(info.message)", comment: "Download status preparing")
        case .downloading(let info):
            return String(format: NSLocalizedString("正在下载 %@ (%d/%d)", comment: "Download status downloading"),
                        info.fileName, info.currentPackageIndex + 1, info.totalPackages)
        case .paused(let info):
            switch info.reason {
            case .userRequested:
                return NSLocalizedString("已暂停", comment: "Download status paused")
            case .networkIssue:
                return NSLocalizedString("网络中断", comment: "Download status network paused")
            case .systemSleep:
                return NSLocalizedString("系统休眠", comment: "Download status system sleep")
            case .other(let reason):
                return NSLocalizedString("已暂停: \(reason)", comment: "Download status paused with reason")
            }
        case .completed(let info):
            let duration = formatDuration(info.totalTime)
            return NSLocalizedString("已完成 (用时: \(duration))", comment: "Download status completed")
        case .failed(let info):
            return NSLocalizedString("失败: \(info.message)", comment: "Download status failed")
        case .retrying(let info):
            return String(format: NSLocalizedString("重试中 (%d/%d)", comment: "Download status retrying"),
                        info.attempt, info.maxAttempts)
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .downloading: return 0
        case .preparing: return 1
        case .waiting: return 2
        case .paused: return 3
        case .retrying: return 4
        case .failed: return 5
        case .completed: return 6
        }
    }
    
    var isActive: Bool {
        switch self {
        case .downloading, .preparing, .waiting, .retrying:
            return true
        default:
            return false
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
    
    var canRetry: Bool {
        switch self {
        case .failed(let info):
            return info.recoverable
        default:
            return false
        }
    }
    
    var canPause: Bool {
        switch self {
        case .downloading, .preparing, .waiting:
            return true
        default:
            return false
        }
    }
    
    var canResume: Bool {
        switch self {
        case .paused(let info):
            return info.resumable
        default:
            return false
        }
    }
}

extension DownloadStatus {
    static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.waiting, .waiting):
            return true
        case (.preparing(let lInfo), .preparing(let rInfo)):
            return lInfo.message == rInfo.message && 
                   lInfo.timestamp == rInfo.timestamp &&
                   lInfo.stage == rInfo.stage
        case (.downloading(let lInfo), .downloading(let rInfo)):
            return lInfo.fileName == rInfo.fileName &&
                   lInfo.currentPackageIndex == rInfo.currentPackageIndex &&
                   lInfo.totalPackages == rInfo.totalPackages
        case (.paused(let lInfo), .paused(let rInfo)):
            return lInfo.reason == rInfo.reason &&
                   lInfo.timestamp == rInfo.timestamp &&
                   lInfo.resumable == rInfo.resumable
        case (.completed(let lInfo), .completed(let rInfo)):
            return lInfo.timestamp == rInfo.timestamp &&
                   lInfo.totalTime == rInfo.totalTime &&
                   lInfo.totalSize == rInfo.totalSize
        case (.failed(let lInfo), .failed(let rInfo)):
            return lInfo.message == rInfo.message &&
                   lInfo.timestamp == rInfo.timestamp &&
                   lInfo.recoverable == rInfo.recoverable
        case (.retrying(let lInfo), .retrying(let rInfo)):
            return lInfo.attempt == rInfo.attempt &&
                   lInfo.maxAttempts == rInfo.maxAttempts &&
                   lInfo.reason == rInfo.reason &&
                   lInfo.nextRetryDate == rInfo.nextRetryDate
        default:
            return false
        }
    }
}

extension DownloadStatus.PrepareInfo: Equatable {
    static func == (lhs: DownloadStatus.PrepareInfo, rhs: DownloadStatus.PrepareInfo) -> Bool {
        return lhs.message == rhs.message &&
               lhs.timestamp == rhs.timestamp &&
               lhs.stage == rhs.stage
    }
}

extension DownloadStatus.PrepareInfo.PrepareStage: Equatable {
    static func == (lhs: DownloadStatus.PrepareInfo.PrepareStage, rhs: DownloadStatus.PrepareInfo.PrepareStage) -> Bool {
        switch (lhs, rhs) {
        case (.initializing, .initializing):
            return true
        case (.creatingInstaller, .creatingInstaller):
            return true
        case (.signingApp, .signingApp):
            return true
        case (.fetchingInfo, .fetchingInfo):
            return true
        case (.validatingSetup, .validatingSetup):
            return true
        default:
            return false
        }
    }
}

extension DownloadStatus.PauseInfo.PauseReason: Equatable {
    static func == (lhs: DownloadStatus.PauseInfo.PauseReason, rhs: DownloadStatus.PauseInfo.PauseReason) -> Bool {
        switch (lhs, rhs) {
        case (.userRequested, .userRequested):
            return true
        case (.networkIssue, .networkIssue):
            return true
        case (.systemSleep, .systemSleep):
            return true
        case (.other(let lhsReason), .other(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}

enum LoadingState: Equatable {
    case idle
    case loading
    case failed(Error)
    case success
    
    static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading, .loading):
            return true
        case (.success, .success):
            return true
        case (.failed(let lError), .failed(let rError)):
            return lError.localizedDescription == rError.localizedDescription
        default:
            return false
        }
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return String(format: "%.1f秒", seconds)
    } else if seconds < 3600 {
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)分\(remainingSeconds)秒"
    } else {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(hours)小时\(minutes)分\(remainingSeconds)秒"
    }
}

extension DownloadStatus.DownloadInfo: Equatable {
    static func == (lhs: DownloadStatus.DownloadInfo, rhs: DownloadStatus.DownloadInfo) -> Bool {
        return lhs.fileName == rhs.fileName &&
               lhs.currentPackageIndex == rhs.currentPackageIndex &&
               lhs.totalPackages == rhs.totalPackages &&
               lhs.startTime == rhs.startTime &&
               lhs.estimatedTimeRemaining == rhs.estimatedTimeRemaining
    }
}

extension DownloadStatus.PauseInfo: Equatable {
    static func == (lhs: DownloadStatus.PauseInfo, rhs: DownloadStatus.PauseInfo) -> Bool {
        return lhs.reason == rhs.reason &&
               lhs.timestamp == rhs.timestamp &&
               lhs.resumable == rhs.resumable
    }
}

extension DownloadStatus.CompletionInfo: Equatable {
    static func == (lhs: DownloadStatus.CompletionInfo, rhs: DownloadStatus.CompletionInfo) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
               lhs.totalTime == rhs.totalTime &&
               lhs.totalSize == rhs.totalSize
    }
}

extension DownloadStatus.FailureInfo: Equatable {
    static func == (lhs: DownloadStatus.FailureInfo, rhs: DownloadStatus.FailureInfo) -> Bool {
        return lhs.message == rhs.message &&
               lhs.timestamp == rhs.timestamp &&
               lhs.recoverable == rhs.recoverable
    }
}

extension DownloadStatus.RetryInfo: Equatable {
    static func == (lhs: DownloadStatus.RetryInfo, rhs: DownloadStatus.RetryInfo) -> Bool {
        return lhs.attempt == rhs.attempt &&
               lhs.maxAttempts == rhs.maxAttempts &&
               lhs.reason == rhs.reason &&
               lhs.nextRetryDate == rhs.nextRetryDate
    }
} 
