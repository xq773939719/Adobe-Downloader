//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct VersionPickerView: View {
    let product: Product
    let onVersionSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    
    private var sortedVersions: [(version: String, platform: String, exists: Bool)] {
        product.versions
            .map { version -> (version: String, platform: String, exists: Bool) in
                let installerPath: String
                let appName = "Install \(product.sapCode)_\(version.key)-\(defaultLanguage)-\(version.value.apPlatform).app"
                if useDefaultDirectory && !defaultDirectory.isEmpty {
                    installerPath = (defaultDirectory as NSString).appendingPathComponent(appName)
                } else {
                    let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
                    installerPath = (downloadsPath as NSString).appendingPathComponent(appName)
                }
                return (
                    version: version.key,
                    platform: version.value.apPlatform,
                    exists: FileManager.default.fileExists(atPath: installerPath)
                )
            }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                    Text("选择版本")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(sortedVersions, id: \.version) { version in
                        Button(action: {
                            onVersionSelected(version.version)
                            dismiss()
                        }) {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(version.version)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: getPlatformIcon(version.platform))
                                            .foregroundColor(.secondary)
                                        Text(getPlatformDisplayName(version.platform))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if version.exists {
                                    Text("已下载")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.01))
                        .cornerRadius(8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        Divider()
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 360, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func getPlatformDisplayName(_ platform: String) -> String {
        switch platform {
        case "macuniversal":
            return "Universal (Intel/Apple Silicon)"
        case "macarm64":
            return "Apple Silicon"
        case "osx10-64", "osx10":
            return "Intel"
        default:
            return platform
        }
    }
    
    private func getPlatformIcon(_ platform: String) -> String {
        switch platform {
        case "macuniversal":
            return "cpu"
        case "macarm64":
            return "memorychip"
        case "osx10-64", "osx10":
            return "desktopcomputer"
        default:
            return "questionmark.circle"
        }
    }
}

#Preview {
    VersionPickerView(
        product: Product(
            id: "PHSP",
            hidden: false,
            displayName: "Photoshop",
            sapCode: "PHSP",
            versions: [
                "25.0.0": Product.ProductVersion(
                    sapCode: "PHSP",
                    baseVersion: "25.0.0",
                    productVersion: "25.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: ""
                ),
                "24.6.0": Product.ProductVersion(
                    sapCode: "PHSP",
                    baseVersion: "24.6.0",
                    productVersion: "24.6.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: ""
                ),
                "24.5.0": Product.ProductVersion(
                    sapCode: "PHSP",
                    baseVersion: "24.5.0",
                    productVersion: "24.5.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: ""
                )
            ],
            icons: []
        ),
        onVersionSelected: { _ in }
    )
}
