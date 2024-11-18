//
//  Adobe Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation
import SwiftUI
import AppKit


struct AppStatics {
    static let supportedLanguages: [(code: String, name: String)] = [
        ("en_US", "English (US)"),
        ("fr_FR", "Français"),
        ("de_DE", "Deutsch"),
        ("ja_JP", "日本語"),
        ("fr_CA", "Français (Canada)"),
        ("en_GB", "English (UK)"),
        ("nl_NL", "Nederlands"),
        ("it_IT", "Italiano"),
        ("es_ES", "Español"),
        ("ex_MX", "Español (Mexico)"),
        ("pt_BR", "Português (Brasil)"),
        ("pt_PT", "Português"),
        ("sv_SE", "Svenska"),
        ("da_DK", "Dansk"),
        ("fi_FI", "Suomi"),
        ("nb_NO", "Norsk"),
        ("zh_CN", "简体中文"),
        ("zh_TW", "繁體中文"),
        ("kr_KR", "한국어"),
        ("cs_CZ", "Čeština"),
        ("ht_HU", "Magyar"),
        ("pl_PL", "Polski"),
        ("ru_RU", "Русский"),
        ("uk_UA", "Українська"),
        ("tr_TR", "Türkçe"),
        ("ro_RO", "Romaân"),
        ("fr_MA", "Français (Maroc)"),
        ("en_AE", "English (UAE)"),
        ("en_IL", "English (Israel)"),
        ("ALL", "ALL")
    ]
    
    static let cpuArchitecture: String = {
        #if arch(arm64)
            return "Apple Silicon"
        #elseif arch(x86_64)
            return "Intel"
        #else
            return "Unknown Architecture"
        #endif
    }()
    
    static let isAppleSilicon: Bool = {
        #if arch(arm64)
            return true
        #elseif arch(x86_64)
            return false
        #else
            return false
        #endif
    }()

    static let architectureSymbol: String = {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x64"
        #else
            return "Unknown Architecture"
        #endif
    }()
}
