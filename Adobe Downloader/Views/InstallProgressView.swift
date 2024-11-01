//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct InstallProgressView: View {
    let productName: String
    let progress: Double
    let status: String
    let onCancel: () -> Void
    let onRetry: (() -> Void)?  // 重试回调
    
    private var isCompleted: Bool {
        progress >= 1.0 || status == "安装完成"
    }
    
    private var isFailed: Bool {
        status.contains("失败")
    }
    
    private var progressText: String {
        if isCompleted {
            return "安装完成"
        } else {
            return "\(Int(progress * 100))%"
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : 
                      (status.contains("失败") ? "xmark.circle.fill" : "arrow.down.circle.fill"))
                    .font(.title2)
                    .foregroundColor(isCompleted ? .green : 
                                   (status.contains("失败") ? .red : .blue))
                
                Text(isCompleted ? "\(productName) 安装完成" : 
                     (status.contains("失败") ? "\(productName) 安装失败" : "正在安装 \(productName)"))
                    .font(.headline)
            }

            VStack(spacing: 4) {
                if !status.contains("失败") {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                    
                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if status.contains("失败") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("错误详情:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                        
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)  // 允许用户选择和复制错误信息
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            } else {
                HStack {
                    Image(systemName: isCompleted ? "checkmark.circle" : "hourglass.circle")
                        .foregroundColor(isCompleted ? .green : .secondary)
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 根据状态显示不同的按钮
            HStack(spacing: 12) {
                if isFailed {
                    // 当安装失败时显示重试按钮
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
        }
        .padding()
        .frame(minWidth: 400, minHeight: 150)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview("安装中") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.45,
        status: "正在安装核心组件...",
        onCancel: {},
        onRetry: nil
    )
}

#Preview("准备安装") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.0,
        status: "正在准备安装...",
        onCancel: {},
        onRetry: nil
    )
}

#Preview("安装完成") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 1.0,
        status: "安装完成",
        onCancel: {},
        onRetry: nil
    )
}

#Preview("安装失败") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.0,
        status: "安装失败: 权限被拒绝",
        onCancel: {},
        onRetry: {}
    )
}

#Preview("在深色模式下") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.75,
        status: "正在安装...",
        onCancel: {},
        onRetry: nil
    )
    .preferredColorScheme(.dark)
}
