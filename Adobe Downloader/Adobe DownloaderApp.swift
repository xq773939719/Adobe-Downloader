import SwiftUI

@main
struct Adobe_DownloaderApp: App {
    @StateObject private var networkManager = NetworkManager()
    @State private var showBackupAlert = false
    
    init() {
        if UserDefaults.standard.object(forKey: "useDefaultLanguage") == nil {
            UserDefaults.standard.set(true, forKey: "useDefaultLanguage")
        }
        if UserDefaults.standard.object(forKey: "useDefaultDirectory") == nil {
            UserDefaults.standard.set(true, forKey: "useDefaultDirectory")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(networkManager)
                .frame(width: 850, height: 800)
                .tint(.blue)
                .onAppear {
                    if ModifySetup.checkSetupBackup() {
                        showBackupAlert = true
                    }
                }
                .alert("Setup未备份提示", isPresented: $showBackupAlert) {
                    Button("OK") {
                        ModifySetup.backupSetupFile { success, message in
                            if !success {
                                print(message)
                            }
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("检测到Setup文件尚未备份，如果你需要安装程序，则Setup必须被处理，点击确定后你需要输入密码，Adobe Downloader将自动处理并备份为Setup.original")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            AboutView()
        }
    }
}
