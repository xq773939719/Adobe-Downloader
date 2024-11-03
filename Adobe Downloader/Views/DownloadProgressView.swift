//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct DownloadProgressView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    let task: NewDownloadTask
    let onCancel: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    
    @State private var showInstallPrompt = false
    @State private var isInstalling = false
    @State private var isPackageListExpanded: Bool = false
    
    private var statusLabel: some View {
        Text(task.status.description)
            .font(.caption)
            .foregroundColor(statusColor)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(statusBackgroundColor)
            .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch task.status {
        case .downloading:
            return .white
        case .preparing:
            return .white
        case .completed:
            return .white
        case .failed:
            return .white
        case .paused:
            return .white
        case .waiting:
            return .white
        case .retrying:
            return .white
        }
    }
    
    private var statusBackgroundColor: Color {
        switch task.status {
        case .downloading:
            return Color.blue
        case .preparing:
            return Color.purple.opacity(0.8)
        case .completed:
            return Color.green.opacity(0.8)
        case .failed:
            return Color.red.opacity(0.8)
        case .paused:
            return Color.orange.opacity(0.8)
        case .waiting:
            return Color.gray.opacity(0.8)
        case .retrying:
            return Color.yellow.opacity(0.8)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch task.status {
            case .downloading, .preparing, .waiting:
                Button(action: onPause) {
                    Label("暂停", systemImage: "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                
                Button(action: onCancel) {
                    Label("取消", systemImage: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
            case .paused:
                Button(action: onResume) {
                    Label("继续", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
                Button(action: onCancel) {
                    Label("取消", systemImage: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
            case .failed(let info):
                if info.recoverable {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                
                Button(action: onRemove) {
                    Label("移除", systemImage: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
            case .completed:
                HStack(spacing: 8) {
                    Button(action: { showInstallPrompt = true }) {
                        Label("安装", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button(action: onRemove) {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                
            case .retrying:
                Button(action: onCancel) {
                    Label("取消", systemImage: "xmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .controlSize(.small)
        .sheet(isPresented: $showInstallPrompt) {
            VStack(spacing: 20) {
                Text("是否要安装 \(task.displayName)?")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Button("取消") {
                        showInstallPrompt = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("安装") {
                        showInstallPrompt = false
                        isInstalling = true
                        Task {
                            await networkManager.installProduct(at: task.directory)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
        .sheet(isPresented: $isInstalling) {
            Group {
                if case .installing(let progress, let status) = networkManager.installationState {
                    InstallProgressView(
                        productName: task.displayName,
                        progress: progress,
                        status: status,
                        onCancel: {
                            networkManager.cancelInstallation()
                            isInstalling = false
                        },
                        onRetry: nil
                    )
                } else if case .completed = networkManager.installationState {
                    InstallProgressView(
                        productName: task.displayName,
                        progress: 1.0,
                        status: "安装完成",
                        onCancel: {
                            isInstalling = false
                        },
                        onRetry: nil
                    )
                } else if case .failed(let error) = networkManager.installationState {
                    InstallProgressView(
                        productName: task.displayName,
                        progress: 0,
                        status: "安装失败: \(error.localizedDescription)",
                        onCancel: {
                            isInstalling = false
                        },
                        onRetry: {
                            Task {
                                await networkManager.retryInstallation(at: task.directory)
                            }
                        }
                    )
                } else {
                    InstallProgressView(
                        productName: task.displayName,
                        progress: 0,
                        status: "准备安装...",
                        onCancel: {
                            networkManager.cancelInstallation()
                            isInstalling = false
                        },
                        onRetry: nil
                    )
                }
            }
            .frame(minWidth: 400, minHeight: 200)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private func openInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    private func formatRemainingTime(totalSize: Int64, downloadedSize: Int64, speed: Double) -> String {
        guard speed > 0 else { return "" }
        
        let remainingBytes = Double(totalSize - downloadedSize)
        let remainingSeconds = Int(remainingBytes / speed)
        
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(task.displayName)
                    .font(.headline)
                
                Spacer()
                
                Text(task.version)
                    .foregroundColor(.secondary)
            }
            
            // 下载目录
            Text(task.directory.path)
                .font(.caption)
                .foregroundColor(.blue)
                .lineLimit(1)
                .truncationMode(.middle)
                .onTapGesture {
                    openInFinder(task.directory)
                }
            
            // 状态标签（移到目录下方）
            statusLabel
                .padding(.vertical, 2)
            
            // 进度信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 4) {
                        Text(formatFileSize(task.totalDownloadedSize))
                        Text("/")
                        Text(formatFileSize(task.totalSize))
                    }
                    
                    Spacer()
                    
                    if task.totalSpeed > 0 {
                        Text(formatRemainingTime(
                            totalSize: task.totalSize,
                            downloadedSize: task.totalDownloadedSize,
                            speed: task.totalSpeed
                        ))
                        .foregroundColor(.secondary)
                    }
                    
                    Text("\(Int(task.totalProgress * 100))%")
                    
                    if task.totalSpeed > 0 {
                        Text(formatSpeed(task.totalSpeed))
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                
                ProgressView(value: task.totalProgress)
                    .progressViewStyle(.linear)
            }

            if !task.productsToDownload.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: { 
                        withAnimation {
                            isPackageListExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: isPackageListExpanded ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary)
                            Text("产品和包列表")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isPackageListExpanded {
                        ScrollView {
                            ForEach(task.productsToDownload, id: \.sapCode) { product in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "cube.box")
                                            .foregroundColor(.blue)
                                        Text("\(product.sapCode) (\(product.version))")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.vertical, 2)
                                    
                                    ForEach(product.packages) { package in
                                        PackageRow(
                                            package: package,
                                            isCurrentPackage: task.currentPackage?.id == package.id
                                        )
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }

            HStack {
                Spacer()
                actionButtons
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.primary.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct PackageRow: View {
    @ObservedObject var package: Package
    let isCurrentPackage: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // 第一行：包名和类型标签
            HStack {
                // 添加缩进
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 20)
                
                Text(package.fullPackageName)
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Text(package.type)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(2)
                
                Spacer()
                
                // 非下载状态只显示状态文本
                if !isCurrentPackage || package.status != .downloading {
                    Text(package.status.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 如果是当前下载的包，显示进度信息
            if isCurrentPackage && package.status == .downloading {
                VStack(spacing: 2) {
                    // 进度信息也需要缩进对齐
                    HStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                        
                        ProgressView(value: package.progress)
                            .progressViewStyle(.linear)
                        
                        Text("\(Int(package.progress * 100))% \(package.formattedSpeed)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // 已下载大小和总大小也需要缩进对齐
                    HStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                        
                        Text("\(package.formattedDownloadedSize) / \(package.formattedSize)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isCurrentPackage ? Color.blue.opacity(0.05) : Color.clear)
        .cornerRadius(4)
    }
}

// 在文件末尾添加预览
#Preview("下载中") {
    struct PreviewWrapper: View {
        @StateObject private var task: NewDownloadTask
        
        init() {
            let task = NewDownloadTask(
                sapCode: "PHSP",
                version: "26.0.0",
                language: "zh_CN",
                displayName: "Adobe Photoshop",
                directory: URL(fileURLWithPath: "/Users/Downloads/Install PHSP_26.0-zh_CN-macuniversal.app"),
                productsToDownload: [
                    ProductsToDownload(
                        sapCode: "PHSP",
                        version: "26.0.0",
                        buildGuid: "123",
                        applicationJson: ""
                    ),
                    ProductsToDownload(
                        sapCode: "ACR",
                        version: "9.6.0",
                        buildGuid: "456",
                        applicationJson: ""
                    )
                ],
                retryCount: 0,
                createAt: Date(),
                totalStatus: .downloading(DownloadStatus.DownloadInfo(
                    fileName: "AdobePhotoshop26-Core.zip",
                    currentPackageIndex: 0,
                    totalPackages: 8,
                    startTime: Date(),
                    estimatedTimeRemaining: nil
                )),
                totalProgress: 0.35,
                totalDownloadedSize: 738_197_504,
                totalSize: 2_147_483_648,
                totalSpeed: 1_048_576
            )
            
            // PHSP 包
            let phspPackages = [
                // 正在下载的包
                Package(
                    type: "core",
                    fullPackageName: "AdobePhotoshop26-Core.zip",
                    downloadSize: 2_112_950_169,
                    downloadURL: "/products/PHSP/AdobePhotoshop26-Core.zip"
                ),
                // 等待下载的包
                Package(
                    type: "core",
                    fullPackageName: "AdobePhotoshop26-Core_stripped.zip",
                    downloadSize: 1_874_257_058,
                    downloadURL: "/products/PHSP/AdobePhotoshop26-Core_stripped.zip"
                ),
                // 已完成的包
                Package(
                    type: "core",
                    fullPackageName: "AdobePhotoshop26-nl_NL.zip",
                    downloadSize: 490_628,
                    downloadURL: "/products/PHSP/AdobePhotoshop26-nl_NL.zip"
                )
            ]
            
            // ACR 包
            let acrPackages = [
                // 等待下载的包
                Package(
                    type: "core",
                    fullPackageName: "AdobeCameraRaw8.0All.zip",
                    downloadSize: 255_223_665,
                    downloadURL: "/products/ACR/AdobeCameraRaw8.0All.zip"
                ),
                // 失败的包
                Package(
                    type: "core",
                    fullPackageName: "AdobeCameraRaw8.0-support.zip",
                    downloadSize: 76_896_003,
                    downloadURL: "/products/ACR/AdobeCameraRaw8.0-support.zip"
                )
            ]
            
            // 设置包的状态
            phspPackages[0].status = .downloading
            phspPackages[0].downloadedSize = 738_197_504
            phspPackages[0].progress = 0.35
            phspPackages[0].speed = 1_048_576
            
            phspPackages[1].status = .waiting
            
            phspPackages[2].status = .completed
            phspPackages[2].downloaded = true
            phspPackages[2].progress = 1.0
            
            acrPackages[0].status = .waiting
            
            acrPackages[1].status = .failed("下载失败")
            
            task.productsToDownload[0].packages = phspPackages
            task.productsToDownload[1].packages = acrPackages
            
            // 设置当前包
            task.currentPackage = phspPackages[0]
            
            self._task = StateObject(wrappedValue: task)
        }
        
        var body: some View {
            DownloadProgressView(
                task: task,
                onCancel: {},
                onPause: {},
                onResume: {},
                onRetry: {},
                onRemove: {}
            )
            .environmentObject(NetworkManager())
            .padding()
            .frame(width: 600)
        }
    }
    
    return PreviewWrapper()
}

// 添加一个新的预览，默认展开包列表
#Preview("下载中(展开包列表)") {
    struct PreviewWrapper: View {
        @State private var isExpanded = true
        let task: NewDownloadTask
        
        var body: some View {
            DownloadProgressView(
                task: task,
                onCancel: {},
                onPause: {},
                onResume: {},
                onRetry: {},
                onRemove: {}
            )
            .environmentObject(NetworkManager())
            .padding()
            .frame(width: 600)
        }
    }
    
    let task = NewDownloadTask(
        sapCode: "PHSP",
        version: "26.0.0",
        language: "zh_CN",
        displayName: "Adobe Photoshop",
        directory: URL(fileURLWithPath: "/Users/Downloads/Install Photoshop_26.0-zh_CN.app"),
        productsToDownload: [
            ProductsToDownload(
                sapCode: "PHSP",
                version: "26.0.0",
                buildGuid: "123",
                applicationJson: ""
            ),
            ProductsToDownload(
                sapCode: "ACR",
                version: "9.6.0",
                buildGuid: "456",
                applicationJson: ""
            )
        ],
        retryCount: 0,
        createAt: Date(),
        totalStatus: .downloading(DownloadStatus.DownloadInfo(
            fileName: "AdobePhotoshop26-Core.zip",
            currentPackageIndex: 0,
            totalPackages: 8,
            startTime: Date(),
            estimatedTimeRemaining: nil
        )),
        totalProgress: 0.35,
        totalDownloadedSize: 738_197_504,
        totalSize: 2_147_483_648,
        totalSpeed: 1_048_576
    )
    
    // 添加包
    task.productsToDownload[0].packages = [
        Package(
            type: "core",
            fullPackageName: "AdobePhotoshop26-Core.zip",
            downloadSize: 1_073_741_824,
            downloadURL: "/products/PHSP/AdobePhotoshop26-Core.zip"
        ),
        Package(
            type: "non-core",
            fullPackageName: "AdobePhotoshop26-Support.zip",
            downloadSize: 536_870_912,
            downloadURL: "/products/PHSP/AdobePhotoshop26-Support.zip"
        )
    ]
    
    task.productsToDownload[1].packages = [
        Package(
            type: "core",
            fullPackageName: "ACR-Core.zip",
            downloadSize: 268_435_456,
            downloadURL: "/products/ACR/ACR-Core.zip"
        )
    ]
    
    // 设置当前包和进度
    task.currentPackage = task.productsToDownload[0].packages[0]
    task.currentPackage?.downloadedSize = 738_197_504
    task.currentPackage?.progress = 0.35
    task.currentPackage?.speed = 1_048_576
    task.currentPackage?.status = .downloading
    
    return PreviewWrapper(task: task)
}

#Preview("准备中") {
    let task = NewDownloadTask(
        sapCode: "PHSP",
        version: "26.0.0",
        language: "zh_CN",
        displayName: "Adobe Photoshop",
        directory: URL(fileURLWithPath: "/Users/Downloads/Install Photoshop_26.0-zh_CN.app"),
        productsToDownload: [],
        retryCount: 0,
        createAt: Date(),
        totalStatus: .preparing(DownloadStatus.PrepareInfo(
            message: "正在准备下载...",
            timestamp: Date(),
            stage: .initializing
        )),
        totalProgress: 0,
        totalDownloadedSize: 0,
        totalSize: 2_147_483_648,
        totalSpeed: 0
    )
    
    return DownloadProgressView(
        task: task,
        onCancel: {},
        onPause: {},
        onResume: {},
        onRetry: {},
        onRemove: {}
    )
    .environmentObject(NetworkManager())
    .padding()
    .frame(width: 600)
}

#Preview("已完成") {
    let task = NewDownloadTask(
        sapCode: "PHSP",
        version: "26.0.0",
        language: "zh_CN",
        displayName: "Adobe Photoshop",
        directory: URL(fileURLWithPath: "/Users/Downloads/Install Photoshop_26.0-zh_CN.app"),
        productsToDownload: [
            ProductsToDownload(
                sapCode: "PHSP",
                version: "26.0.0",
                buildGuid: "123",
                applicationJson: ""
            )
        ],
        retryCount: 0,
        createAt: Date().addingTimeInterval(-3600),
        totalStatus: .completed(DownloadStatus.CompletionInfo(
            timestamp: Date(),
            totalTime: 3600,
            totalSize: 2_147_483_648
        )),
        totalProgress: 1.0,
        totalDownloadedSize: 2_147_483_648,
        totalSize: 2_147_483_648,
        totalSpeed: 0
    )
    
    // 添加已完成的包
    task.productsToDownload[0].packages = [
        Package(
            type: "core",
            fullPackageName: "AdobePhotoshop26-Core.zip",
            downloadSize: 1_073_741_824,
            downloadURL: "/products/PHSP/AdobePhotoshop26-Core.zip"
        )
    ]
    task.productsToDownload[0].packages[0].downloaded = true
    task.productsToDownload[0].packages[0].progress = 1.0
    task.productsToDownload[0].packages[0].status = .completed
    
    return DownloadProgressView(
        task: task,
        onCancel: {},
        onPause: {},
        onResume: {},
        onRetry: {},
        onRemove: {}
    )
    .environmentObject(NetworkManager())
    .padding()
    .frame(width: 600)
}

#Preview("失败") {
    let task = NewDownloadTask(
        sapCode: "PHSP",
        version: "26.0.0",
        language: "zh_CN",
        displayName: "Adobe Photoshop",
        directory: URL(fileURLWithPath: "/Users/Downloads/Install Photoshop_26.0-zh_CN.app"),
        productsToDownload: [
            ProductsToDownload(
                sapCode: "PHSP",
                version: "26.0.0",
                buildGuid: "123",
                applicationJson: ""
            )
        ],
        retryCount: 3,
        createAt: Date(),
        totalStatus: .failed(DownloadStatus.FailureInfo(
            message: "网络连接已断开",
            error: NetworkError.noConnection,
            timestamp: Date(),
            recoverable: true
        )),
        totalProgress: 0.5,
        totalDownloadedSize: 1_073_741_824,
        totalSize: 2_147_483_648,
        totalSpeed: 0
    )
    
    return DownloadProgressView(
        task: task,
        onCancel: {},
        onPause: {},
        onResume: {},
        onRetry: {},
        onRemove: {}
    )
    .environmentObject(NetworkManager())
    .padding()
    .frame(width: 600)
}
