//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct VersionPickerView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @State private var expandedVersions: Set<String> = []
    
    let sap: Sap
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(sap.displayName)")
                    .font(.headline)
                Text("选择版本")
                    .foregroundColor(.secondary)
                Spacer()
                Button("取消") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(sap.versions.sorted { $0.key > $1.key }), id: \.key) { version, info in
                        if networkManager.allowedPlatform.contains(info.apPlatform) {
                            VStack(spacing: 0) {
                                Button(action: {
                                    if info.dependencies.isEmpty {
                                        onSelect(version)
                                        dismiss()
                                    } else {
                                        withAnimation {
                                            if expandedVersions.contains(version) {
                                                expandedVersions.remove(version)
                                            } else {
                                                expandedVersions.insert(version)
                                            }
                                        }
                                    }
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(version)
                                                .font(.headline)
                                            Text(info.apPlatform)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if let existingPath = networkManager.isVersionDownloaded(
                                            sap: sap,
                                            version: version,
                                            language: defaultLanguage
                                        ) {
                                            Button(action: {
                                                NSWorkspace.shared.selectFile(
                                                    existingPath.path,
                                                    inFileViewerRootedAtPath: existingPath.deletingLastPathComponent().path
                                                )
                                            }) {
                                                Text("已存在")
                                                    .font(.caption)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.blue)
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        
                                        if !info.dependencies.isEmpty {
                                            Image(systemName: expandedVersions.contains(version) ? "chevron.down" : "chevron.right")
                                                .foregroundColor(.secondary)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                if expandedVersions.contains(version) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("依赖包:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 8)
                                            .padding(.leading, 16)
                                        
                                        ForEach(info.dependencies, id: \.sapCode) { dependency in
                                            HStack(spacing: 8) {
                                                Image(systemName: "cube.box")
                                                    .foregroundColor(.blue)
                                                    .frame(width: 16)
                                                Text("\(dependency.sapCode) (\(dependency.version))")
                                                    .font(.caption)
                                                Spacer()
                                            }
                                            .padding(.leading, 24)
                                        }
                                        
                                        Button("下载此版本") {
                                            onSelect(version)
                                            dismiss()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .padding(.top, 8)
                                        .padding(.leading, 16)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 8)
                                }
                            }
                            .padding(.horizontal)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 400, height: 500)
    }
}

#Preview {
    let networkManager = NetworkManager()
    
    return VersionPickerView(
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
        onSelect: { version in
            print("Selected version: \(version)")
        }
    )
    .environmentObject(networkManager)
}
