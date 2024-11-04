//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import SwiftUI

struct LanguagePickerView: View {
    let languages: [(code: String, name: String)]
    let onLanguageSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultLanguage") private var defaultLanguage: String = "zh_CN"
    @State private var searchText: String = ""
    
    private var filteredLanguages: [(code: String, name: String)] {
        guard !searchText.isEmpty else {
            return languages
        }
        
        let searchTerms = searchText.lowercased()
        return languages.filter { language in
            language.name.lowercased().contains(searchTerms) ||
            language.code.lowercased().contains(searchTerms)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择安装语言")
                    .font(.headline)
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索语言", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredLanguages.enumerated()), id: \.element.code) { index, language in
                        LanguageRow(
                            language: language,
                            isSelected: language.code == defaultLanguage,
                            onSelect: {
                                defaultLanguage = language.code
                                onLanguageSelected(language.code)
                                dismiss()
                            }
                        )
                        
                        if index < filteredLanguages.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            
            if filteredLanguages.isEmpty {
                ContentUnavailableView(
                    "未找到语言",
                    systemImage: "magnifyingglass",
                    description: Text("尝试其他搜索关键词")
                )
            }
        }
        .frame(width: 320, height: 400)
    }
}

struct LanguageRow: View {
    let language: (code: String, name: String)
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: getLanguageIcon(language.code))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(language.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(language.code)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
    }
    
    private func getLanguageIcon(_ code: String) -> String {
        switch code {
        case "zh_CN", "zh_TW":
            return "character.textbox"
        case "en_US", "en_GB":
            return "a.square"
        case "ja_JP":
            return "j.square"
        case "ko_KR":
            return "k.square"
        case "fr_FR":
            return "f.square"
        case "de_DE":
            return "d.square"
        case "es_ES":
            return "e.square"
        case "it_IT":
            return "i.square"
        case "ru_RU":
            return "r.square"
        case "ALL":
            return "globe"
        default:
            return "character.square"
        }
    }
}

#Preview {
    LanguagePickerView(
        languages: AppStatics.supportedLanguages,
        onLanguageSelected: { _ in }
    )
}
