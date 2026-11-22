import AppKit
import HueKit
import SwiftUI

extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

extension Light {
    /// Roughly what the light looks like right now, for the little colour dots.
    var displayColor: Color {
        guard on.on else { return Color.secondary.opacity(0.25) }
        if isInWhiteMode, let mirek = colorTemperature?.mirek {
            return ColorConversion.rgb(kelvin: ColorConversion.kelvin(fromMirek: mirek)).color
        }
        if let xy = color?.xy { return ColorConversion.rgb(from: xy).color }
        return ColorConversion.rgb(kelvin: 2700).color
    }
}

/// A brightness slider that never jumps under your finger.
///
/// While dragging it shows your own value, whatever the bridge reports meanwhile (a lesson from the Sonos app's
/// menu, which rebuilt itself mid-click). Only whole-number changes are sent. After you let go, the store holds
/// your value until the bridge has caught up (see the shields in HueStore), so it doesn't flick back.
struct BrightnessSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    var onDim: Bool = true

    @State private var dragValue: Double?
    @State private var lastSent: Double?

    var body: some View {
        Slider(
            value: Binding(
                get: { dragValue ?? value },
                set: { new in
                    dragValue = new
                    send(new)
                }),
            in: 1...100,
            onEditingChanged: { editing in
                if !editing {
                    if let v = dragValue { send(v) }
                    dragValue = nil
                    lastSent = nil
                }
            })
        .opacity(onDim ? 1 : 0.55)
        .accessibilityLabel("Brightness")
    }

    private func send(_ v: Double) {
        let rounded = min(max(v.rounded(), 1), 100)
        guard rounded != lastSent else { return }
        lastSent = rounded
        onChange(rounded)
    }
}

/// An on/off switch that always flips what's really true (the store decides), never its own idea of the state.
struct PowerSwitch: View {
    let isOn: Bool
    let toggle: () -> Void
    var size: ControlSize = .small

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: { _ in toggle() }))
            .toggleStyle(.switch)
            .controlSize(size)
            .labelsHidden()
            .accessibilityLabel(isOn ? "Turn off" : "Turn on")
    }
}

/// A round colour picker: around the edge picks the colour, towards the middle makes it paler.
struct ColorWheel: View {
    let current: XY?
    let onPick: (XY) -> Void
    var diameter: CGFloat = 220

    @State private var dragPoint: CGPoint?
    private static let spectrum: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        ColorConversion.rgb(from: HSB(hue: $0, saturation: 1, brightness: 1)).color
    }

    var body: some View {
        let radius = diameter / 2
        ZStack {
            Circle().fill(AngularGradient(colors: Self.spectrum, center: .center))
            Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: radius))
            Circle().strokeBorder(.black.opacity(0.1), lineWidth: 1)
            if let p = dragPoint ?? point(for: current, radius: radius) {
                Circle()
                    .fill(color(at: p, radius: radius))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(radius: 2)
                    .position(p)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let p = clampToCircle(g.location, radius: radius)
                    dragPoint = p
                    onPick(xy(at: p, radius: radius))
                }
                .onEnded { _ in
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        dragPoint = nil
                    }
                })
        .accessibilityLabel("Colour")
    }

    private func hsb(at p: CGPoint, radius: CGFloat) -> HSB {
        let dx = p.x - radius, dy = p.y - radius
        var angle = atan2(dy, dx) / (2 * .pi)
        if angle < 0 { angle += 1 }
        return HSB(hue: angle, saturation: min(hypot(dx, dy) / radius, 1), brightness: 1)
    }

    private func color(at p: CGPoint, radius: CGFloat) -> Color {
        ColorConversion.rgb(from: hsb(at: p, radius: radius)).color
    }

    private func xy(at p: CGPoint, radius: CGFloat) -> XY {
        ColorConversion.xy(from: ColorConversion.rgb(from: hsb(at: p, radius: radius)))
    }

    private func point(for xy: XY?, radius: CGFloat) -> CGPoint? {
        guard let xy else { return nil }
        let hsb = ColorConversion.hsb(from: ColorConversion.rgb(from: xy))
        let angle = hsb.hue * 2 * .pi
        let r = hsb.saturation * radius
        return CGPoint(x: radius + cos(angle) * r, y: radius + sin(angle) * r)
    }

    private func clampToCircle(_ p: CGPoint, radius: CGFloat) -> CGPoint {
        let dx = p.x - radius, dy = p.y - radius
        let d = hypot(dx, dy)
        guard d > radius else { return p }
        return CGPoint(x: radius + dx / d * radius, y: radius + dy / d * radius)
    }
}

