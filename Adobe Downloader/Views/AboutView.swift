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
    @State private var showLanguagePicker = false
    
    var body: some View {
        Form {
            GroupBox(label: Text("下载设置")) {
                VStack(alignment: .leading, spacing: 12) {
                    // 语言设置
                    HStack {
                        Toggle("使用默认语言", isOn: $useDefaultLanguage)
                        Spacer()
                        Text(getLanguageName(code: defaultLanguage))
                            .foregroundColor(.secondary)
                        Button("选择") {
                            showLanguagePicker = true
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    Divider()
                    
                    // 目录设置
                    HStack {
                        Toggle("使用默认目录", isOn: $useDefaultDirectory)
                        Spacer()
                        Text(formatPath(defaultDirectory))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("选择") {
                            selectDirectory()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                defaultLanguage = language
                showLanguagePicker = false
            }
        }
    }
    
    private func getLanguageName(code: String) -> String {
        AppStatics.supportedLanguages.first { $0.code == code }?.name ?? code
    }
    
    private func formatPath(_ path: String) -> String {
        if path.isEmpty { return "未设置" }
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
            useDefaultDirectory = false
        }
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
