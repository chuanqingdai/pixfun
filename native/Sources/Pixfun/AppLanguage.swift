import Foundation
import SwiftUI
import AppKit

/// Persist the preference, not the system's current resolved appearance.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let preferenceKey = "appAppearance"
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "Follow system"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var nativeAppearance: NSAppearance? {
        switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) }
    }
    static func read(from defaults: UserDefaults = .standard) -> AppAppearance {
        AppAppearance(rawValue: defaults.string(forKey: preferenceKey) ?? "system") ?? .system
    }
    func persist(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"
    var id: String { rawValue }
    var name: String { self == .chinese ? "简体中文" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
    func text(_ key: String) -> String {
        let bundle = Bundle.main.path(forResource: rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static var saved: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans") ?? .chinese
    }
}

/// A value-type snapshot: choosing a control cannot mutate persisted settings.
struct AppSettingsDraft: Equatable {
    var language: AppLanguage = .chinese
    var appearance: AppAppearance = .system
    var cloud = CloudSettings()
    var mode = "local"
    var onlinePlaceNames = false
    var onlinePlaceBoundaries = false
    var onlinePlaceFallback = false
    func requiresCloudSave(comparedTo original: Self) -> Bool {
        cloud != original.cloud || mode != original.mode
    }
    var validationIssue: String? {
        guard mode != "local" else { return nil }
        if cloud.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a text model ID." }
        if cloud.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter an API key." }
        if mode == "cloud", cloud.visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a vision model ID." }
        return nil
    }
}
