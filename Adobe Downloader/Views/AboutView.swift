//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AboutAppView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 375, height: 150)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage: Bool = true
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    
    var body: some View {
        Form {
            GroupBox(label: Text("下载设置")) {
                VStack(alignment: .leading) {
                    Toggle("使用默认语言", isOn: $useDefaultLanguage)
                    if useDefaultLanguage {
                        Text("当前语言：\(getLanguageName(code: defaultLanguage))")
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    Toggle("使用默认目录", isOn: $useDefaultDirectory)
                    if useDefaultDirectory && !defaultDirectory.isEmpty {
                        Text("当前目录：\(defaultDirectory)")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
    
    private func getLanguageName(code: String) -> String {
        AppStatics.supportedLanguages.first { $0.code == code }?.name ?? code
    }
}

struct AboutAppView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            
            Text("Welcome to Adobe Downloader")
                .font(.title2)
                .bold()
            
            Text("By X1a0He. ❤️ Love from China. ❤️")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Released under GPLv3.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    AboutView()
} 
