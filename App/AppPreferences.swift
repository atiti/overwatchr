#if os(macOS)
import Foundation

enum AppPreferenceKey {
    static let alertChimeEnabled = "alertChimeEnabled"
    static let jumpSoundEnabled = "jumpSoundEnabled"
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

    var jumpSoundEnabled: Bool {
        get {
            if defaults.object(forKey: AppPreferenceKey.jumpSoundEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: AppPreferenceKey.jumpSoundEnabled)
        }
        set { defaults.set(newValue, forKey: AppPreferenceKey.jumpSoundEnabled) }
    }
}
#endif
