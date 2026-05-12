#if os(macOS)
import AppKit
import SwiftUI

enum BrandPalette {
    static let primary = Color(red: 11 / 255, green: 31 / 255, blue: 58 / 255)
    static let accent = Color(red: 0 / 255, green: 209 / 255, blue: 1.0)
    static let background = Color(red: 10 / 255, green: 15 / 255, blue: 31 / 255)
    static let card = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.10)
}

enum BrandAssets {
    static func toolbarIconImage() -> NSImage? {
        guard let url = resourceURL(for: "toolbar_native", extension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 14)
        return image
    }

    static func logoImage() -> NSImage? {
        guard let url = resourceURL(for: "logo_512", extension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    private static func resourceURL(for name: String, extension fileExtension: String) -> URL? {
        let bundleName = "overwatchr_OverwatchrApp.bundle"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName)
        ].compactMap { $0 }

        for bundleURL in candidates {
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: fileExtension) {
                return url
            }
        }
        return nil
    }
}
#endif
