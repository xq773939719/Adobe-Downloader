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
    
    private var isCompleted: Bool {
        progress >= 1.0 || status == "安装完成"
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
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(isCompleted ? .green : .blue)
                
                Text(isCompleted ? "\(productName) 安装完成" : "正在安装 \(productName)")
                    .font(.headline)
            }

            VStack(spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                
                Text(progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack {
                Image(systemName: isCompleted ? "checkmark.circle" : "hourglass.circle")
                    .foregroundColor(isCompleted ? .green : .secondary)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isCompleted {
                Button(action: onCancel) {
                    Label("确定", systemImage: "checkmark.circle.fill")
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
        onCancel: {}
    )
}

#Preview("准备安装") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.0,
        status: "正在准备安装...",
        onCancel: {}
    )
}

#Preview("安装完成") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 1.0,
        status: "安装完成",
        onCancel: {}
    )
}

#Preview("在深色模式下") {
    InstallProgressView(
        productName: "Adobe Photoshop",
        progress: 0.75,
        status: "正在安装...",
        onCancel: {}
    )
    .preferredColorScheme(.dark)
} 
