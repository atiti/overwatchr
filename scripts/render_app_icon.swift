#!/usr/bin/env swift

import AppKit
import Foundation

struct CLI {
    let size: CGFloat
    let outputURL: URL

    init(arguments: [String]) throws {
        var size: CGFloat = 1024
        var outputPath: String?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--size":
                index += 1
                guard index < arguments.count, let parsed = Double(arguments[index]) else {
                    throw NSError(domain: "render_app_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing --size value"])
                }
                size = CGFloat(parsed)
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw NSError(domain: "render_app_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing --output value"])
                }
                outputPath = arguments[index]
            default:
                break
            }
            index += 1
        }

        guard let outputPath else {
            throw NSError(domain: "render_app_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Provide --output /path/to/icon.png"])
        }

        self.size = size
        self.outputURL = URL(fileURLWithPath: outputPath)
    }
}

let cli = try CLI(arguments: CommandLine.arguments)
let size = NSSize(width: cli.size, height: cli.size)
let image = NSImage(size: size)

image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.09, green: 0.49, blue: 0.82, alpha: 1)
])!
gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: cli.size * 0.22, yRadius: cli.size * 0.22), angle: 270)

let innerRect = rect.insetBy(dx: cli.size * 0.18, dy: cli.size * 0.18)
NSColor.white.withAlphaComponent(0.10).setFill()
NSBezierPath(ovalIn: innerRect).fill()

let strokeRect = rect.insetBy(dx: cli.size * 0.24, dy: cli.size * 0.24)
let ring = NSBezierPath(ovalIn: strokeRect)
ring.lineWidth = cli.size * 0.055
NSColor.white.withAlphaComponent(0.92).setStroke()
ring.stroke()

let sweep = NSBezierPath()
sweep.lineWidth = cli.size * 0.055
sweep.lineCapStyle = .round
sweep.appendArc(
    withCenter: NSPoint(x: rect.midX, y: rect.midY),
    radius: cli.size * 0.26,
    startAngle: 30,
    endAngle: 132,
    clockwise: false
)
NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.28, alpha: 1).setStroke()
sweep.stroke()

let dotRect = NSRect(
    x: rect.midX - cli.size * 0.06,
    y: rect.midY - cli.size * 0.06,
    width: cli.size * 0.12,
    height: cli.size * 0.12
)
NSColor.white.setFill()
NSBezierPath(ovalIn: dotRect).fill()

let badgeRect = NSRect(
    x: rect.maxX - cli.size * 0.31,
    y: rect.minY + cli.size * 0.12,
    width: cli.size * 0.19,
    height: cli.size * 0.19
)
NSColor(calibratedRed: 0.98, green: 0.38, blue: 0.23, alpha: 1).setFill()
NSBezierPath(ovalIn: badgeRect).fill()

let badgeText = "!"
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: cli.size * 0.13, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let badgeString = NSAttributedString(string: badgeText, attributes: attributes)
let badgeTextRect = NSRect(
    x: badgeRect.minX,
    y: badgeRect.minY + cli.size * 0.018,
    width: badgeRect.width,
    height: badgeRect.height
)
badgeString.draw(in: badgeTextRect)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "render_app_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render icon PNG"])
}

try FileManager.default.createDirectory(at: cli.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: cli.outputURL)

