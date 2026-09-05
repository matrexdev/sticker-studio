import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case turkish = "tr"

    var name: String {
        switch self {
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .english
        return localized(key, language: language, arguments: arguments)
    }

    static func localized(_ key: String, language: AppLanguage, arguments: [CVarArg] = []) -> String {
        let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return arguments.isEmpty ? format : String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}

struct AppearancePreference: ViewModifier {
    @AppStorage("appAppearance") private var appearance = "system"

    func body(content: Content) -> some View {
        content.preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}
