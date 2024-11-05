//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//

import SwiftUI

class IconCache {
    static let shared = IconCache()
    private var cache = NSCache<NSString, NSImage>()
    
    func getIcon(for url: String) -> NSImage? {
        cache.object(forKey: url as NSString)
    }
    
    func setIcon(_ image: NSImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }
}

class AppCardViewModel: ObservableObject {
    @Published var iconImage: NSImage?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showVersionPicker = false
    @Published var selectedVersion = ""
    @Published var showLanguagePicker = false
    @Published var selectedLanguage = ""
    @Published var showExistingFileAlert = false
    @Published var existingFilePath: URL?
    @Published var pendingVersion = ""
    @Published var pendingLanguage = ""
    @Published var showRedownloadConfirm = false
    
    let sap: Sap
    weak var networkManager: NetworkManager?
    
    @Published var isDownloading = false
    private let userDefaults = UserDefaults.standard
    
    var useDefaultDirectory: Bool {
        get { userDefaults.bool(forKey: "useDefaultDirectory") }
    }
    
    var defaultDirectory: String {
        get { userDefaults.string(forKey: "defaultDirectory") ?? "" }
    }
    
    init(sap: Sap, networkManager: NetworkManager?) {
        self.sap = sap
        self.networkManager = networkManager
        loadIcon()
    }
    
    func updateDownloadingStatus() {
        Task { @MainActor in
            isDownloading = networkManager?.downloadTasks.contains(where: isTaskDownloading) ?? false
        }
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

    func getDestinationURL(version: String, language: String, useDefaultDirectory: Bool, defaultDirectory: String) async throws -> URL {
        let platform = sap.versions[version]?.apPlatform ?? "unknown"
        let installerName = sap.sapCode == "APRO" 
            ? "Install \(sap.sapCode)_\(version)_\(platform).dmg"
            : "Install \(sap.sapCode)_\(version)-\(language)-\(platform).app"
        
        if useDefaultDirectory && !defaultDirectory.isEmpty {
            return URL(fileURLWithPath: defaultDirectory)
                .appendingPathComponent(installerName)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.title = "选择保存位置"
                panel.canCreateDirectories = true
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                
                if panel.runModal() == .OK, let selectedURL = panel.url {
                    continuation.resume(returning: selectedURL.appendingPathComponent(installerName))
                } else {
                    continuation.resume(throwing: NetworkError.cancelled)
                }
            }
        }
    }

