import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showDownloadManager = false
    @State private var searchText = ""
    @AppStorage("useDefaultLanguage") private var useDefaultLanguage = true
    @AppStorage("useDefaultDirectory") private var useDefaultDirectory = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @State private var showLanguagePicker = false
    
    private var filteredProducts: [Sap] {
        let products = networkManager.saps.values
            .filter { !$0.hidden && !$0.versions.isEmpty }
            .sorted { $0.displayName < $1.displayName }
        
        if searchText.isEmpty {
            return Array(products)
        }
        
        return products.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.sapCode.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Adobe Downloader")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(width: 180)
                
                SettingsView(
                    useDefaultLanguage: $useDefaultLanguage,
                    useDefaultDirectory: $useDefaultDirectory,
                    onSelectLanguage: selectLanguage,
                    onSelectDirectory: selectDirectory
                )
                .frame(maxWidth: .infinity)
                
                HStack(spacing: 8) {
                    SearchField(text: $searchText)
                        .frame(width: 140)

                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .disabled(isRefreshing)
                    .buttonStyle(.borderless)
                    
                    Button(action: { showDownloadManager.toggle() }) {
                        Image(systemName: "arrow.down.circle")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .overlay(
                        Group {
                            if !networkManager.downloadTasks.isEmpty {
                                Text("\(networkManager.downloadTasks.count)")
                                    .font(.caption2)
                                    .padding(3)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .foregroundColor(.white)
                                    .offset(x: 8, y: -8)
                            }
                        }
                    )
                }
                .frame(width: 200)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()
                
                switch networkManager.loadingState {
                case .idle, .loading:
                    ProgressView("正在加载...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                case .failed(let error):
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        
                        Text("加载失败")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text(error.localizedDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                            .padding(.bottom, 10)
                        
                        Button(action: {
                            networkManager.retryFetchData()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("重试")
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                case .success:
                    if filteredProducts.isEmpty {
                        ContentUnavailableView(
                            "没有找到产品",
                            systemImage: "magnifyingglass",
                            description: Text("尝试使用不同的搜索关键词")
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 250))],
                                spacing: 20
                            ) {
                                ForEach(filteredProducts, id: \.sapCode) { sap in
                                    AppCardView(sap: sap)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView(languages: AppStatics.supportedLanguages) { language in
                defaultLanguage = language
                showLanguagePicker = false
            }
        }
        .sheet(isPresented: $showDownloadManager) {
            DownloadManagerView()
                .environmentObject(networkManager)
        }
        .onAppear {

            if networkManager.saps.isEmpty {
                refreshData()
            }
        }
    }
    
    private func refreshData() {
        isRefreshing = true
        errorMessage = nil
        
        Task {
            await networkManager.fetchProducts()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
    
    private func selectLanguage() {
        showLanguagePicker = true
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

struct SearchField: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索应用", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    let networkManager = NetworkManager()
    
    return ContentView()
        .environmentObject(networkManager)
        .frame(width: 850, height: 700)
}

