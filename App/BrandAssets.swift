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
        guard let url = Bundle.module.url(forResource: "toolbar_native", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = NSSize(width: 18, height: 14)
        return image
    }

    static func logoImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "logo_512", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }
}
#endif
