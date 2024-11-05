//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation
import AppKit

extension NewDownloadTask {
    var startTime: Date {
        switch totalStatus {
        case .downloading(let info):
            return info.startTime
        case .completed(let info):
            return info.timestamp.addingTimeInterval(-info.totalTime)
        case .preparing(let info):
            return info.timestamp
        case .paused(let info):
            return info.timestamp
        case .failed(let info):
            return info.timestamp
        case .retrying(let info):
            return info.nextRetryDate.addingTimeInterval(-60)
        case .waiting, .none:
            return createAt
        }
    }
}

extension NetworkManager {
    func configureNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied

                if !wasConnected && self.isConnected {
                    for task in self.downloadTasks {
                        if case .paused(let info) = task.status,
                           info.reason == .networkIssue {
                            await self.downloadUtils.resumeDownloadTask(taskId: task.id)
                        }
                    }
                } else if wasConnected && !self.isConnected {
                    for task in self.downloadTasks {
                        if case .downloading = task.status {
                            await self.downloadUtils.pauseDownloadTask(
                                taskId: task.id,
                                reason: .networkIssue
                            )
                        }
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    func generateCookie() -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomString = String((0..<26).map { _ in letters.randomElement()! })
        return "fg=\(randomString)======"
    }
} 
