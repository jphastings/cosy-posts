import SwiftUI
@preconcurrency import Translation
import os

private let translationLog = Logger(subsystem: "com.cosyposts", category: "Translation")

/// Translation availability status for a language pair.
enum TranslationStatus: Equatable {
    case available   // installed or downloadable — translation can be attempted
    case unsupported // no translation possible for this pair
}

/// Manages on-device translation availability and text translation.
@Observable
@MainActor
final class TranslationManager {
    /// Cached availability status per target language code.
    var statuses: [String: TranslationStatus] = [:]

    /// The source language (primary locale of the compose view).
    var sourceLanguage: Locale.Language?

    /// Pending translation request.
    var pendingTranslation: (text: String, targetCode: String, completion: @MainActor (String) -> Void)?

    /// Check translation availability for all given language codes from the source language.
    func checkAvailability(for codes: [String], from source: Locale.Language) async {
        self.sourceLanguage = source
        let availability = LanguageAvailability()

        for code in codes {
            let target = Locale.Language(identifier: code)
            let status = await availability.status(from: source, to: target)
            switch status {
            case .installed, .supported:
                statuses[code] = .available
            case .unsupported:
                statuses[code] = .unsupported
            @unknown default:
                statuses[code] = .unsupported
            }
        }
    }

    /// Prepare a translation request. Returns the Configuration to set on @State.
    /// The caller must set this on their @State translationConfig to trigger .translationTask.
    func prepareTranslation(text: String, to targetCode: String, completion: @escaping @MainActor (String) -> Void) -> TranslationSession.Configuration? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translationLog.error("translate(): empty text, skipping")
            return nil
        }
        guard let source = sourceLanguage else {
            translationLog.error("translate(): no sourceLanguage set")
            return nil
        }

        let target = Locale.Language(identifier: targetCode)
        translationLog.error("translate(): \(source.languageCode?.identifier ?? "?") → \(targetCode), text=\(text.prefix(40))…")
        pendingTranslation = (text: text, targetCode: targetCode, completion: completion)
        return TranslationSession.Configuration(source: source, target: target)
    }
}
