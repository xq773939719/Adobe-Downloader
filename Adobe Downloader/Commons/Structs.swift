//
//  Adobe-Downloader
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
}
class ProductsToDownload {
    var sapCode: String
    var version: String
    var buildGuid: String
    var applicationJson: String?
    var packages: [Package] = []

    init(sapCode: String, version: String, buildGuid: String, applicationJson: String = "") {
        self.sapCode = sapCode
        self.version = version
        self.buildGuid = buildGuid
        self.applicationJson = applicationJson
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

    static let applicationJsonURL = "https://cdn-ffc.oobesaas.adobe.com/core/v3/applications"
    static let productsXmlURL = "https://prod-rel-ffc-ccm.oobesaas.adobe.com/adobe-ffc-external/core/v6/products/all"

    static let adobeRequestHeaders = [
        "X-Adobe-App-Id": "accc-apps-panel-desktop",
        "User-Agent": "Adobe Application Manager 2.0",
        "X-Api-Key": "CC_HD_ESD_1_0",
        "Cookie": "fg=QZ6PFIT595NDL6186O9FNYYQOQ======"
    ]
    
    static let downloadHeaders = [
        "User-Agent": "Creative Cloud"
    ]

    static let ADOBE_CC_MAC_ICON_PATH = "/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Install.app/Contents/Resources/CreativeCloudInstaller.icns"
    static let MAC_VOLUME_ICON_PATH = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/CDAudioVolumeIcon.icns"

    static let INSTALL_APP_APPLE_SCRIPT = """
        const app = Application.currentApplication()
        app.includeStandardAdditions = true

        ObjC.import('Cocoa')
        ObjC.import('stdio')
        ObjC.import('stdlib')

        ObjC.registerSubclass({
        name: 'HandleDataAction',
        methods: {
            'outData:': {
                types: ['void', ['id']],
                implementation: function(sender) {
                    const data = sender.object.availableData
                    if (data.length !== 0) {
                        const output = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js
                        const res = parseOutput(output)
                        if (res) {
                            switch (res.type) {
                                case 'progress':
                                    Progress.additionalDescription = `Progress: ${res.data}%`
                                    Progress.completedUnitCount = res.data
                                    break
                                case 'exit':
                                    if (res.data === 0) {
                                        $.puts(JSON.stringify({ title: 'Installation succeeded' }))
                                    } else {
                                        $.puts(JSON.stringify({ title: `Failed with error code ${res.data}` }))
                                    }
                                    $.exit(0)
                                    break
                            }
                        }
                        sender.object.waitForDataInBackgroundAndNotify
                    } else {
                        $.NSNotificationCenter.defaultCenter.removeObserver(this)
                    }
                }
            }
        }
        })

        function parseOutput(output) {
        let matches

        matches = output.match(/Progress: ([0-9]{1,3})%/)
        if (matches) {
            return {
                type: 'progress',
                data: parseInt(matches[1], 10)
            }
        }

        matches = output.match(/Exit Code: ([0-9]{1,3})/)
        if (matches) {
            return {
                type: 'exit',
                data: parseInt(matches[1], 10)
            }
        }

        return false
        }

        function shellescape(a) {
        var ret = []

        a.forEach(function(s) {
            if (/[^A-Za-z0-9_\\/:=-]/.test(s)) {
                s = "'"+s.replace(/'/g,"'\\''")+"'"
                s = s.replace(/^(?:'')+/g, '') // unduplicate single-quote at the beginning
                    .replace(/\\'''/g, "\\'") // remove non-escaped single-quote if there are enclosed between 2 escaped
            }
            ret.push(s)
        })

        return ret.join(' ')
        }

        function run() {
            const appPath = app.pathTo(this).toString()
            const driverPath = appPath + '/Contents/Resources/products/driver.xml'
            const hyperDrivePath = '/Library/Application Support/Adobe/Adobe Desktop Common/HDBox/Setup'

            if (!$.NSProcessInfo && parseFloat(app.doShellScript('sw_vers -productVersion')) >= 11.0) {
                app.displayAlert('GUI unavailable in Big Sur', {
                    message: 'JXA is currently broken in Big Sur.\\nInstall in Terminal instead?',
                    buttons: ['Cancel', 'Install in Terminal'],
                    defaultButton: 'Install in Terminal',
                    cancelButton: 'Cancel'
                })
                const cmd = shellescape([ 'sudo', hyperDrivePath, '--install=1', '--driverXML=' + driverPath ])
                app.displayDialog('Run this command in Terminal to install (press \\'OK\\' to copy to clipboard)', { defaultAnswer: cmd })
                app.setTheClipboardTo(cmd)
                return
        }

        const args = $.NSProcessInfo.processInfo.arguments
        const argv = []
        const argc = args.count
        for (var i = 0; i < argc; i++) {
            argv.push(ObjC.unwrap(args.objectAtIndex(i)))
        }
        delete args

        const installFlag = argv.indexOf('-y') > -1

        if (!installFlag) {
            app.displayAlert('Adobe Package Installer', {
                message: 'Start installation now?',
                buttons: ['Cancel', 'Install'],
                defaultButton: 'Install',
                cancelButton: 'Cancel'
            })

            const output = app.doShellScript(`"${appPath}/Contents/MacOS/applet" -y`, { administratorPrivileges: true })
            const alert = JSON.parse(output)
            alert.params ? app.displayAlert(alert.title, alert.params) : app.displayAlert(alert.title)
            return
        }

        const stdout = $.NSPipe.pipe
        const task = $.NSTask.alloc.init

        task.executableURL = $.NSURL.alloc.initFileURLWithPath(hyperDrivePath)
        task.arguments = $(['--install=1', '--driverXML=' + driverPath])
        task.standardOutput = stdout

        const dataAction = $.HandleDataAction.alloc.init
        $.NSNotificationCenter.defaultCenter.addObserverSelectorNameObject(dataAction, 'outData:', $.NSFileHandleDataAvailableNotification, stdout.fileHandleForReading)

        stdout.fileHandleForReading.waitForDataInBackgroundAndNotify

        let err = $.NSError.alloc.initWithDomainCodeUserInfo('', 0, '')
        const ret = task.launchAndReturnError(err)
        if (!ret) {
            $.puts(JSON.stringify({
                title: 'Error',
                params: {
                    message: 'Failed to launch task: ' + err.localizedDescription.UTF8String
                }
            }))
            $.exit(0)
        }

        Progress.description = "Installing packages..."
        Progress.additionalDescription = "Preparing…"
        Progress.totalUnitCount = 100

        task.waitUntilExit
        }
        """
}
