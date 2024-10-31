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
    
    private func removeTask(_ task: DownloadTask) {
        networkManager.removeTask(taskId: task.id)
    }

    private func sortTasks(_ tasks: [DownloadTask]) -> [DownloadTask] {
        switch sortOrder {
        case .addTime:
            return tasks
        case .name:
            return tasks.sorted { $0.productName < $1.productName }
        case .status:
            return tasks.sorted { $0.status.sortOrder < $1.status.sortOrder }
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
                    Task {
                        networkManager.clearCompletedTasks()
                    }
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
        .frame(width: 600, height: 400)
    }
}

extension DownloadManagerView.SortOrder: Hashable {}

#Preview {
    DownloadManagerView()
        .environmentObject(NetworkManager())
}
