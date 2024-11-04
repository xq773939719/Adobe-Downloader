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
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage: Bool = true
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory: Bool = true
    @AppStorage("confirmRedownload") private var confirmRedownload: Bool = true
    @State private var showLanguagePicker = false
    
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
                        .buttonStyle(.borderless)
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
                        .buttonStyle(.borderless)
                    }
                    
                    Divider()
                    
                    HStack {
                        Toggle("重新下载时需要确认", isOn: $confirmRedownload)
                            .padding(.leading, 5)
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            useDefaultDirectory = true
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

            Link("Github: Adobe Downloader",
                 destination: URL(string: "https://github.com/X1a0He/Adobe-Downloader")!)
                .font(.caption)
                .foregroundColor(.blue)
            
            Link("Thanks Drovosek01: adobe-packager",
                 destination: URL(string: "https://github.com/Drovosek01/adobe-packager")!)
                .font(.caption)
                .foregroundColor(.blue)
            
            Text("Released under GPLv3.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AboutView()
} 
