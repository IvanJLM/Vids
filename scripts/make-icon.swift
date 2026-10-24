// Draws Vids' app icon (same family as Visor and TextDown) and writes every size
// into the asset catalog.
// Usage: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let context = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Background: the same dark squircle as Visor.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: color(0x0F111A), ending: color(0x2C3350))!.draw(in: tilePath, angle: 90)

// A 16:9 screen, dark like a paused video.
let screen = NSRect(x: 196, y: 300, width: 632, height: 424)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor(white: 0, alpha: 0.45).cgColor)
let screenPath = NSBezierPath(roundedRect: screen, xRadius: 46, yRadius: 46)
NSGradient(starting: color(0x1A1E2E), ending: color(0x3A4266))!.draw(in: screenPath, angle: 90)
context.restoreGState()
color(0xFFFFFF, 0.10).setStroke()
screenPath.lineWidth = 6
screenPath.stroke()

// The play triangle in Visor's sunset colors, with rounded corners.
let sunset = NSGradient(colors: [color(0xF2A35E), color(0xDC5A75), color(0x8E55C2)])!
let triangle = CGMutablePath()
let a = CGPoint(x: 452, y: 612), b = CGPoint(x: 452, y: 412), c = CGPoint(x: 612, y: 512)
triangle.move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
triangle.addArc(tangent1End: b, tangent2End: c, radius: 22)
triangle.addArc(tangent1End: c, tangent2End: a, radius: 22)
triangle.addArc(tangent1End: a, tangent2End: b, radius: 22)
triangle.closeSubpath()
context.saveGState()
context.addPath(triangle)
context.clip()
sunset.draw(in: NSRect(x: 440, y: 400, width: 184, height: 224), angle: -60)
context.restoreGState()

// A progress bar under the screen.
color(0x2C3350, 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 196, y: 214, width: 632, height: 26), xRadius: 13, yRadius: 13).fill()
context.saveGState()
NSBezierPath(roundedRect: NSRect(x: 196, y: 214, width: 380, height: 26), xRadius: 13, yRadius: 13).addClip()
sunset.draw(in: NSRect(x: 196, y: 214, width: 632, height: 26), angle: 0)
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!

let folder = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let master = folder.appendingPathComponent("icon_512x512@2x.png")
try png.write(to: master)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let pixels = points * scale
        if pixels != 1024 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            task.arguments = ["-z", "\(pixels)", "\(pixels)", master.path, "--out", folder.appendingPathComponent(name).path]
            task.standardOutput = FileHandle.nullDevice
            try task.run()
            task.waitUntilExit()
        }
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: folder.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.write(
    to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Icon written to \(folder.path)")
