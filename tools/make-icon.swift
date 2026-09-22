import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let names: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
for (name, pixels) in names {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let s = CGFloat(pixels)
    let rect = NSRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.48, blue: 0.95, alpha: 1), ending: NSColor(calibratedRed: 0.30, green: 0.25, blue: 0.80, alpha: 1))!.draw(in: shape, angle: -60)
    if let symbol = NSImage(systemSymbolName: "person.crop.circle.badge.checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: s * 0.48, weight: .medium)) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let ratio = min(s * 0.60 / symbol.size.width, s * 0.60 / symbol.size.height)
        let size = NSSize(width: symbol.size.width * ratio, height: symbol.size.height * ratio)
        tinted.draw(in: NSRect(x: (s-size.width)/2, y: (s-size.height)/2, width: size.width, height: size.height))
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = bitmap.representation(using: .png, properties: [:])!
    try png.write(to: directory.appendingPathComponent(name + ".png"))
}
