// Draws the app icon (a glowing light bulb) and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift   (only needed when the design changes; the .icns is committed)
import AppKit

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    let u = s / 1024  // all coordinates below are on a 1024 grid
    ctx.saveGState()
    ctx.scaleBy(x: u, y: u)
    let space = CGColorSpaceCreateDeviceRGB()

    // Tile: standard macOS icon grid (824 pt tile inside 1024 pt canvas).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor(red: 0.12, green: 0.10, blue: 0.22, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep violet at the bottom to warm magenta at the top.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let bg = [NSColor(red: 0.13, green: 0.11, blue: 0.30, alpha: 1).cgColor,
              NSColor(red: 0.55, green: 0.20, blue: 0.52, alpha: 1).cgColor] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: bg, locations: [0, 1])!,
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Warm glow behind the bulb.
    let glow = [NSColor(red: 1.0, green: 0.82, blue: 0.45, alpha: 0.75).cgColor,
                NSColor(red: 1.0, green: 0.60, blue: 0.30, alpha: 0).cgColor] as CFArray
    ctx.drawRadialGradient(CGGradient(colorsSpace: space, colors: glow, locations: [0, 1])!,
                           startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 600), endRadius: 400, options: [])
    ctx.restoreGState()

    // Bulb glass: a circle that narrows into a neck.
    let bulb = CGMutablePath()
    bulb.addArc(center: CGPoint(x: 512, y: 600), radius: 200, startAngle: -.pi * 0.22, endAngle: .pi * 1.22, clockwise: false)
    bulb.addCurve(to: CGPoint(x: 430, y: 390), control1: CGPoint(x: 360, y: 460), control2: CGPoint(x: 430, y: 440))
    bulb.addLine(to: CGPoint(x: 594, y: 390))
    bulb.addCurve(to: CGPoint(x: 512 + 200 * cos(-.pi * 0.22), y: 600 + 200 * sin(-.pi * 0.22)),
                  control1: CGPoint(x: 594, y: 440), control2: CGPoint(x: 664, y: 460))
    bulb.closeSubpath()
    ctx.saveGState()
    ctx.addPath(bulb)
    ctx.clip()
    let glass = [NSColor(red: 1.0, green: 0.97, blue: 0.85, alpha: 1).cgColor,
                 NSColor(red: 1.0, green: 0.80, blue: 0.40, alpha: 1).cgColor] as CFArray
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: glass, locations: [0, 1])!,
                           start: CGPoint(x: 512, y: 800), end: CGPoint(x: 512, y: 390), options: [])
    ctx.restoreGState()

    // Screw base: three rounded bands.
    ctx.setFillColor(NSColor(white: 0.92, alpha: 1).cgColor)
    for (i, y) in [350.0, 300.0, 250.0].enumerated() {
        let inset = CGFloat(i) * 8
        let band = CGRect(x: 440 + inset, y: y, width: 144 - inset * 2, height: 36)
        ctx.addPath(CGPath(roundedRect: band, cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    drawIcon(in: gc.cgContext, size: CGFloat(size))
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
let preview = fm.temporaryDirectory.appendingPathComponent("AppIcon-preview.png")
try? png(size: 1024).write(to: preview)
print("Wrote \(out.path) (status \(p.terminationStatus)); preview: \(preview.path)")
