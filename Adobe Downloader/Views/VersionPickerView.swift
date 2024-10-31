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
    
    private var sortedVersions: [(version: String, platform: String)] {
        product.versions
            .map { (version: $0.key, platform: $0.value.apPlatform) }
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

            List {
                ForEach(sortedVersions, id: \.version) { version in
                    Button(action: {
                        onVersionSelected(version.version)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.version)
                                    .font(.system(.body, design: .monospaced))
                                Text(getPlatformDisplayName(version.platform))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 300, height: 400)
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
                )
            ],
            icons: []
        ),
        onVersionSelected: { _ in }
    )
}
