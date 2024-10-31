import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var networkManager: NetworkManager
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showDownloadManager = false
    @State private var searchText = ""
    @State private var useDefaultLanguage = true
    @State private var useDefaultDirectory = true
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @AppStorage("defaultDirectory") private var defaultDirectory: String = ""
    @State private var showLanguagePicker = false
    
    private var filteredProducts: [Product] {
        let products = networkManager.products.values
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
            HStack(spacing: 20) {
                HStack {
                    Text("Adobe Downloader")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .frame(minWidth: 200)
                HStack {
                    SettingsView(
                        useDefaultLanguage: $useDefaultLanguage,
                        useDefaultDirectory: $useDefaultDirectory,
                        onSelectLanguage: selectLanguage,
                        onSelectDirectory: selectDirectory
                    )
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    SearchField(text: $searchText)
                        .frame(width: 160)

                    Button(action: refreshData) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.large)
                    }
                    .disabled(isRefreshing)
                    .buttonStyle(.borderless)
                    
                    Button(action: { showDownloadManager.toggle() }) {
                        Image(systemName: "arrow.down.circle")
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .overlay(
                        Group {
                            if !networkManager.downloadTasks.isEmpty {
                                Text("\(networkManager.downloadTasks.count)")
                                    .font(.caption2)
                                    .padding(4)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .foregroundColor(.white)
                                    .offset(x: 10, y: -10)
                            }
                        }
                    )
                }
                .frame(width: 220)
            }
            .padding(.horizontal)
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
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 250))],
                                spacing: 20
                            ) {
                                ForEach(filteredProducts) { product in
                                    AppCardView(product: product)
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
            if networkManager.products.isEmpty {
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

    let mockProducts: [String: Product] = [
        "PHSP": Product(
            id: "PHSP",
            hidden: false,
            displayName: "Photoshop",
            sapCode: "PHSP",
            versions: [
                "25.0.0": Product.ProductVersion(
                    sapCode: "PHSP",
                    baseVersion: "25.0.0",
                    productVersion: "25.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: ""
                )
            ],
            icons: [
                Product.ProductIcon(
                    size: "192x192",
                    url: "https://ffc-static-cdn.oobesaas.adobe.com/icons/PHSP/25.0.0/192x192.png"
                )
            ]
        ),
        "ILST": Product(
            id: "ILST",
            hidden: false,
            displayName: "Illustrator",
            sapCode: "ILST",
            versions: [
                "28.0.0": Product.ProductVersion(
                    sapCode: "ILST",
                    baseVersion: "28.0.0",
                    productVersion: "28.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: ""
                )
            ],
            icons: [
                Product.ProductIcon(
                    size: "192x192",
                    url: "https://ffc-static-cdn.oobesaas.adobe.com/icons/ILST/28.0.0/192x192.png"
                )
            ]
        ),
        "AEFT": Product(
            id: "AEFT",
            hidden: false,
            displayName: "After Effects",
            sapCode: "AEFT",
            versions: [
                "24.0.0": Product.ProductVersion(
                    sapCode: "AEFT",
                    baseVersion: "24.0.0",
                    productVersion: "24.0.0",
                    apPlatform: "macuniversal",
                    dependencies: [],
                    buildGuid: ""
                )
            ],
            icons: [
                Product.ProductIcon(
                    size: "192x192",
                    url: "https://ffc-static-cdn.oobesaas.adobe.com/icons/AEFT/24.0.0/192x192.png"
                )
            ]
        )
    ]
    
    Task { @MainActor in
        networkManager.products = mockProducts
        networkManager.loadingState = .success
    }
    
    return ContentView()
        .environmentObject(networkManager)
        .frame(width: 850, height: 700)
}

