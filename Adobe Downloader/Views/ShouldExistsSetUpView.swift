//
//  ShouldExistsSetUpView.swift
//  Adobe Downloader
//
//  Created by X1a0He on 11/11/24.
//

import SwiftUI

struct ShouldExistsSetUpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.orange)
            .padding(.bottom, 5)
            .frame(alignment: .bottomTrailing)

            Text("未检测到 Adobe Setup 组件")
                .font(.system(size: 24))
                .bold()

            VStack(spacing: 4) {
                Text("程序检测到你的系统中不存在 Adobe Setup 组件")
                    .multilineTextAlignment(.center)
                
                Text("可能导致无法使用安装功能，请确保是否使用安装功能")
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                Button(action: {
                    showingAlert = true
                }) {
                    Label("不使用安装功能", systemImage: "exclamationmark.triangle.fill")
                        .frame(minWidth: 0,maxWidth: 360)
                        .frame(height: 32)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .alert("确认", isPresented: $showingAlert) {
                    Button("取消", role: .cancel) { }
                    Button("确定", role: .destructive) {
                        dismiss()
                    }
                } message: {
                    Text("你确定不使用安装功能吗？")
                }
                .disabled(isDownloading)
                Button(action: {
                    isDownloading = true
                    // TODO
                }) {
                    if isDownloading {
                        ProgressView(value: downloadProgress) {
                            Label("正在下载 X1a0He CC \(Int(downloadProgress * 100))%", systemImage: "arrow.down")
                                .frame(height: 32)
                                .frame(maxWidth: 360)
                                .frame(alignment: .center)
                                .font(.system(size: 14))
                        }
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .frame(maxWidth: 360)
                    } else {
                        Label("下载 X1a0He CC 组件", systemImage: "arrow.down")
                            .frame(minWidth: 0, maxWidth: 360)
                            .frame(height: 32)
                            .font(.system(size: 14))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isDownloading)

                Button(action: {
                    if let url = URL(string: "https://creativecloud.adobe.com/apps/download/creative-cloud") {
                        NSWorkspace.shared.open(url)
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }) {
                    Label("前往 Adobe Creative Cloud", systemImage: "cloud.fill")
                        .frame(minWidth: 0,maxWidth: 360)
                        .frame(height: 32)
                        .font(.system(size: 14))
                }
                .disabled(isDownloading)

                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.terminate(nil)
                    }
                }) {
                    Label("退出", systemImage: "xmark")
                        .frame(minWidth: 0, maxWidth: 360)
                        .frame(height: 32)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.cancelAction)
                .disabled(isDownloading)
            }
        }
        .frame(width: 400)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

#Preview {
    ShouldExistsSetUpView()
}
