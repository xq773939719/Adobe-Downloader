import SwiftUI

@main
struct Adobe_DownloaderApp: App {
    @StateObject private var networkManager = NetworkManager()
    
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
                .frame(width: 850, height: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            AboutView()
        }
    }
}
