import AppKit
import HueKit
import SwiftUI

/// The full window: rooms and zones on the left; on the right the chosen one's switch, brightness, colour or white,
/// scenes, and each single light.
struct MainWindow: View {
    @Environment(HueStore.self) private var store

    var body: some View {
        Group {
            if store.isPaired {
                ControlView()
            } else {
                SetupView()
            }
        }
        .onAppear {
            // The Dock icon shows only while this window is open; otherwise the app lives in the menu bar.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

private struct ControlView: View {
    @Environment(HueStore.self) private var store
    @State private var selection: String?

    // Sizing the window to fit: see `fitWindow()`.
    @State private var window: NSWindow?
    @State private var detailSize: CGSize = .zero
    @State private var contentHeights: [String: CGFloat] = [:]
    @State private var fitted = false
    /// The detail column's content is never wider than this (see GroupDetailContent).
    static let contentWidth: CGFloat = 760

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !store.rooms.isEmpty {
                    Section("Rooms") { ForEach(store.rooms) { SidebarRow(group: $0).tag($0.id) } }
                }
                if !store.zones.isEmpty {
                    Section("Zones") { ForEach(store.zones) { SidebarRow(group: $0).tag($0.id) } }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if store.status != .connected {
                    StatusPanel()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.yellow.opacity(0.12))
                    Divider()
                }
                if let message = store.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    Divider()
                }
                if let group = selectedGroup {
                    GroupDetailView(group: group)
                } else if store.status == .connected {
                    ContentUnavailableView("Pick a room or zone", systemImage: "lightbulb.2",
                                           description: Text("Rooms and zones come from the Hue app on your phone."))
                } else {
                    Spacer()
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { detailSize = $0; fitWindow() }
            .background(alignment: .topLeading) { measurer }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(WindowReader { window = $0; fitWindow() })
        .onAppear { if selection == nil { selection = store.rooms.first?.id ?? store.zones.first?.id } }
        .onChange(of: store.rooms) { _, rooms in
            if selection == nil || selectedGroup == nil { selection = rooms.first?.id ?? store.zones.first?.id }
        }
    }

    private var allGroups: [LightGroup] { store.rooms + store.zones }

    /// Every room and zone laid out out of sight, colour wheel showing, to find the tallest one.
    private var measurer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(allGroups) { group in
                GroupDetailContent(group: group, startInColor: true)
                    .frame(width: Self.contentWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeights[group.id] = height
                        fitWindow()
                    }
            }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// When the window opens, makes it exactly big enough to show the tallest room or zone (colour wheel showing)
    /// without scrolling, and wide enough for the content. Never taller than the screen. Done once per opening, so
    /// a size you choose yourself afterwards is left alone.
    private func fitWindow() {
        guard !fitted, let window, store.status == .connected, !allGroups.isEmpty,
              allGroups.allSatisfy({ contentHeights[$0.id] != nil }),
              detailSize.width > 0, detailSize.height > 0 else { return }
        fitted = true
        let tallest = contentHeights.values.max() ?? 0
        let chromeHeight = window.frame.height - detailSize.height  // title bar and toolbar
        let chromeWidth = window.frame.width - detailSize.width     // the sidebar
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let height = min(tallest + chromeHeight, visible.height)
        let width = min(Self.contentWidth + chromeWidth, visible.width)

        var frame = window.frame
        frame.origin.y = frame.maxY - height       // keep the top edge where it is
        frame.size = CGSize(width: width, height: height)
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxX > visible.maxX { frame.origin.x = max(visible.maxX - width, visible.minX) }
        window.setFrame(frame, display: true, animate: true)
    }

    private var selectedGroup: LightGroup? {
        guard let selection else { return nil }
        return store.rooms.first { $0.id == selection } ?? store.zones.first { $0.id == selection }
    }
}

private struct SidebarRow: View {
    @Environment(HueStore.self) private var store
    let group: LightGroup

    var body: some View {
        let firstOn = store.lights(in: group).first(where: \.on.on)
        Label {
            Text(group.name)
        } icon: {
            Image(systemName: firstOn != nil ? "lightbulb.fill" : "lightbulb")
                .foregroundStyle(firstOn?.displayColor ?? .secondary)
        }
    }
}

struct GroupDetailView: View {
    let group: LightGroup

    var body: some View {
        ScrollView {
            GroupDetailContent(group: group)
                .frame(maxWidth: ControlView.contentWidth)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Everything shown for one room or zone. Also used, out of sight, to measure how tall the window needs to be.
private struct GroupDetailContent: View {
    @Environment(HueStore.self) private var store
    let group: LightGroup
    var startInColor = false

    var body: some View {
        let lights = store.lights(in: group)
        let isOn = store.isOn(group)
        VStack(alignment: .leading, spacing: 24) {
            // Header: name and the whole-room switch.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.largeTitle.weight(.semibold))
                    Text("\(group.kind == .room ? "Room" : "Zone") · \(lights.count) light\(lights.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PowerSwitch(isOn: isOn, toggle: { store.toggle(group) }, size: .large)
            }

            if store.canDim(group) {
                HStack(spacing: 10) {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    BrightnessSlider(value: store.brightness(group),
                                     onChange: { store.setBrightness($0, for: group) }, onDim: isOn)
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                    Text("\(Int(store.brightness(group).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                }
            }

            if store.canColor(group) || store.canWhite(group) {
                let first = lights.first { $0.on.on && ($0.supportsColor || $0.supportsWhiteTemperature) }
                    ?? lights.first { $0.supportsColor || $0.supportsWhiteTemperature }
                ColorControls(canColor: store.canColor(group), canWhite: store.canWhite(group),
                              xy: first?.color?.xy, mirek: first?.colorTemperature?.mirek,
                              mirekRange: store.mirekRange(group),
                              whiteModeNow: first?.isInWhiteMode ?? false,
                              pickColor: { store.setColor($0, for: group) },
                              pickMirek: { store.setMirek($0, for: group) },
                              startInColor: startInColor)
                    .frame(maxWidth: .infinity)
                    .id(group.id) // a fresh Colour/White choice for each room
            }

            let scenes = store.scenes(in: group)
            if !scenes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scenes").font(.title3.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(scenes) { scene in
                            Button { store.recall(scene) } label: {
                                Text(scene.name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(SceneTileStyle(active: store.isActive(scene)))
                        }
                    }
                }
            }

            if !lights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lights").font(.title3.weight(.semibold))
                    VStack(spacing: 0) {
                        ForEach(Array(lights.enumerated()), id: \.element.id) { index, light in
                            if index > 0 { Divider() }
                            LightRow(light: light)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
                }
            }
        }
        .padding(24)
    }
}

/// Hands over the window a view lives in.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { found(w) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let w = view.window { found(w) } }
    }
}

private struct SceneTileStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

private struct LightRow: View {
    @Environment(HueStore.self) private var store
    let light: Light
    @State private var showColor = false

    var body: some View {
        HStack(spacing: 12) {
            Button { showColor = true } label: {
                Circle()
                    .fill(light.displayColor)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!light.supportsColor && !light.supportsWhiteTemperature)
            .help(light.supportsColor || light.supportsWhiteTemperature ? "Change colour" : "")
            .popover(isPresented: $showColor, arrowEdge: .bottom) {
                ColorControls(canColor: light.supportsColor, canWhite: light.supportsWhiteTemperature,
                              xy: light.color?.xy, mirek: light.colorTemperature?.mirek,
                              mirekRange: (light.colorTemperature?.mirekSchema ?? .standard).range,
                              whiteModeNow: light.isInWhiteMode,
                              pickColor: { store.setColor($0, for: light) },
                              pickMirek: { store.setMirek($0, for: light) },
                              wheelSize: 180)
                    .padding(16)
                    .frame(width: 260)
            }

            Text(light.name).lineLimit(1)
            Spacer()
            if light.supportsDimming {
                BrightnessSlider(value: light.dimming?.brightness ?? 0,
                                 onChange: { store.setBrightness($0, for: light) }, onDim: light.on.on)
                    .controlSize(.small)
                    .frame(width: 180)
            }
            PowerSwitch(isOn: light.on.on, toggle: { store.toggle(light) })
        }
        .padding(.vertical, 10)
    }
}

extension MirekSchema {
    var range: ClosedRange<Int> { mirekMinimum...max(mirekMaximum, mirekMinimum + 1) }
}
