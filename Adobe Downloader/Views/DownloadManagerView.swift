//
//  Adobe-Downloader
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
            case .addTime: return "按添加时间"
            case .name: return "按名称"
            case .status: return "按状态"
            }
        }
    }
    
    private func removeTask(_ task: NewDownloadTask) {
        networkManager.downloadTasks.removeAll { $0.id == task.id }
        networkManager.updateDockBadge()
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
        VStack(spacing: 12) {
            HStack {
                Text("下载管理")
                    .font(.headline)
                Spacer()
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

                Button("全部暂停", action: {})
                Button("全部继续", action: {})
                Button("清理已完成", action: {
                    networkManager.downloadTasks.removeAll { task in
                        if case .completed = task.status {
                            return true
                        }
                        return false
                    }
                    networkManager.updateDockBadge()
                })
                
                Button("关闭") {
                    dismiss()
                }
            }
            .padding()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sortTasks(networkManager.downloadTasks)) { task in
                        DownloadProgressView(
                            task: task,
                            onCancel: {
                                networkManager.cancelDownload(taskId: task.id)
                            },
                            onPause: {
                                networkManager.pauseDownload(taskId: task.id)
                            },
                            onResume: {
                                Task {
                                    await networkManager.resumeDownload(taskId: task.id)
                                }
                            },
                            onRetry: {
                                Task {
                                    await networkManager.resumeDownload(taskId: task.id)
                                }
                            },
                            onRemove: {
                                removeTask(task)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(width: 600, height: 500)
    }
}

extension DownloadManagerView.SortOrder: Hashable {}

#Preview {
    DownloadManagerView()
        .environmentObject(NetworkManager())
}