/// Warm white on the left, cool daylight on the right.
struct TemperatureSlider: View {
    let mirek: Int?
    let range: ClosedRange<Int>
    let onPick: (Int) -> Void

    @State private var dragMirek: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shown = dragMirek ?? mirek
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.1), lineWidth: 1))
                if let shown {
                    Circle()
                        .fill(ColorConversion.rgb(kelvin: ColorConversion.kelvin(fromMirek: shown)).color)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(radius: 2)
                        .offset(x: position(of: shown, width: width) - 13)
                }
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let m = mirek(at: g.location.x, width: width)
                        dragMirek = m
                        onPick(m)
                    }
                    .onEnded { _ in
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            dragMirek = nil
                        }
                    })
        }
        .frame(height: 26)
        .accessibilityLabel("White temperature")
    }

    private var stops: [Color] {
        stride(from: 0.0, through: 1.0, by: 0.2).map { t in
            let m = Double(range.upperBound) - t * Double(range.upperBound - range.lowerBound)
            return ColorConversion.rgb(kelvin: 1_000_000 / m).color
        }
    }

    private func position(of mirek: Int, width: CGFloat) -> CGFloat {
        let span = Double(max(range.upperBound - range.lowerBound, 1))
        let t = Double(range.upperBound - min(max(mirek, range.lowerBound), range.upperBound)) / span
        return 13 + t * (width - 26)
    }

    private func mirek(at x: CGFloat, width: CGFloat) -> Int {
        let t = min(max((x - 13) / max(width - 26, 1), 0), 1)
        return Int((Double(range.upperBound) - t * Double(range.upperBound - range.lowerBound)).rounded())
    }
}

/// Colour / White controls for a room or one light.
struct ColorControls: View {
    let canColor: Bool
    let canWhite: Bool
    let xy: XY?
    let mirek: Int?
    let mirekRange: ClosedRange<Int>
    let whiteModeNow: Bool
    let pickColor: (XY) -> Void
    let pickMirek: (Int) -> Void
    var wheelSize: CGFloat = 220
    /// Show the colour wheel first, whatever the lights show now (used to measure the tallest layout).
    var startInColor = false

    enum Mode: String, CaseIterable { case color = "Colour", white = "White" }
    @State private var mode: Mode?

    var body: some View {
        let current = mode ?? (canColor && (startInColor || !whiteModeNow) ? .color : (canWhite ? .white : .color))
        VStack(spacing: 14) {
            if canColor && canWhite {
                Picker("", selection: Binding(get: { current }, set: { mode = $0 })) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            if current == .color && canColor {
                ColorWheel(current: whiteModeNow ? nil : xy, onPick: pickColor, diameter: wheelSize)
            } else if canWhite {
                TemperatureSlider(mirek: whiteModeNow ? mirek : nil, range: mirekRange, onPick: pickMirek)
                    .frame(maxWidth: 320)
                HStack {
                    Text("Warm").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Daylight").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 320)
            }
        }
    }
}

/// The see-through grey background macOS uses for its own menus (like the Wi-Fi menu). It also makes the panel's
/// window itself see-through, otherwise the window paints a solid dark colour behind it.
struct NativeMenuBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = SeeThroughEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private final class SeeThroughEffectView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
    }
}

/// Lays out items left to right and wraps onto a new line when the row is full (used for scene buttons, so none
/// are cut off at the panel's edge).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
