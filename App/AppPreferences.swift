#if os(macOS)
import Foundation

enum AppPreferenceKey {
    static let alertChimeEnabled = "alertChimeEnabled"
}

struct AppPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var alertChimeEnabled: Bool {
        get { defaults.bool(forKey: AppPreferenceKey.alertChimeEnabled) }
        set { defaults.set(newValue, forKey: AppPreferenceKey.alertChimeEnabled) }
    }
}
#endif
