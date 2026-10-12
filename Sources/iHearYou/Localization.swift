// iHearYou | Signature: i729
import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en", indonesian = "id"
    var displayName: String { self == .english ? "English" : "Bahasa Indonesia" }
    var locale: Locale { Locale(identifier: self == .english ? "en_US" : "id_ID") }
}

/// Also used by the audio/network queues when they report an error. Language
/// changes do not restart capture, recording, or a network listener.
enum L10n {
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .english
        var messages: [String: (english: String, indonesian: String)] = [:]
    }
    private static let store = Store()
    static var language: AppLanguage {
        get { store.lock.lock(); defer { store.lock.unlock() }; return store.language }
        set { store.lock.lock(); store.language = newValue; store.lock.unlock() }
    }
    static func text(_ english: String, _ indonesian: String, language: AppLanguage? = nil) -> String {
        store.lock.lock(); defer { store.lock.unlock() }
        // Remember complete message pairs so a visible notice can change language.
        // Limit this cache: device names, export filenames, and errors may vary.
        if store.messages.count > 2048 { store.messages.removeAll(keepingCapacity: true) }
        let pair = (english: english, indonesian: indonesian)
        store.messages[english] = pair; store.messages[indonesian] = pair
        return (language ?? store.language) == .english ? english : indonesian
    }
    static func retranslate(_ message: String?, language: AppLanguage) -> String? {
        guard let message else { return nil }
        store.lock.lock(); defer { store.lock.unlock() }
        guard let pair = store.messages[message] else { return message }
        return language == .english ? pair.english : pair.indonesian
    }
}

func L(_ english: String, _ indonesian: String) -> String { L10n.text(english, indonesian) }
