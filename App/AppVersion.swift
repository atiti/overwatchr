#if os(macOS)
import Foundation

enum AppVersion {
    static var displayString: String {
        if let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !shortVersion.isEmpty {
            return normalized(shortVersion)
        }

        if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !bundleVersion.isEmpty {
            return normalized(bundleVersion)
        }

        return "dev"
    }

    private static func normalized(_ version: String) -> String {
        version.hasPrefix("v") ? version : "v\(version)"
    }
}
#endif
