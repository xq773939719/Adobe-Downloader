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
        ("zh_CN", "简体中文"),
        ("zh_TW", "繁體中文"),
        ("en_US", "English (US)"),
        ("en_GB", "English (UK)"),
        ("ja_JP", "日本語"),
        ("ko_KR", "한국어"),
        ("fr_FR", "Français"),
        ("de_DE", "Deutsch"),
        ("es_ES", "Español"),
        ("it_IT", "Italiano"),
        ("ru_RU", "Русский"),
        ("pt_BR", "Português (Brasil)"),
        ("nl_NL", "Nederlands"),
        ("pl_PL", "Polski"),
        ("tr_TR", "Türkçe"),
        ("sv_SE", "Svenska"),
        ("da_DK", "Dansk"),
        ("fi_FI", "Suomi"),
        ("nb_NO", "Norsk"),
        ("cs_CZ", "Čeština"),
        ("hu_HU", "Magyar"),
        ("ALL", "所有语言")
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
