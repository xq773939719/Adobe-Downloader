//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

class Package: Identifiable, ObservableObject {
    let id = UUID()
    var type: String
    var fullPackageName: String
    var downloadSize: Int64
    var downloadURL: String
    
    @Published var downloadedSize: Int64 = 0 {
        didSet {
            if downloadSize > 0 {
                progress = Double(downloadedSize) / Double(downloadSize)
            }
        }
    }
    @Published var progress: Double = 0
    @Published var speed: Double = 0
    @Published var status: PackageStatus = .waiting
    @Published var downloaded: Bool = false
    
    var lastUpdated: Date = Date()
    var lastRecordedSize: Int64 = 0
    var retryCount: Int = 0
    var lastError: Error?
    
    var canRetry: Bool {
        if case .failed = status {
            return retryCount < 3
        }
        return false
    }
    
    func markAsFailed(_ error: Error) {
        Task { @MainActor in
            self.lastError = error
            self.status = .failed(error.localizedDescription)
            objectWillChange.send()
        }
    }
    
    func prepareForRetry() {
        Task { @MainActor in
            self.retryCount += 1
            self.status = .waiting
            self.progress = 0
            self.speed = 0
            self.downloadedSize = 0
            objectWillChange.send()
        }
    }

    init(type: String, fullPackageName: String, downloadSize: Int64, downloadURL: String) {
        self.type = type
        self.fullPackageName = fullPackageName
        self.downloadSize = downloadSize
        self.downloadURL = downloadURL
    }

    func updateProgress(downloadedSize: Int64, speed: Double) {
        Task { @MainActor in
            self.downloadedSize = downloadedSize
            self.speed = speed
            self.status = .downloading
            objectWillChange.send()
        }
    }

    func markAsCompleted() {
        Task { @MainActor in
            self.downloaded = true
            self.progress = 1.0
            self.speed = 0
            self.status = .completed
            self.downloadedSize = downloadSize
            objectWillChange.send()
        }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
    }

    var formattedDownloadedSize: String {
        ByteCountFormatter.string(fromByteCount: downloadedSize, countStyle: .file)
    }

    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }

    var hasValidSize: Bool {
        downloadSize > 0
    }

    func updateStatus(_ status: PackageStatus) {
        Task { @MainActor in
            self.status = status
            objectWillChange.send()
        }
    }
}
class ProductsToDownload: ObservableObject {
    var sapCode: String
    var version: String
    var buildGuid: String
    var applicationJson: String?
    @Published var packages: [Package] = []
    @Published var completedPackages: Int = 0
    
    var totalPackages: Int {
        packages.count
    }

    init(sapCode: String, version: String, buildGuid: String, applicationJson: String = "") {
        self.sapCode = sapCode
        self.version = version
        self.buildGuid = buildGuid
        self.applicationJson = applicationJson
    }
    
    func updateCompletedPackages() {
        Task { @MainActor in
            completedPackages = packages.filter { $0.downloaded }.count
            objectWillChange.send()
        }
    }
}

struct SapCodes: Identifiable {
    var id: String { sapCode }
    var sapCode: String
    var displayName: String
}

struct Sap: Identifiable {
    var id: String { sapCode }
    var hidden: Bool
    var displayName: String
    var sapCode: String
    var versions: [String: Versions]
    var icons: [ProductIcon]
    var productsToDownload: [ProductsToDownload]? = nil


    struct Versions {
        var sapCode: String
        var baseVersion: String
        var productVersion: String
        var apPlatform: String
        var dependencies: [Dependencies]
        var buildGuid: String
        
        struct Dependencies {
            var sapCode: String
            var version: String
        }
    }
    
    struct ProductIcon {
        let size: String
        let url: String
        
        var dimension: Int {
            let components = size.split(separator: "x")
            if components.count == 2,
               let dimension = Int(components[0]) {
                return dimension
            }
            return 0
        }
    }
    
    var isValid: Bool { !hidden }
    
    func getBestIcon() -> ProductIcon? {
        if let icon = icons.first(where: { $0.size == "192x192" }) {
            return icon
        }
        return icons.max(by: { $0.dimension < $1.dimension })
    }
}

struct NetworkConstants {
    static let downloadTimeout: TimeInterval = 300
    static let maxRetryAttempts = 3
    static let retryDelay: UInt64 = 3_000_000_000
    static let bufferSize = 1024 * 1024
    static let maxConcurrentDownloads = 3
    static let progressUpdateInterval: TimeInterval = 1

    static var productsXmlURL: String {
        "https://prod-rel-ffc-ccm.oobesaas.adobe.com/adobe-ffc-external/core/v\(UserDefaults.standard.string(forKey: "apiVersion") ?? "6")/products/all"
    }

    static let applicationJsonURL = "https://cdn-ffc.oobesaas.adobe.com/core/v3/applications"

    static let adobeRequestHeaders = [
        "X-Adobe-App-Id": "accc-apps-panel-desktop",
        "User-Agent": "Adobe Application Manager 2.0",
        "X-Api-Key": "CC_HD_ESD_1_0",
        "Cookie": "fg=QZ6PFIT595NDL6186O9FNYYQOQ======"
    ]
    
    static let downloadHeaders = [
        "User-Agent": "Creative Cloud"
    ]
}
