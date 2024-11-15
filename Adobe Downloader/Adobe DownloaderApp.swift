import SwiftUI
import Sparkle

@main
struct Adobe_DownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var networkManager = NetworkManager()
    @State private var showBackupAlert = false
    @State private var showTipsSheet = false
    @State private var showLanguagePicker = false
    @State private var showCreativeCloudAlert = false
    @StorageValue(\.useDefaultLanguage) private var useDefaultLanguage
    @StorageValue(\.defaultLanguage) private var defaultLanguage
    @StorageValue(\.downloadAppleSilicon) private var downloadAppleSilicon
    @StorageValue(\.confirmRedownload) private var confirmRedownload
    @StorageValue(\.useDefaultDirectory) private var useDefaultDirectory
    @StorageValue(\.defaultDirectory) private var defaultDirectory
    @State private var showBackupResultAlert = false
    @State private var backupResultMessage = ""
    @State private var backupSuccess = false
    private let updaterController: SPUStandardUpdaterController

    init() {
        if StorageData.shared.installedHelperBuild == "0" {
            StorageData.shared.installedHelperBuild = "0"
        }

        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        if StorageData.shared.isFirstLaunch {
            let shouldDownloadAppleSilicon = AppStatics.isAppleSilicon
            StorageData.shared.downloadAppleSilicon = shouldDownloadAppleSilicon
            _downloadAppleSilicon.wrappedValue = shouldDownloadAppleSilicon

            StorageData.shared.confirmRedownload = true
            _confirmRedownload.wrappedValue = true

            let systemLanguage = Locale.current.identifier
            let matchedLanguage = AppStatics.supportedLanguages.first {
                systemLanguage.hasPrefix($0.code.prefix(2))
            }?.code ?? "ALL"
            StorageData.shared.defaultLanguage = matchedLanguage
            StorageData.shared.useDefaultLanguage = true

            if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                StorageData.shared.defaultDirectory = downloadsURL.path
                StorageData.shared.useDefaultDirectory = true
            }
        }

        if StorageData.shared.apiVersion == "6" {
            StorageData.shared.apiVersion = "6"
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(networkManager)
                .frame(width: 850, height: 800)
                .tint(.blue)
                .task {
                    PrivilegedHelperManager.shared.checkInstall()
                    
                    await MainActor.run {
                        appDelegate.networkManager = networkManager
                        networkManager.loadSavedTasks()
                    }

                    let needsBackup = !ModifySetup.isSetupBackup()
                    let needsSetup = !ModifySetup.isSetupExists()

                    await MainActor.run {
                        if needsSetup {
                            showCreativeCloudAlert = true
                        } else if needsBackup {
                            showBackupAlert = true
                        }

                        if StorageData.shared.isFirstLaunch {
                            showTipsSheet = true
                            StorageData.shared.isFirstLaunch = false
                        }
                    }
                }
                .sheet(isPresented: $showCreativeCloudAlert) {
                    ShouldExistsSetUpView()
                        .environmentObject(networkManager)
                }
                .alert("Setup未备份提示", isPresented: $showBackupAlert) {
                    Button("确定") {
                        ModifySetup.backupAndModifySetupFile { success, message in
                            backupSuccess = success
                            backupResultMessage = message
                            showBackupResultAlert = true
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("检测到Setup文件尚未备份，如果你需要安装程序，则Setup必须被处理，点击确定后你需要输入密码，Adobe Downloader将自动处理并备份为Setup.original")
                }
                .alert(backupSuccess ? "备份成功" : "备份失败", isPresented: $showBackupResultAlert) {
                    Button("确定") { }
                } message: {
                    Text(backupResultMessage)
                }
                .sheet(isPresented: $showTipsSheet) {
                    VStack(spacing: 20) {
                        Text("Adobe Downloader 已为你默认设定如下值")
                            .font(.headline)

                        VStack(spacing: 12) {
                            HStack {
                                Toggle("使用默认语言", isOn: Binding(
                                    get: { useDefaultLanguage },
                                    set: { 
                                        useDefaultLanguage = $0
                                        StorageData.shared.useDefaultLanguage = $0
                                    }
                                ))
                                .padding(.leading, 5)
                                Spacer()
                                Text(getLanguageName(code: defaultLanguage))
                                    .foregroundColor(.secondary)
                                Button("选择") {
                                    showLanguagePicker = true
                                }
                                .padding(.trailing, 5)
                            }

                            Divider()

                            HStack {
                                Toggle("使用默认目录", isOn: Binding(
                                    get: { useDefaultDirectory },
                                    set: { 
                                        useDefaultDirectory = $0
                                        StorageData.shared.useDefaultDirectory = $0
                                    }
                                ))
                                .padding(.leading, 5)
                                Spacer()
                                Text(formatPath(defaultDirectory))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("选择") {
                                    selectDirectory()
                                }
                                .padding(.trailing, 5)
                            }

                            Divider()

                            HStack {
                                Toggle("重新下载时需要确认", isOn: Binding(
                                    get: { confirmRedownload },
                                    set: { 
                                        confirmRedownload = $0
                                        StorageData.shared.confirmRedownload = $0
                                        NotificationCenter.default.post(name: .storageDidChange, object: nil)
                                    }
                                ))
                                .padding(.leading, 5)
                                Spacer()
                            }

                            Divider()

                            HStack {
                                Toggle("下载 Apple Silicon 架构", isOn: Binding(
                                    get: { downloadAppleSilicon },
                                    set: { 
                                        downloadAppleSilicon = $0
                                        StorageData.shared.downloadAppleSilicon = $0
                                        networkManager.updateAllowedPlatform(useAppleSilicon: $0)
                                    }
                                ))
                                .padding(.leading, 5)
                                Spacer()
                                Text("当前架构: \(AppStatics.cpuArchitecture)")
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        Text("你可以在设置中随时更改以上选项")
                            .font(.headline)

                        Button("确定") {
                            showTipsSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(width: 500)
                    .sheet(isPresented: $showLanguagePicker) {
                        LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                            defaultLanguage = language
                            StorageData.shared.defaultLanguage = language
                            showLanguagePicker = false
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizabilityContentSize()
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            AboutView(updater: updaterController.updater)
                .environmentObject(networkManager)
        }
    }

    private func formatPath(_ path: String) -> String {
        if path.isEmpty { return String(localized: "未设置") }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择默认下载目录"
        panel.canCreateDirectories = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            defaultDirectory = panel.url?.path ?? "Downloads"
            useDefaultDirectory = true
        }
    }

    private func checkCreativeCloudSetup() {
        let setupPath = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup"
        if !FileManager.default.fileExists(atPath: setupPath) {
            showCreativeCloudAlert = true
        }
    }

    private func getLanguageName(code: String) -> String {
        AppStatics.supportedLanguages.first { $0.code == code }?.name ?? code
    }
}

extension Scene {
    func windowResizabilityContentSize() -> some Scene {
        if #available(macOS 13.0, *) {
            return windowResizability(.contentSize)
        } else {
            return self
        }
    }
}
