#!/usr/bin/env swift

import AppKit
import Foundation

struct CLI {
    let outputURL: URL

    init(arguments: [String]) throws {
        guard arguments.count >= 3, arguments[1] == "--output" else {
            throw NSError(
                domain: "render_toolbar_icon",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Usage: render_toolbar_icon.swift --output /path/to/file.png"]
            )
        }

        self.outputURL = URL(fileURLWithPath: arguments[2])
    }
}

let cli = try CLI(arguments: CommandLine.arguments)
let canvasSize = NSSize(width: 72, height: 44)
let image = NSImage(size: canvasSize)

image.lockFocus()

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

let white = NSColor.white
white.setFill()

let head = NSBezierPath()
head.move(to: NSPoint(x: 14, y: 15))
head.curve(to: NSPoint(x: 19, y: 31), controlPoint1: NSPoint(x: 12, y: 22), controlPoint2: NSPoint(x: 14, y: 28))
head.line(to: NSPoint(x: 25, y: 39))
head.line(to: NSPoint(x: 30, y: 31))
head.curve(to: NSPoint(x: 42, y: 31), controlPoint1: NSPoint(x: 33, y: 29), controlPoint2: NSPoint(x: 39, y: 29))
head.line(to: NSPoint(x: 47, y: 39))
head.line(to: NSPoint(x: 53, y: 31))
head.curve(to: NSPoint(x: 58, y: 15), controlPoint1: NSPoint(x: 58, y: 28), controlPoint2: NSPoint(x: 60, y: 22))
head.curve(to: NSPoint(x: 36, y: 4), controlPoint1: NSPoint(x: 55, y: 8), controlPoint2: NSPoint(x: 47, y: 4))
head.curve(to: NSPoint(x: 14, y: 15), controlPoint1: NSPoint(x: 25, y: 4), controlPoint2: NSPoint(x: 17, y: 8))
head.close()
head.fill()

NSColor.clear.setFill()

func punchEye(at center: NSPoint) {
    let outer = NSBezierPath(ovalIn: NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
    NSGraphicsContext.current?.compositingOperation = .clear
    outer.fill()

    NSGraphicsContext.current?.compositingOperation = .sourceOver
    let pupil = NSBezierPath(ovalIn: NSRect(x: center.x - 2.4, y: center.y - 2.4, width: 4.8, height: 4.8))
    white.setFill()
    pupil.fill()
}

punchEye(at: NSPoint(x: 27.5, y: 19.5))
punchEye(at: NSPoint(x: 44.5, y: 19.5))

let beak = NSBezierPath()
beak.move(to: NSPoint(x: 36, y: 9))
beak.line(to: NSPoint(x: 31, y: 16))
beak.line(to: NSPoint(x: 41, y: 16))
beak.close()
beak.fill()

let chest = NSBezierPath()
chest.lineWidth = 3.6
chest.lineCapStyle = .round
chest.move(to: NSPoint(x: 27, y: 8))
chest.line(to: NSPoint(x: 36, y: 3))
chest.line(to: NSPoint(x: 45, y: 8))
white.setStroke()
chest.stroke()

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "render_toolbar_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
}

try FileManager.default.createDirectory(at: cli.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: cli.outputURL)
