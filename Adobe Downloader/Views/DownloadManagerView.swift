//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//

import SwiftUI

struct DownloadManagerView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var sortOrder: SortOrder = .addTime

    enum SortOrder {
        case addTime
        case name
        case status
        
        var description: String {
            switch self {
            case .addTime: return String(localized: "按添加时间")
            case .name: return String(localized: "按名称")
            case .status: return String(localized: "按状态")
            }
        }
    }
    
    private func removeTask(_ task: NewDownloadTask) {
        networkManager.removeTask(taskId: task.id)
    }

    private func sortTasks(_ tasks: [NewDownloadTask]) -> [NewDownloadTask] {
        switch sortOrder {
        case .addTime:
            return tasks
        case .name:
            return tasks.sorted { task1, task2 in
                task1.displayName < task2.displayName
            }
        case .status:
            return tasks.sorted { task1, task2 in
                task1.status.sortOrder < task2.status.sortOrder
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("下载管理")
                    .font(.headline)
                Spacer()
                HStack(){
                    Menu {
                        ForEach([SortOrder.addTime, .name, .status], id: \.self) { order in
                            Button(action: {
                                sortOrder = order
                            }) {
                                HStack {
                                    Text(order.description)
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOrder.description)
                                .font(.caption)
                        }
                    }
                }
                .frame(minWidth: 120)
                .fixedSize()

                Button("全部暂停") {
                    Task {
                        for task in networkManager.downloadTasks {
                            if case .downloading = task.status {
                                await networkManager.downloadUtils.pauseDownloadTask(
                                    taskId: task.id,
                                    reason: .userRequested
                                )
                            }
                        }
                    }
                }
                
                Button("全部继续") {
                    Task {
                        for task in networkManager.downloadTasks {
                            if case .paused = task.status {
                                await networkManager.downloadUtils.resumeDownloadTask(taskId: task.id)
                            }
                        }
                    }
                }
                
                Button("清理已完成") {
                    networkManager.downloadTasks.removeAll { task in
                        if case .completed = task.status {
                            return true
                        }
                        return false
                    }
                    networkManager.updateDockBadge()
                }
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(sortTasks(networkManager.downloadTasks)) { task in
                        DownloadProgressView(
                            task: task,
                            onCancel: {
                                Task {
                                    await networkManager.downloadUtils.cancelDownloadTask(taskId: task.id)
                                }
                            },
                            onPause: {
                                Task {
                                    await networkManager.downloadUtils.pauseDownloadTask(
                                        taskId: task.id,
                                        reason: .userRequested
                                    )
                                }
                            },
                            onResume: {
                                Task {
                                    await networkManager.downloadUtils.resumeDownloadTask(taskId: task.id)
                                }
                            },
                            onRetry: {
                                Task {
                                    await networkManager.downloadUtils.resumeDownloadTask(taskId: task.id)
                                }
                            },
                            onRemove: {
                                removeTask(task)
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width:800, height: 600)
    }
}

extension DownloadManagerView.SortOrder: Hashable {}

#Preview {
    DownloadManagerView()
        .environmentObject(NetworkManager())
}
