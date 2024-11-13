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
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage: Bool = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "ALL"
    @AppStorage("downloadAppleSilicon") private var downloadAppleSilicon: Bool = true
    @AppStorage("confirmRedownload") private var confirmRedownload: Bool = true
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @State private var showBackupResultAlert = false
    @State private var backupResultMessage = ""
    @State private var backupSuccess = false
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        let isFirstRun = UserDefaults.standard.object(forKey: "downloadAppleSilicon") == nil ||
                        UserDefaults.standard.object(forKey: "useDefaultLanguage") == nil
        
        UserDefaults.standard.set(isFirstRun, forKey: "isFirstLaunch")

        if UserDefaults.standard.object(forKey: "downloadAppleSilicon") == nil {
            UserDefaults.standard.set(AppStatics.isAppleSilicon, forKey: "downloadAppleSilicon")
        }
        
        if UserDefaults.standard.object(forKey: "useDefaultLanguage") == nil {
            let systemLanguage = Locale.current.identifier
            let matchedLanguage = AppStatics.supportedLanguages.first { 
                systemLanguage.hasPrefix($0.code.prefix(2)) 
            }?.code ?? "ALL"

            UserDefaults.standard.set(true, forKey: "useDefaultLanguage")
            UserDefaults.standard.set(matchedLanguage, forKey: "defaultLanguage")
        }
        
        if UserDefaults.standard.object(forKey: "useDefaultDirectory") == nil {
            if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                print(downloadsURL.path)
                defaultDirectory = downloadsURL.path
                UserDefaults.standard.set(true, forKey: "useDefaultDirectory")
                UserDefaults.standard.set(downloadsURL.path, forKey: "defaultDirectory")
            }
        }
        PrivilegedHelperManager.shared.checkInstall()
        
        if UserDefaults.standard.string(forKey: "apiVersion") == nil {
            UserDefaults.standard.set("6", forKey: "apiVersion")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(networkManager)
                .frame(width: 850, height: 800)
                .tint(.blue)
                .task {
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
                        
                        if UserDefaults.standard.bool(forKey: "isFirstLaunch") {
                            showTipsSheet = true
                            UserDefaults.standard.removeObject(forKey: "isFirstLaunch")
                        }
                    }
                }
                .sheet(isPresented: $showCreativeCloudAlert) {
                    ShouldExistsSetUpView()
                        .environmentObject(networkManager)
                }
                .alert("Setup未备份提示", isPresented: $showBackupAlert) {
                    Button("确定") {
                        ModifySetup.backupSetupFile { success, message in
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
                                Toggle("使用默认语言", isOn: $useDefaultLanguage)
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
                                Toggle("使用默认目录", isOn: $useDefaultDirectory)
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
                                Toggle("重新下载时需要确认", isOn: $confirmRedownload)
                                    .padding(.leading, 5)
                                Spacer()
                            }
                            
                            Divider()

                            HStack {
                                Toggle("下载 Apple Silicon 架构", isOn: $downloadAppleSilicon)
                                    .padding(.leading, 5)
                                Spacer()
                                Text("当前架构: \(AppStatics.cpuArchitecture)")
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .onChange(of: downloadAppleSilicon) { newValue in
                                networkManager.updateAllowedPlatform(useAppleSilicon: newValue)
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
