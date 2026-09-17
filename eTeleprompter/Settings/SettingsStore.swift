import Foundation
import Observation

/// Observable store for the global ReadingSettings (WP4). Loads once at init
/// and persists every mutation as JSON `Data` under the single
/// `"readingSettings"` UserDefaults key (the same key `@AppStorage` would
/// use — see team/PLAN.md). Views bind straight to `store.settings.*`.
@Observable
final class SettingsStore {
    /// UserDefaults key holding the JSON-encoded ReadingSettings.
    static let storageKey = "readingSettings"

    /// The current settings. Every assignment (including nested mutations
    /// like `store.settings.fontSize = 60`) is persisted immediately.
    var settings: ReadingSettings {
        get { storage }
        set {
            storage = newValue
            persist()
        }
    }

    private var storage: ReadingSettings
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameters:
    ///   - userDefaults: injection point for tests; production uses `.standard`.
    ///   - fallback: used when nothing valid is stored yet. The app passes
    ///     `.phoneDefault` on iPhone; the platform check stays out of this
    ///     Foundation-only module.
    init(userDefaults: UserDefaults = .standard,
         fallback: ReadingSettings = .default) {
        self.defaults = userDefaults
        if let data = userDefaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ReadingSettings.self, from: data) {
            storage = decoded
        } else {
            // Missing or corrupt data: fall back to the supplied defaults.
            storage = fallback
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
