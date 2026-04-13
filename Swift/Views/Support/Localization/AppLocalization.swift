import Foundation
import SwiftUI
enum AppLocalization {
    private final class BundleMarker {}
    private struct LocalizationState {
        let signature: String
        let identifiers: [String]
        let locale: Locale
        let bundles: [Bundle]
    }
    private struct RuntimeStringCatalog: Decodable {
        let sourceLanguage: String
        let locales: [String: [String: String]]
    }
    private static let candidateBundles: [Bundle] = {
        var seen = Set<URL>()
        return ([Bundle.main, Bundle(for: BundleMarker.self)] + Bundle.allBundles + Bundle.allFrameworks).filter { bundle in
            guard let bundleURL = bundle.bundleURL.standardizedFileURL as URL? else { return false }
            return seen.insert(bundleURL).inserted
        }}()
    private static var localizedStringCache: [String: String] = [:]
    private static var cachedState: LocalizationState?
    private static var runtimeCatalog: RuntimeStringCatalog?
    private static var runtimeCatalogLoadAttempted = false
    static var locale: Locale { localizationState().locale }
    static func string(_ key: String, table: String? = nil) -> String {
        let state = localizationState()
        let signature = state.signature
        let cacheKey = "\(signature)|\(table ?? "<default>")|\(key)"
        if let cachedValue = localizedStringCache[cacheKey] { return cachedValue }
        if let runtimeValue = runtimeString(for: key, localizationIdentifiers: state.identifiers) {
            localizedStringCache[cacheKey] = runtimeValue
            return runtimeValue
        }
        for bundle in state.bundles {
            let value = bundle.localizedString(forKey: key, value: key, table: table)
            if value != key {
                localizedStringCache[cacheKey] = value
                return value
            }}
        let fallbackValue: String
        if let developmentPath = Bundle.main.path(forResource: Bundle.main.developmentLocalization ?? "en", ofType: "lproj"), let developmentBundle = Bundle(path: developmentPath) { fallbackValue = developmentBundle.localizedString(forKey: key, value: key, table: table) } else { fallbackValue = Bundle.main.localizedString(forKey: key, value: key, table: table) }
        localizedStringCache[cacheKey] = fallbackValue
        return fallbackValue
    }
    static func preferredLocalizationIdentifiers() -> [String] { localizationState().identifiers }
    private static func localizationState() -> LocalizationState {
        let signature = preferenceSignature()
        if let cachedState, cachedState.signature == signature { return cachedState }
        let supported = supportedLocalizationIdentifiers()
        guard !supported.isEmpty else {
            let state = LocalizationState(
                signature: signature, identifiers: ["en"], locale: Locale(identifier: "en"), bundles: [Bundle.main]
            )
            cachedState = state
            return state
        }
        let development = loadRuntimeCatalog()?.sourceLanguage ?? Bundle.main.developmentLocalization ?? "en"
        let preferred = preferredLanguageCandidates()
        let resolved = preferred.compactMap { preferredLocalization(for: $0, supported: supported) }
        var ordered: [String] = []
        var seen = Set<String>()
        for localization in resolved where seen.insert(localization).inserted { ordered.append(localization) }
        if seen.insert(development).inserted { ordered.append(development) }
        if seen.insert("Base").inserted { ordered.append("Base") }
        let bundles = ordered.compactMap { identifier in
            guard identifier != "Base" else { return Bundle.main }
            guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
            return bundle
        } + [Bundle.main]
        let state = LocalizationState(
            signature: signature, identifiers: ordered, locale: Locale(identifier: ordered.first ?? development), bundles: bundles
        )
        cachedState = state
        return state
    }
    private static func preferenceSignature() -> String { (Locale.preferredLanguages + Bundle.main.preferredLocalizations).joined(separator: "|") }
    private static func supportedLocalizationIdentifiers() -> [String] {
        var supported = Set(Bundle.main.localizations.filter { $0 != "Base" })
        if let catalog = loadRuntimeCatalog() {
            supported.formUnion(catalog.locales.keys)
            supported.insert(catalog.sourceLanguage)
        }
        return supported.isEmpty ? ["en"] : supported.sorted()
    }
    private static func preferredLanguageCandidates() -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()
        for identifier in Locale.preferredLanguages + Bundle.main.preferredLocalizations {
            for fallback in localizationFallbacks(for: identifier) where seen.insert(fallback).inserted { candidates.append(fallback) }}
        if candidates.isEmpty {
            let fallbackIdentifiers = [loadRuntimeCatalog()?.sourceLanguage ?? Bundle.main.developmentLocalization ?? "en"]
            for identifier in fallbackIdentifiers {
                for fallback in localizationFallbacks(for: identifier) where seen.insert(fallback).inserted { candidates.append(fallback) }}}
        return candidates
    }
    private static func preferredLocalization(for identifier: String, supported: [String]) -> String? {
        if supported.contains(identifier) { return identifier }
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if supported.contains(normalized) { return normalized }
        if normalized.lowercased().hasPrefix("zh-hans"), supported.contains("zh-Hans") { return "zh-Hans" }
        if normalized.lowercased().hasPrefix("zh-hant"), supported.contains("zh-Hant") { return "zh-Hant" }
        let languageCode = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return supported.first(where: { $0.caseInsensitiveCompare(languageCode) == .orderedSame })
    }
    private static func localizationFallbacks(for identifier: String) -> [String] {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let components = normalized.split(separator: "-").map(String.init)
        guard !components.isEmpty else { return [] }
        var fallbacks: [String] = []
        for index in stride(from: components.count, through: 1, by: -1) { fallbacks.append(components.prefix(index).joined(separator: "-")) }
        return fallbacks
    }
    private static func runtimeString(for key: String, localizationIdentifiers: [String]) -> String? {
        guard let catalog = loadRuntimeCatalog() else { return nil }
        for identifier in localizationIdentifiers {
            for fallback in localizationFallbacks(for: identifier) {
                if let value = catalog.locales[fallback]?[key] { return value }}}
        return catalog.locales[catalog.sourceLanguage]?[key]
    }
    private static func loadRuntimeCatalog() -> RuntimeStringCatalog? {
        if runtimeCatalogLoadAttempted { return runtimeCatalog }
        runtimeCatalogLoadAttempted = true
        let decoder = JSONDecoder()
        for bundle in candidateBundles {
            guard let resourceURL = bundle.resourceURL else { continue }
            let candidateURLs = [
                resourceURL.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent("Localization", isDirectory: true).appendingPathComponent("RuntimeStrings.json", isDirectory: false), resourceURL.appendingPathComponent("Localization", isDirectory: true).appendingPathComponent("RuntimeStrings.json", isDirectory: false), resourceURL.appendingPathComponent("RuntimeStrings.json", isDirectory: false), ]
            for url in candidateURLs {
                guard let data = try? Data(contentsOf: url), let catalog = try? decoder.decode(RuntimeStringCatalog.self, from: data) else { continue }
                runtimeCatalog = catalog
                return catalog
            }}
        return nil
    }
}
