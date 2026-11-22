import Foundation

/// A screen colour with components 0...1 (sRGB).
public struct RGB: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public static let white = RGB(r: 1, g: 1, b: 1)
}

/// Hue (0...1 around the wheel), saturation 0...1, brightness 0...1.
public struct HSB: Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double
    public init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue; self.saturation = saturation; self.brightness = brightness
    }
}

/// Colour maths: Hue lights take colours as CIE "xy" points and whites as "mirek" (a million divided by Kelvin).
public enum ColorConversion {
    public static let whitePoint = XY(x: 0.3127, y: 0.3290) // D65

    // MARK: sRGB <-> xy

    public static func xy(from rgb: RGB) -> XY {
        let r = linear(rgb.r), g = linear(rgb.g), b = linear(rgb.b)
        let X = r * 0.4124 + g * 0.3576 + b * 0.1805
        let Y = r * 0.2126 + g * 0.7152 + b * 0.0722
        let Z = r * 0.0193 + g * 0.1192 + b * 0.9505
        let sum = X + Y + Z
        guard sum > 0 else { return whitePoint }
        return XY(x: X / sum, y: Y / sum)
    }

    /// The brightest screen colour for an xy point (brightness is handled separately by the light).
    public static func rgb(from xy: XY) -> RGB {
        guard xy.y > 0 else { return .white }
        let Y = 1.0
        let X = (Y / xy.y) * xy.x
        let Z = (Y / xy.y) * (1 - xy.x - xy.y)
        var r = X * 3.2406 - Y * 1.5372 - Z * 0.4986
        var g = -X * 0.9689 + Y * 1.8758 + Z * 0.0415
        var b = X * 0.0557 - Y * 0.2040 + Z * 1.0570
        r = max(r, 0); g = max(g, 0); b = max(b, 0)
        let m = max(r, g, b)
        if m > 0 { r /= m; g /= m; b /= m }
        return RGB(r: gamma(r), g: gamma(g), b: gamma(b))
    }

    private static func linear(_ c: Double) -> Double {
        let c = min(max(c, 0), 1)
        return c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
    }

    private static func gamma(_ c: Double) -> Double {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }

    // MARK: Gamut (the colours a particular light can actually make)

    /// Moves a point that lies outside the light's colour triangle to the nearest point on its edge.
    public static func clamp(_ p: XY, to gamut: Gamut) -> XY {
        if isInside(p, gamut) { return p }
        let candidates = [
            closestPoint(p, gamut.red, gamut.green),
            closestPoint(p, gamut.green, gamut.blue),
            closestPoint(p, gamut.blue, gamut.red),
        ]
        return candidates.min { distance($0, p) < distance($1, p) }!
    }

    public static func isInside(_ p: XY, _ g: Gamut) -> Bool {
        func sign(_ a: XY, _ b: XY, _ c: XY) -> Double { (a.x - c.x) * (b.y - c.y) - (b.x - c.x) * (a.y - c.y) }
        let d1 = sign(p, g.red, g.green), d2 = sign(p, g.green, g.blue), d3 = sign(p, g.blue, g.red)
        let hasNeg = d1 < 0 || d2 < 0 || d3 < 0
        let hasPos = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNeg && hasPos)
    }

    private static func closestPoint(_ p: XY, _ a: XY, _ b: XY) -> XY {
        let abx = b.x - a.x, aby = b.y - a.y
        let len = abx * abx + aby * aby
        guard len > 0 else { return a }
        let t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / len, 0), 1)
        return XY(x: a.x + t * abx, y: a.y + t * aby)
    }

    private static func distance(_ a: XY, _ b: XY) -> Double { hypot(a.x - b.x, a.y - b.y) }

    // MARK: White temperature

    public static func kelvin(fromMirek mirek: Int) -> Double { 1_000_000 / Double(max(mirek, 1)) }
    public static func mirek(fromKelvin kelvin: Double) -> Int { Int((1_000_000 / max(kelvin, 1)).rounded()) }

    /// Roughly what a white of this temperature looks like on screen (Tanner Helland's approximation).
    public static func rgb(kelvin: Double) -> RGB {
        let t = min(max(kelvin, 1000), 40000) / 100
        let r: Double = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g: Double = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b: Double = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func c(_ v: Double) -> Double { min(max(v, 0), 255) / 255 }
        return RGB(r: c(r), g: c(g), b: c(b))
    }

    // MARK: Colour wheel (hue/saturation) <-> RGB

    public static func rgb(from hsb: HSB) -> RGB {
        let h = (hsb.hue - floor(hsb.hue)) * 6
        let s = min(max(hsb.saturation, 0), 1), v = min(max(hsb.brightness, 0), 1)
        let i = Int(h) % 6
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return RGB(r: v, g: t, b: p)
        case 1: return RGB(r: q, g: v, b: p)
        case 2: return RGB(r: p, g: v, b: t)
        case 3: return RGB(r: p, g: q, b: v)
        case 4: return RGB(r: t, g: p, b: v)
        default: return RGB(r: v, g: p, b: q)
        }
    }

    public static func hsb(from rgb: RGB) -> HSB {
        let mx = max(rgb.r, rgb.g, rgb.b), mn = min(rgb.r, rgb.g, rgb.b)
        let d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == rgb.r { h = (rgb.g - rgb.b) / d } else if mx == rgb.g { h = (rgb.b - rgb.r) / d + 2 } else { h = (rgb.r - rgb.g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return HSB(hue: h, saturation: mx > 0 ? d / mx : 0, brightness: mx)
    }
}
