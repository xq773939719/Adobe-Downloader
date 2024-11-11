//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//

import SwiftUI
import Sparkle

struct AboutView: View {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }
    
    var body: some View {
        TabView {
            GeneralSettingsView(updater: updater)
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            AboutAppView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(width: 600)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "ALL"
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage: Bool = true
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @AppStorage("confirmRedownload") private var confirmRedownload: Bool = true
    @AppStorage("downloadAppleSilicon") private var downloadAppleSilicon: Bool = true
    @State private var showLanguagePicker = false
    @EnvironmentObject private var networkManager: NetworkManager
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSuccess = false
    
    @State private var setupVersion: String = ""

    private let updater: SPUUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        _automaticallyChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        Form {
            GroupBox(label: Text("下载设置").padding(.bottom, 8)) {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(8)
            }
            GroupBox(label: Text("其他设置").padding(.bottom, 8)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Setup 备份状态: ")
                        if ModifySetup.isSetupBackup() {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("(将导致无法使用安装功能)")
                        }
                        Spacer()

                        Button(action: {
                            ModifySetup.backupSetupFile { success, message in
                                self.isSuccess = success
                                self.alertMessage = message
                                self.showAlert = true
                            }
                        }) {
                            Text("立即备份")
                        }
                        .disabled(ModifySetup.isSetupBackup())
                    }
                    Divider()
                    HStack {
                        Text("Setup 组件版本: \(setupVersion)")
                        Spacer()

                        Button(action: {}) {
                            Text("下载 Setup 组件")
                        }
                        .disabled(setupVersion != String(localized: "未知 Setup 组件版本号"))
                    }
                }.padding(8)
            }
            .padding(.vertical, 5)
            GroupBox(label: Text("更新设置").padding(.bottom, 8)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("自动检查更新版本", isOn: $automaticallyChecksForUpdates)
                            .onChange(of: automaticallyChecksForUpdates) { newValue in
                                updater.automaticallyChecksForUpdates = newValue
                            }
                        Spacer()
                        
                        CheckForUpdatesView(updater: updater)
                    }
                    Divider()
                    Toggle("自动下载最新版本", isOn: $automaticallyDownloadsUpdates)
                        .disabled(!automaticallyChecksForUpdates)
                        .onChange(of: automaticallyDownloadsUpdates) { newValue in
                            updater.automaticallyDownloadsUpdates = newValue
                        }
                }.padding(8)
            }
            .padding(.vertical, 5)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                defaultLanguage = language
                showLanguagePicker = false
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(isSuccess ? "操作成功" : "操作失败"),
                message: Text(alertMessage),
                dismissButton: .default(Text("确定"))
            )
        }
        .onAppear {
            setupVersion = ModifySetup.checkComponentVersion()
            networkManager.updateAllowedPlatform(useAppleSilicon: downloadAppleSilicon)
        }
    }
    
    private func getLanguageName(code: String) -> String {
        AppStatics.supportedLanguages.first { $0.code == code }?.name ?? code
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
            defaultDirectory = panel.url?.path ?? ""
            useDefaultDirectory = true
        }
    }
}

struct AboutAppView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        // let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        // return "Version \(version) (\(build))"
        return "\(version)"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            
            Text("Adobe Downloader \(appVersion)")
                .font(.title2)
                .bold()
            
            Text("By X1a0He. ❤️ Love from China. ❤️")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Link("联系 @X1a0He",
                 destination: URL(string: "https://t.me/X1a0He")!)
                .font(.caption)
                .foregroundColor(.blue)
            Link("Github: Adobe Downloader",
                 destination: URL(string: "https://github.com/X1a0He/Adobe-Downloader")!)
                .font(.caption)
                .foregroundColor(.blue)
            
            Link("感谢 Drovosek01: adobe-packager",
                 destination: URL(string: "https://github.com/Drovosek01/adobe-packager")!)
                .font(.caption)
                .foregroundColor(.blue)

            Link("感谢 QiuChenly: InjectLib",
                 destination: URL(string: "https://github.com/QiuChenly/InjectLib")!)
                .font(.caption)
                .foregroundColor(.blue)

            Text("GNU通用公共许可证GPL v3.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("About Tab") {
    AboutAppView()
}

#Preview("General Settings") {
    let networkManager = NetworkManager()
    VStack {
        GeneralSettingsView(updater: PreviewUpdater())
            .environmentObject(networkManager)
    }
}

private class PreviewUpdater: SPUUpdater {
    init() {
        let hostBundle = Bundle.main
        let applicationBundle = Bundle.main
        let userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        
        super.init(
            hostBundle: hostBundle,
            applicationBundle: applicationBundle,
            userDriver: userDriver,
            delegate: nil
        )
    }
    
    override var automaticallyChecksForUpdates: Bool {
        get { true }
        set { }
    }
    
    override var automaticallyDownloadsUpdates: Bool {
        get { true }
        set { }
    }
} 
