//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct InstallProgressView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    let productName: String
    let progress: Double
    let status: String
    let onCancel: () -> Void
    let onRetry: (() -> Void)?
    
    private var isCompleted: Bool {
        progress >= 1.0 || status == String(localized: "安装完成")
    }
    
    private var isFailed: Bool {
        status.contains(String(localized: "失败"))
    }
    
    private var progressText: String {
        if isCompleted {
            return String(localized: "安装完成")
        } else {
            return "\(Int(progress * 100))%"
        }
    }
    
    private var statusIcon: String {
        if isCompleted {
            return "checkmark.circle.fill"
        } else if isFailed {
            return "xmark.circle.fill"
        } else {
            return "arrow.down.circle.fill"
        }
    }
    
    private var statusColor: Color {
        if isCompleted {
            return .green
        } else if isFailed {
            return .red
        } else {
            return .blue
        }
    }
    
    private var statusTitle: String {
        if isCompleted {
            return String(localized: "\(productName) 安装完成")
        } else if isFailed {
            return String(localized: "\(productName) 安装失败")
        } else {
            return String(localized: "正在安装 \(productName)")
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)
                
                Text(statusTitle)
                    .font(.headline)
            }
            .padding(.horizontal, 20)

            if !isFailed {
                ProgressSection(progress: progress, progressText: progressText)
            }

            LogSection(logs: networkManager.installationLogs)

            if isFailed {
                ErrorSection(
                    status: status, isFailed: isFailed
                )
            }

            ButtonSection(
                isCompleted: isCompleted,
                isFailed: isFailed,
                onCancel: onCancel,
                onRetry: onRetry
            )
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

private struct ProgressSection: View {
    let progress: Double
    let progressText: String
    
    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
            
            Text(progressText)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 20)
    }
}

private struct LogSection: View {
    let logs: [String]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(logs.suffix(1000).enumerated()), id: \.offset) { index, log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .id(index)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .frame(height: 150)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .onChange(of: logs) { newValue in
                if !newValue.isEmpty {
                    withAnimation {
                        proxy.scrollTo(newValue.count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ErrorSection: View {
    let status: String
    let isFailed: Bool

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {
            Text("错误详情:")
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            if isFailed {
                HStack {
                    Text("自行安装命令:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                    CommandPopover()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

private struct CommandSection: View {
    let command: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("自行安装命令:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text(command)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity,alignment: .leading)
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ButtonSection: View {
    let isCompleted: Bool
    let isFailed: Bool
    let onCancel: () -> Void
    let onRetry: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            if isFailed {
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                
                Button(action: onCancel) {
                    Label("关闭", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else if isCompleted {
                Button(action: onCancel) {
                    Label("关闭", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button(action: onCancel) {
                    Label("取消", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct CommandPopover: View {
    @EnvironmentObject private var networkManager: NetworkManager
    @State private var showPopover = false
    @State private var showCopiedAlert = false
    
    var body: some View {
        Button(action: { showPopover.toggle() }) {
            Image(systemName: "terminal.fill")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button("复制命令") {
                    let command = networkManager.installCommand
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                    showCopiedAlert = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedAlert = false
                    }
                }

                if showCopiedAlert {
                    Text("已复制")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                let command = networkManager.installCommand
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding()
            .frame(width: 400)
        }
    }
}

#Preview("安装中带日志") {
    let networkManager = NetworkManager()
    return InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.45,
        status: "正在安装核心组件...",
        onCancel: {},
        onRetry: nil
    )
    .environmentObject(networkManager)
    .onAppear {
        let previewLogs = [
            "正在准备安装...",
            "Progress: 10%",
            "Progress: 20%",
            "Progress: 30%",
            "Progress: 40%",
            "Progress: 45%",
            "正在安装核心组件...",
        ]
        
        for (index, log) in previewLogs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                networkManager.installationLogs.append(log)
            }
        }
    }
}

#Preview("安装失败带日志") {
    let networkManager = NetworkManager()
    return InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.0,
        status: "安装失败: 权限被拒绝",
        onCancel: {},
        onRetry: {}
    )
    .environmentObject(networkManager)
    .onAppear {
        networkManager.installCommand = "sudo \"/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup\" --install=1 --driverXML=\"/Users/demo/Downloads/Adobe Photoshop/driver.xml\""
        
        let previewLogs = [
            "正在准备安装...",
            "Progress: 10%",
            "Progress: 20%",
            "检查权限...",
            "权限检查失败",
            "安装失败: 权限被拒绝"
        ]
        
        for (index, log) in previewLogs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                networkManager.installationLogs.append(log)
            }
        }
    }
}

#Preview("安装完成带日志") {
    let networkManager = NetworkManager()
    return InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 1.0,
        status: "安装完成",
        onCancel: {},
        onRetry: nil
    )
    .environmentObject(networkManager)
    .onAppear {
        let previewLogs = [
            "正在准备安装...",
            "Progress: 25%",
            "Progress: 50%",
            "Progress: 75%",
            "Progress: 100%",
            "正在完成安装...",
            "安装完成"
        ]
        
        for (index, log) in previewLogs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                networkManager.installationLogs.append(log)
            }
        }
    }
}

#Preview("在深色模式下带日志") {
    let networkManager = NetworkManager()
    return InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.75,
        status: "正在安装...",
        onCancel: {},
        onRetry: nil
    )
    .environmentObject(networkManager)
    .preferredColorScheme(.dark)
    .onAppear {
        let previewLogs = [
            "正在准备安装...",
            "Progress: 25%",
            "Progress: 50%",
            "Progress: 75%",
            "正在安装..."
        ]
        
        for (index, log) in previewLogs.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                networkManager.installationLogs.append(log)
            }
        }
    }
}
