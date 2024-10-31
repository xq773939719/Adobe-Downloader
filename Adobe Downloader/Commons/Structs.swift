//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

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

    // 这里好像不怎么需要这个script了
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

struct ApplicationInfo: Codable {
    let Name: String?
    let SAPCode: String?
    let CodexVersion: String?
    let AssetGuid: String?
    let ProductVersion: String?
    let BaseVersion: String?
    let Platform: String?
    let LbsUrl: String?
    let LanguageSet: String?
    let Packages: PackagesContainer
    let SupportedLanguages: SupportedLanguages?
    let ConflictingProcesses: ConflictingProcesses?
    let AMTConfig: AMTConfig?
    let SystemRequirement: SystemRequirement?
    let version: String?
    let NglLicensingInfo: NglLicensingInfo?
    let AppLineage: String?
    let FamilyName: String?
    let BuildGuid: String?
    let selfServeBuild: Bool?
    let HDBuilderVersion: String?
    let IsSTI: Bool?
    let AppsPanelFullAppUpdateConfig: AppsPanelFullAppUpdateConfig?
    let Cdn: CdnInfo?
    let WhatsNewUrl: UrlContainer?
    let TutorialUrl: UrlContainer?
    let AppLaunch: String?
    let InstallDir: InstallDir?
    let MoreInfoUrl: UrlContainer?
    let AddRemoveInfo: AddRemoveInfo?
    let AutoUpdate: String?
    let AppsPanelPreviousVersionConfig: AppsPanelPreviousVersionConfig?
    let ProductDescription: ProductDescription?
    let IsNonCCProduct: Bool?
    let CompressionType: String?
    let MinimumSupportedClientVersion: String?
}

struct PackagesContainer: Codable {
    let Package: [Package]
    
    struct Package: Codable {
        let PackageType: String?
        let PackageName: String?
        let PackageVersion: String?
        let DownloadSize: Int64?
        let ExtractSize: Int64?
        let Path: String
        let Format: String?
        let ValidationURL: String?
        let packageHashKey: String?
        let DeltaPackages: [DeltaPackage]?
        let ValidationURLs: ValidationURLs?
        let Condition: String?
        let InstallSequenceNumber: Int?
        let fullPackageName: String?
        let PackageValidation: String?
        let AliasPackageName: String?
        let PackageScheme: String?
        let Features: Features?
        
        var size: Int64 { DownloadSize ?? 0 }
    }
}

struct DeltaPackage: Codable {
    let SchemaVersion: String?
    let PackageName: String?
    let Path: String?
    let BasePackageVersion: String?
    let ValidationURL: String?
    let DownloadSize: Int64?
    let ExtractSize: Int64?
    let packageHashKey: String?
}

struct ValidationURLs: Codable {
    let TYPE1: String?
    let TYPE2: String?
}

struct Features: Codable {
    let Feature: [FeatureItem]
    
    struct FeatureItem: Codable {
        let name: String?
        let value: String?
    }
}

struct CdnInfo: Codable {
    let Secure: String
    let NonSecure: String
}

struct UrlContainer: Codable {
    let Stage: LanguageContainer
    let Prod: LanguageContainer
    
    struct LanguageContainer: Codable {
        let Language: [LanguageValue]
    }
    
    struct LanguageValue: Codable {
        let value: String
        let locale: String
    }
}

struct InstallDir: Codable {
    let value: String?
    let maxPath: String?
}

struct AddRemoveInfo: Codable {
    let DisplayName: LanguageContainer
    let DisplayVersion: LanguageContainer?
    let URLInfoAbout: LanguageContainer?
    
    struct LanguageContainer: Codable {
        let Language: [LanguageValue]
    }
    
    struct LanguageValue: Codable {
        let value: String
        let locale: String
    }
}

struct AppsPanelPreviousVersionConfig: Codable {
    let ListInPreviousVersion: Bool
    let BrandingName: String
}

struct ProductDescription: Codable {
    let Tagline: LanguageContainer?
    let DetailedDescription: LanguageContainer?
    
    struct LanguageContainer: Codable {
        let Language: [LanguageValue]
        
        struct LanguageValue: Codable {
            let value: String
            let locale: String
        }
    }
}

struct AppsPanelFullAppUpdateConfig: Codable {
    let PreviousVersionRange: VersionRange
    let ShowDialogBox: Bool
    let ImportPreferenceCheckBox: PreferenceCheckBox
    let RemovePreviousVersionCheckBox: PreferenceCheckBox
    
    struct VersionRange: Codable {
        let min: String
    }
    
    struct PreferenceCheckBox: Codable {
        let DefaultValue: Bool
        let Show: Bool
        let AllowToggle: Bool
    }
}

struct SupportedLanguages: Codable {
    let Language: [LanguageInfo]
    
    struct LanguageInfo: Codable {
        let value: String
        let locale: String
    }
}

struct ConflictingProcesses: Codable {
    let ConflictingProcess: [ConflictingProcess]
    
    struct ConflictingProcess: Codable {
        let RegularExpression: String
        let ProcessDisplayName: String
        let Reason: String
        let RelativePath: String
        let headless: Bool
        let forceKillAllowed: Bool
        let adobeOwned: Bool
    }
}

struct AMTConfig: Codable {
    let path: String
    let LEID: String
    let appID: String
}

struct SystemRequirement: Codable {
    let OsVersion: OsVersion?
    let SupportedOsVersionRange: [OsVersionRange]?
    let ExternalUrl: ExternalUrl
    let CheckCompatibility: CheckCompatibility
    
    struct OsVersion: Codable {
        let min: String
    }
    
    struct OsVersionRange: Codable {
        let min: String
    }
    
    struct ExternalUrl: Codable {
        let Stage: LanguageUrls
        let Prod: LanguageUrls
        
        struct LanguageUrls: Codable {
            let Language: [LanguageUrl]
            
            struct LanguageUrl: Codable {
                let value: String
                let locale: String
            }
        }
    }
    
    struct CheckCompatibility: Codable {
        let Content: String
    }
}

struct NglLicensingInfo: Codable {
    let AppId: String
    let AppVersion: String
    let LibVersion: String
    let BuildId: String
    let ImsClientId: String
} 
