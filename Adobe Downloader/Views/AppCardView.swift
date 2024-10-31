//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//

import SwiftUI

class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "com.adobe.downloader.iconcache")
    
    func getIcon(for url: String) -> NSImage? {
        queue.sync {
            return cache[url]
        }
    }
    
    func setIcon(_ image: NSImage, for url: String) {
        queue.sync {
            self.cache[url] = image
        }
    }
}

struct AppCardView: View {
    let product: Product
    @EnvironmentObject private var networkManager: NetworkManager
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showVersionPicker = false
    @State private var selectedVersion: String = ""
    @State private var iconImage: NSImage? = nil

    private var isDownloading: Bool {
        networkManager.downloadTasks.contains { task in
            if task.sapCode == product.sapCode {
                if case .downloading = task.status {
                    return true
                }
                if case .preparing = task.status {
                    return true
                }
                if case .waiting = task.status {
                    return true
                }
                if case .retrying = task.status {
                    return true
                }
            }
            return false
        }
    }

    var body: some View {
        VStack {
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
            .onAppear {
                loadIcon()
            }

            Text(product.displayName)
                .font(.system(size: 16))
                .fontWeight(.bold)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text("可用版本: \(product.versions.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(height: 20)

            Spacer()

            Button(action: { showVersionPicker = true }) {
                Label(isDownloading ? "下载中" : "下载",
                      systemImage: isDownloading ? "hourglass.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 14))
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(isDownloading ? .gray : .blue)
            .disabled(isDownloading)
        }
        .padding()
        .frame(width: 250, height: 200)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 2)
        )
        .sheet(isPresented: $showVersionPicker) {
            VersionPickerView(product: product) { version in
                selectedVersion = version
                startDownload(version)
            }
        }
        .alert("下载错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
            Button("重试") {
                if !selectedVersion.isEmpty {
                    startDownload(selectedVersion)
                }
            }
        } message: {
            Text(errorMessage)
        }
    }

    private func loadIcon() {
        guard let bestIcon = product.getBestIcon(),
              let iconURL = URL(string: bestIcon.url) else {
            return
        }

        if let cachedImage = IconCache.shared.getIcon(for: bestIcon.url) {
            self.iconImage = cachedImage
            return
        }
        
        Task {
            do {
                var request = URLRequest(url: iconURL)
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let image = NSImage(data: data) else {
                    throw URLError(.badServerResponse)
                }

                IconCache.shared.setIcon(image, for: bestIcon.url)
                
                await MainActor.run {
                    self.iconImage = image
                }
            } catch {
                if let localImage = NSImage(named: product.displayName) {
                    await MainActor.run {
                        self.iconImage = localImage
                    }
                }
            }
        }
    }

    private func startDownload(_ version: String) {
        Task {
            do {
                let destinationURL: URL
                if useDefaultDirectory && !defaultDirectory.isEmpty {
                    destinationURL = URL(fileURLWithPath: defaultDirectory)
                        .appendingPathComponent("Install \(product.displayName)_\(version)-zh_CN.app")
                } else {
                    let panel = NSOpenPanel()
                    panel.title = "选择保存位置"
                    panel.canCreateDirectories = true
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    
                    guard await MainActor.run(body: { panel.runModal() == .OK }),
                          let selectedURL = panel.url else {
                        return
                    }
                    destinationURL = selectedURL
                        .appendingPathComponent("Install \(product.displayName)_\(version)-zh_CN.app")
                }
                try await networkManager.startDownload(
                    sapCode: product.sapCode,
                    version: version,
                    language: "zh_CN",
                    destinationURL: destinationURL
                )
                
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    AppCardView(product: Product(
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
        icons: [
            Product.ProductIcon(
                size: "192x192",
                url: "https://ffc-static-cdn.oobesaas.adobe.com/icons/PHSP/25.0.0/192x192.png"
            )
        ]
    ))
    .environmentObject(NetworkManager())
}
