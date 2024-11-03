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
    @State private var expandedProducts: Set<String> = []
    
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
                    if task.displayInstallButton {
                        Button(action: { showInstallPrompt = true }) {
                            Label("安装", systemImage: "square.and.arrow.down.on.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    
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
            if task.displayInstallButton {
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

            Text(task.directory.path)
                .font(.caption)
                .foregroundColor(.blue)
                .lineLimit(1)
                .truncationMode(.middle)
                .onTapGesture {
                    openInFinder(task.directory)
                }

            statusLabel
                .padding(.vertical, 2)

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
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(task.productsToDownload, id: \.sapCode) { product in
                                    ProductRow(
                                        product: product,
                                        isCurrentProduct: task.currentPackage?.id == product.packages.first?.id,
                                        expandedProducts: $expandedProducts
                                    )
                                }
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

struct ProductRow: View {
    @ObservedObject var product: ProductsToDownload
    let isCurrentProduct: Bool
    @Binding var expandedProducts: Set<String>
    
    private var completedPackages: Int {
        product.packages.filter { $0.status == .completed }.count
    }
    
    private var totalPackages: Int {
        product.packages.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation {
                    if expandedProducts.contains(product.sapCode) {
                        expandedProducts.remove(product.sapCode)
                    } else {
                        expandedProducts.insert(product.sapCode)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "cube.box")
                        .foregroundColor(.blue)
                    Text("\(product.sapCode) (\(product.version))")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(completedPackages)/\(totalPackages)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: expandedProducts.contains(product.sapCode) ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
            if expandedProducts.contains(product.sapCode) {
                VStack(spacing: 8) {
                    ForEach(product.packages) { package in
                        PackageRow(package: package)
                            .padding(.horizontal)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
                .padding(.leading, 24)
            }
        }
    }
}

struct PackageRow: View {
    @ObservedObject var package: Package
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
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
                
                if package.status == .downloading {
                    Text("\(Int(package.progress * 100))%")
                        .font(.caption)
                } else {
                    Text(package.status.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if package.status == .downloading {
                VStack(spacing: 2) {
                    ProgressView(value: package.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text("\(package.formattedDownloadedSize) / \(package.formattedSize)")
                        Spacer()
                        if package.speed > 0 {
                            Text(formatSpeed(package.speed))
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
