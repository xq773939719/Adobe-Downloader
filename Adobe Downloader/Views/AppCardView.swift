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
    @AppStorage("confirmRedownload") private var confirmRedownload: Bool = true
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showVersionPicker = false
    @State private var selectedVersion: String = ""
    @State private var iconImage: NSImage? = nil
    @State private var showLanguagePicker = false
    @State private var selectedLanguage = ""
    @State private var showExistingFileAlert = false
    @State private var existingFilePath: URL? = nil
    @State private var pendingVersion: String = ""
    @State private var pendingLanguage: String = ""
    @State private var showRedownloadConfirm = false

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
        CardContent(
            sap: sap,
            iconImage: iconImage,
            loadIcon: loadIcon,
            dependenciesCount: dependenciesCount,
            isDownloading: isDownloading,
            showVersionPicker: $showVersionPicker
        )
        .padding()
        .frame(width: 250, height: 200)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 2)
        )
        .applyModifiers(
            showVersionPicker: $showVersionPicker,
            showLanguagePicker: $showLanguagePicker,
            showExistingFileAlert: $showExistingFileAlert,
            showError: $showError,
            sap: sap,
            existingFilePath: existingFilePath,
            pendingVersion: pendingVersion,
            pendingLanguage: pendingLanguage,
            errorMessage: errorMessage,
            selectedVersion: selectedVersion,
            selectedLanguage: $selectedLanguage,
            handleDownloadRequest: handleDownloadRequest,
            checkAndStartDownload: checkAndStartDownload,
            startDownload: startDownload,
            createCompletedTask: createCompletedTask,
            confirmRedownload: confirmRedownload,
            showRedownloadConfirm: $showRedownloadConfirm
        )
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

    private func handleDownloadRequest(_ version: String) {
        if useDefaultLanguage {
            checkAndStartDownload(version: version, language: defaultLanguage)
        } else {
            selectedVersion = version
            showLanguagePicker = true
        }
    }
    
    private func checkAndStartDownload(version: String, language: String) {
        if let existingPath = networkManager.isVersionDownloaded(sap: sap, version: version, language: language) {
            existingFilePath = existingPath
            pendingVersion = version
            pendingLanguage = language
            showExistingFileAlert = true
        } else {
            startDownload(version, language)
        }
    }
    
    private func startDownload(_ version: String, _ language: String) {
        Task {
            do {
                let destinationURL: URL
                let platform = sap.versions[version]?.apPlatform ?? "unknown"
                
                if useDefaultDirectory && !defaultDirectory.isEmpty {
                    destinationURL = URL(fileURLWithPath: defaultDirectory)
                        .appendingPathComponent("Install \(sap.sapCode)_\(version)-\(language)-\(platform).app")
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
                        .appendingPathComponent("Install \(sap.sapCode)_\(version)-\(language)-\(platform).app")
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

    private func createCompletedTask(_ path: URL) {
        guard let productInfo = sap.versions[pendingVersion] else { return }

        var productsToDownload: [ProductsToDownload] = []

        let mainProduct = ProductsToDownload(
            sapCode: sap.sapCode,
            version: pendingVersion,
            buildGuid: productInfo.buildGuid
        )
        productsToDownload.append(mainProduct)

        for dependency in productInfo.dependencies {
            if let dependencyVersions = networkManager.saps[dependency.sapCode]?.versions {
                let sortedVersions = dependencyVersions.sorted { first, second in
                    first.value.productVersion.compare(second.value.productVersion, options: .numeric) == .orderedDescending
                }
                
                var buildGuid = ""
                for (_, versionInfo) in sortedVersions where versionInfo.baseVersion == dependency.version {
                    if networkManager.allowedPlatform.contains(versionInfo.apPlatform) {
                        buildGuid = versionInfo.buildGuid
                        break
                    }
                }
                
                if !buildGuid.isEmpty {
                    let dependencyProduct = ProductsToDownload(
                        sapCode: dependency.sapCode,
                        version: dependency.version,
                        buildGuid: buildGuid
                    )
                    productsToDownload.append(dependencyProduct)
                }
            }
        }

        let completedTask = NewDownloadTask(
            sapCode: sap.sapCode,
            version: pendingVersion,
            language: pendingLanguage,
            displayName: sap.displayName,
            directory: path,
            productsToDownload: productsToDownload,
            retryCount: 0,
            createAt: Date(),
            totalStatus: .completed(DownloadStatus.CompletionInfo(
                timestamp: Date(),
                totalTime: 0,
                totalSize: 0
            )),
            totalProgress: 1.0,
            totalDownloadedSize: 0,
            totalSize: 0,
            totalSpeed: 0
        )

        Task { @MainActor in
            networkManager.downloadTasks.append(completedTask)
            networkManager.objectWillChange.send()
        }
    }
}

private struct CardContent: View {
    let sap: Sap
    let iconImage: NSImage?
    let loadIcon: () -> Void
    let dependenciesCount: Int
    let isDownloading: Bool
    @Binding var showVersionPicker: Bool
    
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
    }
}

private extension View {
    func applyModifiers(
        showVersionPicker: Binding<Bool>,
        showLanguagePicker: Binding<Bool>,
        showExistingFileAlert: Binding<Bool>,
        showError: Binding<Bool>,
        sap: Sap,
        existingFilePath: URL?,
        pendingVersion: String,
        pendingLanguage: String,
        errorMessage: String,
        selectedVersion: String,
        selectedLanguage: Binding<String>,
        handleDownloadRequest: @escaping (String) -> Void,
        checkAndStartDownload: @escaping (String, String) -> Void,
        startDownload: @escaping (String, String) -> Void,
        createCompletedTask: @escaping (URL) -> Void,
        confirmRedownload: Bool,
        showRedownloadConfirm: Binding<Bool>
    ) -> some View {
        self
            .sheet(isPresented: showVersionPicker) {
                VersionPickerView(sap: sap, onSelect: handleDownloadRequest)
            }
            .sheet(isPresented: showLanguagePicker) {
                LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                    selectedLanguage.wrappedValue = language
                    showLanguagePicker.wrappedValue = false
                    if !selectedVersion.isEmpty {
                        checkAndStartDownload(selectedVersion, language)
                    }
                }
            }
            .alert("安装程序已存在", isPresented: showExistingFileAlert) {
                Button("使用现有程序") {
                    if let path = existingFilePath,
                       !pendingVersion.isEmpty && !pendingLanguage.isEmpty {
                        createCompletedTask(path)
                    }
                }
                Button("重新下载") {
                    if !pendingVersion.isEmpty && !pendingLanguage.isEmpty {
                        if confirmRedownload {
                            showRedownloadConfirm.wrappedValue = true
                        } else {
                            startDownload(pendingVersion, pendingLanguage)
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                VStack(alignment: .leading) {
                    Text("在以下位置找到现有的安装程序：")
                    if let path = existingFilePath {
                        Text(path.path)
                            .foregroundColor(.blue)
                            .onTapGesture {
                                NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: path.deletingLastPathComponent().path)
                            }
                    }
                }
            }
            .alert("确认重新下载", isPresented: showRedownloadConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认") {
                    if !pendingVersion.isEmpty && !pendingLanguage.isEmpty {
                        startDownload(pendingVersion, pendingLanguage)
                    }
                }
            } message: {
                Text("是否确认重新下载？这将覆盖现有的安装程序。")
            }
            .alert("下载错误", isPresented: showError) {
                Button("确定", role: .cancel) { }
                Button("重试") {
                    if !selectedVersion.isEmpty {
                        startDownload(selectedVersion, selectedLanguage.wrappedValue)
                    }
                }
            } message: {
                Text(errorMessage)
            }
    }
}

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