    func handleError(_ error: Error) {
        Task { @MainActor in
            if case NetworkError.cancelled = error { return }
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func loadIcon() {
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

    func handleDownloadRequest(_ version: String, useDefaultLanguage: Bool, defaultLanguage: String) async {
        await MainActor.run {
            if useDefaultLanguage {
                Task {
                    await checkAndStartDownload(version: version, language: defaultLanguage)
                }
            } else {
                selectedVersion = version
                showLanguagePicker = true
            }
        }
    }
    
    func checkAndStartDownload(version: String, language: String) async {
        if let networkManager = networkManager {
            if let existingPath = await networkManager.isVersionDownloaded(sap: sap, version: version, language: language) {
                await MainActor.run {
                    existingFilePath = existingPath
                    pendingVersion = version
                    pendingLanguage = language
                    showExistingFileAlert = true
                }
            } else {
                startDownload(version, language)
            }
        }
    }
    
    func startDownload(_ version: String, _ language: String) {
        Task {
            do {
                let destinationURL = try await getDestinationURL(
                    version: version,
                    language: language,
                    useDefaultDirectory: useDefaultDirectory,
                    defaultDirectory: defaultDirectory
                )

                try await networkManager?.startDownload(
                    sap: sap,
                    selectedVersion: version,
                    language: language,
                    destinationURL: destinationURL
                )
            } catch {
                handleError(error)
            }
        }
    }

    func createCompletedTask(_ path: URL) async {
        guard let networkManager = networkManager,
              let productInfo = sap.versions[pendingVersion] else { return }

        var productsToDownload: [ProductsToDownload] = []
        let mainProduct = ProductsToDownload(
            sapCode: sap.sapCode,
            version: pendingVersion,
            buildGuid: productInfo.buildGuid
        )
        productsToDownload.append(mainProduct)

        for dependency in productInfo.dependencies {
            if let dependencyVersions = await networkManager.saps[dependency.sapCode]?.versions {
                let sortedVersions = dependencyVersions.sorted { first, second in
                    first.value.productVersion.compare(second.value.productVersion, options: .numeric) == .orderedDescending
                }
                
                var buildGuid = ""
                for (_, versionInfo) in sortedVersions where versionInfo.baseVersion == dependency.version {
                    if await networkManager.allowedPlatform.contains(versionInfo.apPlatform) {
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

        await MainActor.run {
            networkManager.downloadTasks.append(completedTask)
            networkManager.objectWillChange.send()
        }
    }
    
    var dependenciesCount: Int {
        if let firstVersion = sap.versions.first?.value {
            return firstVersion.dependencies.count
        }
        return 0
    }
}

struct AppCardView: View {
    @StateObject private var viewModel: AppCardViewModel
    @EnvironmentObject private var networkManager: NetworkManager
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    
    init(sap: Sap) {
        _viewModel = StateObject(wrappedValue: AppCardViewModel(sap: sap, networkManager: nil))
    }
    
    var body: some View {
        CardContent(
            sap: viewModel.sap,
            iconImage: viewModel.iconImage,
            loadIcon: viewModel.loadIcon,
            dependenciesCount: viewModel.dependenciesCount,
            isDownloading: viewModel.isDownloading,
            showVersionPicker: $viewModel.showVersionPicker
        )
        .padding()
        .frame(width: 250, height: 200)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.1), lineWidth: 2)
        )
        .modifier(AlertModifier(viewModel: viewModel, confirmRedownload: true))
        .sheet(isPresented: $viewModel.showVersionPicker) {
            VersionPickerView(sap: viewModel.sap) { version in
                Task {
                    await viewModel.handleDownloadRequest(version, useDefaultLanguage: useDefaultLanguage, defaultLanguage: defaultLanguage)
                }
            }
            .environmentObject(networkManager)
        }
        .sheet(isPresented: $viewModel.showLanguagePicker) {
            LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                Task {
                    await viewModel.checkAndStartDownload(version: viewModel.selectedVersion, language: language)
                }
            }
        }
        .onAppear {
            viewModel.networkManager = networkManager
            viewModel.updateDownloadingStatus()
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
    func applyModifiers(viewModel: AppCardViewModel) -> some View {
        self.modifier(AlertModifier(viewModel: viewModel, confirmRedownload: true))
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
    let networkManager = NetworkManager()
    let sap = Sap(
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
    )
    
    return AppCardView(sap: sap)
        .environmentObject(networkManager)
}

struct AlertModifier: ViewModifier {
    @ObservedObject var viewModel: AppCardViewModel
    let confirmRedownload: Bool
    
    func body(content: Content) -> some View {
        content
            .alert("安装程序已存在", isPresented: $viewModel.showExistingFileAlert) {
                Button("使用现有程序") {
                    if let path = viewModel.existingFilePath,
                       !viewModel.pendingVersion.isEmpty && !viewModel.pendingLanguage.isEmpty {
                        Task {
                            await viewModel.createCompletedTask(path)
                        }
                    }
                }
                Button("重新下载") {
                    if !viewModel.pendingVersion.isEmpty && !viewModel.pendingLanguage.isEmpty {
                        if confirmRedownload {
                            viewModel.showRedownloadConfirm = true
                        } else {
                            viewModel.startDownload(viewModel.pendingVersion, viewModel.pendingLanguage)
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                VStack(alignment: .leading) {
                    Text("在以下位置找到现有的安装程序：")
                    if let path = viewModel.existingFilePath {
                        Text(path.path)
                            .foregroundColor(.blue)
                            .onTapGesture {
                                NSWorkspace.shared.selectFile(path.path, inFileViewerRootedAtPath: path.deletingLastPathComponent().path)
                            }
                    }
                }
            }
            .alert("确认重新下载", isPresented: $viewModel.showRedownloadConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认") {
                    if !viewModel.pendingVersion.isEmpty && !viewModel.pendingLanguage.isEmpty {
                        viewModel.startDownload(viewModel.pendingVersion, viewModel.pendingLanguage)
                    }
                }
            } message: {
                Text("是否确认重新下载？这将覆盖现有的安装程序。")
            }
            .alert("下载错误", isPresented: $viewModel.showError) {
                Button("确定", role: .cancel) { }
                Button("重试") {
                    if !viewModel.selectedVersion.isEmpty {
                        viewModel.startDownload(viewModel.selectedVersion, viewModel.selectedLanguage)
                    }
                }
            } message: {
                Text(viewModel.errorMessage)
            }
    }
}
