import SwiftUI

@main
struct Adobe_DownloaderApp: App {
    @StateObject private var networkManager = NetworkManager()
    
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
