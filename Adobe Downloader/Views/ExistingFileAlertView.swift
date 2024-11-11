//
//  ShouldExistsSetUpView.swift
//  Adobe Downloader
//
//  Created by X1a0He.
//

import SwiftUI

struct ExistingFileAlertView: View {
    let path: URL
    let onUseExisting: () -> Void
    let onRedownload: () -> Void
    let onCancel: () -> Void
    let iconImage: NSImage?
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let iconImage = iconImage {
                        Image(nsImage: iconImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .offset(x: 10, y: 4)
            }
            .padding(.bottom, 5)
            
            Text("安装程序已存在")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(path.path)
                        .foregroundColor(.blue)
                        .onTapGesture {
                            NSWorkspace.shared.activateFileViewerSelecting([path])
                        }
                }
            }

            VStack(spacing: 16) {
                Button(action: onUseExisting) {
                    Label("使用现有程序", systemImage: "checkmark.circle")
                        .frame(minWidth: 0,maxWidth: 260)
                        .frame(height: 32)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: onRedownload) {
                    Label("重新下载", systemImage: "arrow.down.circle")
                        .frame(minWidth: 0,maxWidth: 260)
                        .frame(height: 32)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(action: onCancel) {
                    Label("取消", systemImage: "xmark.circle")
                        .frame(minWidth: 0, maxWidth: 260)
                        .frame(height: 32)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}

#Preview {
    ExistingFileAlertView(
        path: URL(fileURLWithPath: "/Users/username/Downloads/Adobe/Adobe Downloader PHSP_25.0-en_US-macuniversal"),
        onUseExisting: {},
        onRedownload: {},
        onCancel: {},
        iconImage: NSImage(named: "PHSP")
    )
    .background(Color.black.opacity(0.3))
}

#Preview("Dark Mode") {
    ExistingFileAlertView(
        path: URL(fileURLWithPath: "/Users/username/Downloads/Adobe/Adobe Downloader PHSP_25.0-en_US-macuniversal"),
        onUseExisting: {},
        onRedownload: {},
        onCancel: {},
        iconImage: NSImage(named: "PHSP")
    )
    .background(Color.black.opacity(0.3))
    .preferredColorScheme(.dark)
}
