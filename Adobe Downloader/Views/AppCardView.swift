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
    let sap: Sap
    @EnvironmentObject private var networkManager: NetworkManager
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage: Bool = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showVersionPicker = false
    @State private var selectedVersion: String = ""
    @State private var iconImage: NSImage? = nil
    @State private var showLanguagePicker = false
    @State private var selectedLanguage = ""

    private var isDownloading: Bool {
        networkManager.downloadTasks.contains(where: isTaskDownloading)
    }

    private func isTaskDownloading(_ task: NewDownloadTask) -> Bool {
        guard task.sapCode == sap.sapCode else { return false }

        switch task.totalStatus {
        case .downloading, .preparing, .waiting, .retrying:
            return true
        default:
            return false
        }
    }

    private var dependenciesCount: Int {
        if let firstVersion = sap.versions.first?.value {
            return firstVersion.dependencies.count
        }
        return 0
    }

    var body: some View {
        VStack {
            IconView(iconImage: iconImage, loadIcon: loadIcon)
            
            ProductInfoView(sap: sap, dependenciesCount: dependenciesCount)

            Spacer()
            
            DownloadButton(
                isDownloading: isDownloading,
                showVersionPicker: $showVersionPicker
            )
        }
        .padding()
        .frame(width: 250, height: 200)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 2)
        )
        .sheet(isPresented: $showVersionPicker) {
            VersionPickerView(sap: sap) { version in
                if useDefaultLanguage {
                    startDownload(version)
                } else {
                    selectedVersion = version
                    showLanguagePicker = true
                }
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                selectedLanguage = language
                showLanguagePicker = false
                if !selectedVersion.isEmpty {
                    startDownloadWithLanguage(selectedVersion, language)
                }
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
        if let bestIcon = sap.getBestIcon(),
           let iconURL = URL(string: bestIcon.url) {
            
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
                    if let localImage = NSImage(named: sap.sapCode) {
                        await MainActor.run {
                            self.iconImage = localImage
                        }
                    }
                }
            }
        } else if let localImage = NSImage(named: sap.sapCode) {
            self.iconImage = localImage
        }
    }

    private func startDownload(_ version: String) {
        if useDefaultLanguage {
            startDownloadWithLanguage(version, defaultLanguage)
        } else {
            selectedVersion = version
            showLanguagePicker = true
        }
    }
    
    private func startDownloadWithLanguage(_ version: String, _ language: String) {
        Task {
            do {
                let destinationURL: URL
                if useDefaultDirectory && !defaultDirectory.isEmpty {
                    destinationURL = URL(fileURLWithPath: defaultDirectory)
                        .appendingPathComponent("Install \(sap.displayName)_\(version)-\(language).app")
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
                        .appendingPathComponent("Install \(sap.displayName)_\(version)-\(language).app")
                }
                try await networkManager.startDownload(
                    sap: sap,
                    selectedVersion: version,
                    language: language,
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

// 子视图
private struct IconView: View {
    let iconImage: NSImage?
    let loadIcon: () -> Void
    
    var body: some View {
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
        .onAppear(perform: loadIcon)
    }
}

private struct ProductInfoView: View {
    let sap: Sap
    let dependenciesCount: Int
    
    var body: some View {
        VStack {
            Text(sap.displayName)
                .font(.system(size: 16))
                .fontWeight(.bold)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("可用版本: \(sap.versions.count)")
                Text("|")
                Text("依赖包: \(dependenciesCount)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(height: 20)
        }
    }
}

private struct DownloadButton: View {
    let isDownloading: Bool
    @Binding var showVersionPicker: Bool
    
    var body: some View {
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
}

#Preview {
    AppCardView(sap: Sap(
        hidden: false,
        displayName: "Photoshop",
        sapCode: "PHSP",
        versions: [
            "25.0.0": Sap.Versions(
                sapCode: "PHSP",
                baseVersion: "25.0.0",
                productVersion: "25.0.0",
                apPlatform: "macuniversal",
                dependencies: [
                    Sap.Versions.Dependencies(sapCode: "ACR", version: "9.6"),
                    Sap.Versions.Dependencies(sapCode: "COCM", version: "1.0"),
                    Sap.Versions.Dependencies(sapCode: "COSY", version: "2.4.1")
                ],
                buildGuid: ""
            )
        ],
        icons: [
            Sap.ProductIcon(
                size: "192x192",
                url: "https://ffc-static-cdn.oobesaas.adobe.com/icons/PHSP/25.0.0/192x192.png"
            )
        ]
    ))
    .environmentObject(NetworkManager())
}
