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
        case .downloading(let info): return info.startTime
        case .completed(let info): return info.timestamp - info.totalTime
        case .preparing(let info): return info.timestamp
        case .paused(let info): return info.timestamp
        case .failed(let info): return info.timestamp
        case .retrying(let info): return info.nextRetryDate - 60
        case .waiting, .none: return createAt
        }
    }
}

extension NetworkManager {
    func configureNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                switch (wasConnected, self.isConnected) {
                    case (false, true): await resumePausedTasks()
                    case (true, false): await pauseActiveTasks()
                    default: break
                }
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
    
    private func resumePausedTasks() async {
        for task in downloadTasks {
            if case .paused(let info) = task.status,
               info.reason == .networkIssue {
                await downloadUtils.resumeDownloadTask(taskId: task.id)
            }
        }
    }
    
    private func pauseActiveTasks() async {
        for task in downloadTasks {
            if case .downloading = task.status {
                await downloadUtils.pauseDownloadTask(taskId: task.id, reason: .networkIssue)
            }
        }
    }
    
    func generateCookie() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomString = (0..<26).map { _ in chars.randomElement()! }
        return "fg=\(String(randomString))======"
    }
} 
