//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

class DownloadTask: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    let sapCode: String
    let version: String
    let language: String
    let productName: String
    @Published var status: DownloadStatus
    @Published var progress: Double
    @Published var downloadedSize: Int64
    @Published var totalSize: Int64
    @Published var speed: Double
    @Published var currentFileName: String
    let destinationURL: URL
    var priority: Priority
    var retryCount: Int
    let createdAt: Date
    @Published var lastUpdated: Date
    @Published var lastRecordedSize: Int64
    @Published var packages: [Package]
    @Published var detailedStatus: String = ""
    
    enum Priority: Int {
        case low = 0
        case normal = 1
        case high = 2
    }
    
    enum DownloadStatus {
        case waiting
        case preparing(PrepareInfo)
        case downloading(DownloadInfo)
        case paused(PauseInfo)
        case completed(CompletionInfo)
        case failed(FailureInfo)
        case retrying(RetryInfo)

        struct PrepareInfo: Equatable {
            let message: String
            let timestamp: Date
            let stage: PrepareStage
            
            enum PrepareStage: Equatable {
                case initializing
                case creatingInstaller
                case signingApp
                case fetchingInfo
                case validatingSetup
            }
        }
        
        struct DownloadInfo: Equatable {
            let fileName: String
            let currentPackageIndex: Int
            let totalPackages: Int
            let startTime: Date
            let estimatedTimeRemaining: TimeInterval?
        }
        
        struct PauseInfo: Equatable {
            let reason: PauseReason
            let timestamp: Date
            let resumable: Bool
            
            enum PauseReason: Equatable {
                case userRequested
                case networkIssue
                case systemSleep
                case other(String)
            }
        }
        
        struct CompletionInfo: Equatable {
            let timestamp: Date
            let totalTime: TimeInterval
            let totalSize: Int64
        }
        
        struct FailureInfo: Equatable {
            let message: String
            let error: Error?
            let timestamp: Date
            let recoverable: Bool
            
            static func == (lhs: FailureInfo, rhs: FailureInfo) -> Bool {
                lhs.message == rhs.message &&
                lhs.timestamp == rhs.timestamp &&
                lhs.recoverable == rhs.recoverable
            }
        }
        
        struct RetryInfo: Equatable {
            let attempt: Int
            let maxAttempts: Int
            let reason: String
            let nextRetryDate: Date
        }
        
        var description: String {
            switch self {
            case .waiting:
                return "等待中"
            case .preparing(let info):
                return "准备中: \(info.message)"
            case .downloading(let info):
                return "下载中: \(info.fileName) (\(info.currentPackageIndex + 1)/\(info.totalPackages))"
            case .paused(let info):
                switch info.reason {
                case .userRequested: return "已暂停"
                case .networkIssue: return "网络中断"
                case .systemSleep: return "系统休眠"
                case .other(let reason): return "已暂停: \(reason)"
                }
            case .completed(let info):
                let duration = String(format: "%.1f", info.totalTime)
                return "已完成 (用时: \(duration)秒)"
            case .failed(let info):
                return "失败: \(info.message)"
            case .retrying(let info):
                return "重试中 (\(info.attempt)/\(info.maxAttempts))"
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
        
        var isFinished: Bool {
            switch self {
            case .completed, .failed:
                return true
            default:
                return false
            }
        }
        
        var isPaused: Bool {
            if case .paused = self {
                return true
            }
            return false
        }
        
        var isActive: Bool {
            switch self {
            case .downloading, .preparing, .retrying:
                return true
            default:
                return false
            }
        }
        
        var isCompleted: Bool {
            if case .completed = self {
                return true
            }
            return false
        }
        
        var isFailed: Bool {
            if case .failed = self {
                return true
            }
            return false
        }
    }
    
    enum PackageStatus {
        case waiting
        case downloading
        case paused
        case completed
        case failed(String)
        
        var description: String {
            switch self {
            case .waiting: return "等待中"
            case .downloading: return "下载中"
            case .paused: return "已暂停"
            case .completed: return "已完成"
            case .failed(let message): return "失败: \(message)"
            }
        }
    }
    
    struct Package: Identifiable {
        let id = UUID()
        var name: String
        var Path: String
        var size: Int64
        var downloadedSize: Int64 = 0
        var progress: Double = 0
        var speed: Double = 0
        var status: PackageStatus = .waiting
        var type: String
        var downloaded: Bool = false
        var lastUpdated: Date = Date()
        var lastRecordedSize: Int64 = 0
    }

    init(sapCode: String, version: String, language: String, productName: String,
         status: DownloadStatus = .waiting, progress: Double = 0,
         downloadedSize: Int64 = 0, totalSize: Int64 = 0, speed: Double = 0,
         currentFileName: String = "", destinationURL: URL,
         priority: Priority = .normal, retryCount: Int = 0,
         packages: [Package] = [], detailedStatus: String = "") {
        self.sapCode = sapCode
        self.version = version
        self.language = language
        self.productName = productName
        self.status = status
        self.progress = progress
        self.downloadedSize = downloadedSize
        self.totalSize = totalSize
        self.speed = speed
        self.currentFileName = currentFileName
        self.destinationURL = destinationURL
        self.priority = priority
        self.retryCount = retryCount
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.lastRecordedSize = 0
        self.packages = packages
        self.detailedStatus = detailedStatus
    }

    private func updateProgress(_ newProgress: Double) {
        objectWillChange.send()
        progress = newProgress
    }
    
    private func updateSpeed(_ newSpeed: Double) {
        objectWillChange.send()
        speed = newSpeed
    }

    static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
        lhs.id == rhs.id
    }
}

extension DownloadTask.DownloadStatus: Equatable {
    static func == (lhs: DownloadTask.DownloadStatus, rhs: DownloadTask.DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.waiting, .waiting): return true
        case (.downloading, .downloading): return true
        case (.paused, .paused): return true
        case (.completed, .completed): return true
        case (.failed(let lhsMessage), .failed(let rhsMessage)): return lhsMessage == rhsMessage
        case (.retrying(let lhsCount), .retrying(let rhsCount)): return lhsCount == rhsCount
        default: return false
        }
    }
}
