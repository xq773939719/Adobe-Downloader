//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct DownloadProgressView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    let task: DownloadTask
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
                    
                    Button(action: {
                        networkManager.removeTask(taskId: task.id, removeFiles: true)
                    }) {
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
                Text("是否要安装 \(task.productName)?")
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
                            await networkManager.installProduct(at: task.destinationURL)
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
                        productName: task.productName,
                        progress: progress,
                        status: status
                    ) {
                        networkManager.cancelInstallation()
                        isInstalling = false
                    }
                } else if case .completed = networkManager.installationState {
                    InstallProgressView(
                        productName: task.productName,
                        progress: 1.0,
                        status: "安装完成"
                    ) {
                        isInstalling = false
                    }
                } else {
                    InstallProgressView(
                        productName: task.productName,
                        progress: 0,
                        status: "准备安装..."
                    ) {
                        networkManager.cancelInstallation()
                        isInstalling = false
                    }
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.productName)
                        .font(.headline)
                    Text(task.destinationURL.path)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onTapGesture {
                            openInFinder(task.destinationURL)
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(task.version)
                        .foregroundColor(.secondary)
                    statusLabel
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .cornerRadius(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 4) {
                        Text(formatFileSize(task.downloadedSize))
                        Text("/")
                        Text(formatFileSize(task.totalSize))
                    }
                    
                    Spacer()

                    HStack(spacing: 8) {
                        Text("\(Int(task.progress * 100))%")
                            .foregroundColor(.primary)

                        if task.speed > 0 {
                            Text(formatSpeed(task.speed))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
            }

            if task.packages.count > 0 {
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
                            Text("包列表 (\(task.packages.count))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isPackageListExpanded {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(task.packages.indices, id: \.self) { index in
                                    let package = task.packages[index]
                                    PackageProgressView(package: package, index: index, total: task.packages.count)
                                }
                            }
                        }
                        .frame(maxHeight: 120)
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

struct PackageProgressView: View {
    let package: DownloadTask.Package
    let index: Int
    let total: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(package.name)")
                    .font(.caption)
                    .foregroundColor(package.downloaded ? .secondary : .primary)
                
                Text("(\(index + 1)/\(total))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if package.downloaded {
                    Text("已完成")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if package.downloadedSize > 0 {
                    HStack(spacing: 4) {
                        Text("\(Int(package.progress * 100))%")
                        Text(formatSpeed(package.speed))
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                } else {
                    Text("等待中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !package.downloaded && package.downloadedSize > 0 {
                ProgressView(value: package.progress)
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
                
                HStack {
                    Text(formatFileSize(package.downloadedSize))
                    Text("/")
                    Text(formatFileSize(package.size))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
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
}

#Preview {
    DownloadProgressView(
        task: DownloadTask(
            sapCode: "PHSP",
            version: "24.0",
            language: "zh_CN",
            productName: "Adobe Photoshop",
            status: .downloading(DownloadTask.DownloadStatus.DownloadInfo(
                fileName: "PhotoshopSupport.dmg",
                currentPackageIndex: 1,
                totalPackages: 4,
                startTime: Date(),
                estimatedTimeRemaining: nil
            )),
            progress: 0.45,
            downloadedSize: 1024 * 1024 * 450,
            totalSize: 1024 * 1024 * 1000,
            speed: 1024 * 1024 * 2,
            currentFileName: "PhotoshopSupport.dmg",
            destinationURL: URL(fileURLWithPath: "/tmp"),
            packages: [
                .init(
                    name: "PhotoshopCore.dmg",
                    Path: "/path/to/core",
                    size: 1024 * 1024 * 300,
                    downloadedSize: 1024 * 1024 * 300,
                    progress: 1.0,
                    speed: 0,
                    status: .completed,
                    type: "core",
                    downloaded: true,
                    lastUpdated: Date(),
                    lastRecordedSize: 1024 * 1024 * 300
                ),
                .init(
                    name: "PhotoshopSupport.dmg",
                    Path: "/path/to/support",
                    size: 1024 * 1024 * 400,
                    downloadedSize: 1024 * 1024 * 150,
                    progress: 0.375,
                    speed: 1024 * 1024 * 2,
                    status: .downloading,
                    type: "support",
                    downloaded: false,
                    lastUpdated: Date(),
                    lastRecordedSize: 1024 * 1024 * 150
                ),
                .init(
                    name: "PhotoshopOptional.dmg",
                    Path: "/path/to/optional",
                    size: 1024 * 1024 * 200,
                    downloadedSize: 0,
                    progress: 0,
                    speed: 0,
                    status: .waiting,
                    type: "optional",
                    downloaded: false,
                    lastUpdated: Date(),
                    lastRecordedSize: 0
                )
            ]
        ),
        onCancel: {},
        onPause: {},
        onResume: {},
        onRetry: {},
        onRemove: {}
    )
    .environmentObject(NetworkManager())
    .padding()
    .frame(width: 500)
}
