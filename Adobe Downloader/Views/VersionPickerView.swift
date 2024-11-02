//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct VersionPickerView: View {
    let sap: Sap
    let onVersionSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @State private var expandedVersions: Set<String> = []
    
    private func getInstallerPath(version: String, platform: String) -> String {
        let appName = "Install \(sap.sapCode)_\(version)-\(defaultLanguage)-\(platform).app"
        if useDefaultDirectory && !defaultDirectory.isEmpty {
            return (defaultDirectory as NSString).appendingPathComponent(appName)
        } else {
            let downloadsPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
            return (downloadsPath as NSString).appendingPathComponent(appName)
        }
    }
    
    private func mapVersion(_ version: (key: String, value: Sap.Versions)) -> (version: String, platform: String, exists: Bool, dependencies: [Sap.Versions.Dependencies]) {
        let installerPath = getInstallerPath(version: version.key, platform: version.value.apPlatform)
        return (
            version: version.key,
            platform: version.value.apPlatform,
            exists: FileManager.default.fileExists(atPath: installerPath),
            dependencies: version.value.dependencies
        )
    }
    
    private var sortedVersions: [(version: String, platform: String, exists: Bool, dependencies: [Sap.Versions.Dependencies])] {
        sap.versions
            .map(mapVersion)
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                displayName: sap.displayName,
                onDismiss: { dismiss() }
            )
            
            Divider()

            VersionListView(
                versions: sortedVersions,
                expandedVersions: $expandedVersions,
                onVersionSelected: onVersionSelected,
                onDismiss: { dismiss() }
            )
        }
        .frame(width: 360, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - 子视图
private struct HeaderView: View {
    let displayName: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                Text("选择版本")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("取消", action: onDismiss)
                .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

private struct VersionListView: View {
    let versions: [(version: String, platform: String, exists: Bool, dependencies: [Sap.Versions.Dependencies])]
    @Binding var expandedVersions: Set<String>
    let onVersionSelected: (String) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(versions, id: \.version) { version in
                    VersionRowView(
                        version: version,
                        isExpanded: expandedVersions.contains(version.version),
                        onToggleExpand: {
                            withAnimation {
                                if expandedVersions.contains(version.version) {
                                    expandedVersions.remove(version.version)
                                } else {
                                    expandedVersions.insert(version.version)
                                }
                            }
                        },
                        onSelect: {
                            onVersionSelected(version.version)
                            onDismiss()
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct VersionRowView: View {
    let version: (version: String, platform: String, exists: Bool, dependencies: [Sap.Versions.Dependencies])
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                if version.dependencies.isEmpty {
                    onSelect()
                } else {
                    onToggleExpand()
                }
            }) {
                VersionRowContent(
                    version: version.version,
                    platform: version.platform,
                    exists: version.exists,
                    hasDependencies: !version.dependencies.isEmpty,
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.01))
            
            if isExpanded {
                DependenciesView(
                    dependencies: version.dependencies,
                    onSelect: onSelect
                )
            }
            
            Divider()
        }
    }
}

private struct VersionRowContent: View {
    let version: String
    let platform: String
    let exists: Bool
    let hasDependencies: Bool
    let isExpanded: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(version)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: getPlatformIcon(platform))
                        .foregroundColor(.secondary)
                    Text(getPlatformDisplayName(platform))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if exists {
                Text("已下载")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
            
            if hasDependencies {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct DependenciesView: View {
    let dependencies: [Sap.Versions.Dependencies]
    let onSelect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("依赖包:")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            ForEach(dependencies, id: \.sapCode) { dependency in
                HStack(spacing: 8) {
                    Image(systemName: "cube.box")
                        .foregroundColor(.blue)
                        .frame(width: 16)
                    Text("\(dependency.sapCode) (\(dependency.version))")
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            HStack {
                Spacer()
                Button("下载此版本", action: onSelect)
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.05))
    }
}

// 辅助函数移到外部
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

#Preview {
    VersionPickerView(
        sap: Sap(
            hidden: false,
            displayName: "Photoshop",
            sapCode: "PHSP",
            versions: [
                "26.0.0": Sap.Versions(
                    sapCode: "PHSP",
                    baseVersion: "26.0.0",
                    productVersion: "26.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [
                        Sap.Versions.Dependencies(sapCode: "ACR", version: "9.6"),
                        Sap.Versions.Dependencies(sapCode: "COCM", version: "1.0"),
                        Sap.Versions.Dependencies(sapCode: "COSY", version: "2.4.1")
                    ],
                    buildGuid: "b382ef03-c44a-4fd4-a9a1-3119ab0474b4"
                ),
                "25.0.0": Sap.Versions(
                    sapCode: "PHSP",
                    baseVersion: "25.0.0",
                    productVersion: "25.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [
                        Sap.Versions.Dependencies(sapCode: "ACR", version: "9.5"),
                        Sap.Versions.Dependencies(sapCode: "COCM", version: "1.0")
                    ],
                    buildGuid: "a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6"
                ),
                "24.0.0": Sap.Versions(
                    sapCode: "PHSP",
                    baseVersion: "24.0.0",
                    productVersion: "24.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: "q1w2e3r4-t5y6-u7i8-o9p0-a1s2d3f4g5h6"
                )
            ],
            icons: [
                Sap.ProductIcon(
                    size: "192x192",
                    url: "https://ffc-static-cdn.oobesaas.adobe.com/icons/PHSP/26.0.0/192x192.png"
                )
            ]
        ),
        onVersionSelected: { version in
            print("Selected version: \(version)")
        }
    )
}
