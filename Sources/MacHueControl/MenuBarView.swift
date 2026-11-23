import AppKit
import HueKit
import SwiftUI

/// The panel that opens from the menu bar icon: every room and zone as a card with a switch and a brightness
/// slider. Each card opens up to show its scenes and single lights.
struct MenuBarView: View {
    @Environment(HueStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var expanded: Set<String> = []
    @State private var contentHeight: CGFloat = 300

    /// Leave room for the menu bar, the panel's header and footer, and a margin at the bottom of the screen.
    private var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return max(screen - 220, 240)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.status == .connected {
                content
            } else {
                MenuSeparator()
                StatusPanel(compact: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
            if let message = store.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            MenuSeparator()
            footer
        }
        .frame(width: 320)
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack {
            Text(store.bridge?.name ?? "Hue").font(.headline)
            Spacer()
            if store.status == .connected {
                Circle().fill(.green).frame(width: 7, height: 7).accessibilityLabel("Connected")
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.rooms.isEmpty && store.zones.isEmpty {
                    MenuSeparator()
                    Text("No rooms or zones yet. Set them up in the Hue app on your phone.")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
                section("Rooms", store.rooms)
                section("Zones", store.zones)
            }
            .padding(.bottom, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.automatic)
        // The panel grows with its content (opening a room makes it taller) up to what fits on the screen;
        // beyond that the list scrolls.
        .frame(height: min(max(contentHeight, 1), maxListHeight))
    }

    @ViewBuilder
    private func section(_ title: String, _ groups: [LightGroup]) -> some View {
        if !groups.isEmpty {
            MenuSeparator()
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 4)
            ForEach(groups) { group in
                MenuGroupRow(group: group, isExpanded: Binding(
                    get: { expanded.contains(group.id) },
                    set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuItemButton(title: "Open Hue Control…") {
                openWindow(id: "main")
                NSApp.activate()
            }
            MenuItemButton(title: "Settings…") {
                openSettings()
                NSApp.activate()
            }
            MenuItemButton(title: "Quit Mac Hue Control") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 5).padding(.vertical, 5)
    }
}

/// One room or zone: name, arrow, switch and brightness, laid out like a row in a native menu.
private struct MenuGroupRow: View {
    @Environment(HueStore.self) private var store
    let group: LightGroup
    @Binding var isExpanded: Bool

    /// Everything inside the card lines up on this inset (right after the arrow).
    private let inset: CGFloat = 22

    var body: some View {
        let isOn = store.isOn(group)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 14)
                        Text(group.name).font(.body.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide \(group.name)'s lights" : "Show \(group.name)'s lights")
                PowerSwitch(isOn: isOn, toggle: { store.toggle(group) }, size: .mini)
            }
            if store.canDim(group) {
                BrightnessSlider(value: store.brightness(group),
                                 onChange: { store.setBrightness($0, for: group) }, onDim: isOn)
                    .controlSize(.small)
                    .padding(.leading, inset)
            }
            if isExpanded {
                expandedContent
                    .padding(.leading, inset)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    @ViewBuilder
    private var expandedContent: some View {
        let scenes = store.scenes(in: group)
        VStack(alignment: .leading, spacing: 8) {
            if !scenes.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(scenes) { scene in
                        Button(scene.name) { store.recall(scene) }
                            .buttonStyle(SceneChipStyle(active: store.isActive(scene)))
                    }
                }
            }
            ForEach(group.lightIDs, id: \.self) { id in
                if let state = store.lightStates[id] {
                    MenuLightRow(state: state)
                }
            }
        }
    }
}

/// One light inside an opened card. It watches only its own light, so dragging another slider doesn't redraw it.
private struct MenuLightRow: View {
    @Environment(HueStore.self) private var store
    let state: LightState

    var body: some View {
        let light = state.light
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle().fill(light.displayColor).frame(width: 10, height: 10)
                Text(light.name).font(.callout).lineLimit(1)
                Spacer(minLength: 8)
                PowerSwitch(isOn: light.on.on, toggle: { store.toggle(light) }, size: .mini)
            }
            if light.supportsDimming {
                BrightnessSlider(value: light.dimming?.brightness ?? 0,
                                 onChange: { store.setBrightness($0, for: light) }, onDim: light.on.on)
                    .controlSize(.mini)
                    .padding(.leading, 18)
            }
        }
    }
}

struct SceneChipStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
            .overlay(Capsule().strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}

/// What to say (and offer) when the app isn't connected. Used in the menu and the window.
struct StatusPanel: View {
    @Environment(HueStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.status {
            case .notPaired:
                Text("Set up your Hue Bridge to get started.")
                Button("Set up…") { openMain() }
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to your Hue Bridge…")
                }
            case .unreachable:
                Text(HueError.unreachable.localizedDescription)
                Button("Try again") { store.retry() }
            case .localNetworkDenied:
                Text(HueError.localNetworkDenied.localizedDescription)
                Text("Turn on Mac Hue Control under Privacy & Security ▸ Local Network.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Open Local Network settings…") { openLocalNetworkSettings() }
                    Button("Try again") { store.retry() }
                }
            case .certificateChanged:
                Text(HueError.certificateChanged.localizedDescription)
                Button("Set up again…") { store.forget(); openMain() }
            case .notAuthorized:
                Text(HueError.notAuthorized.localizedDescription)
                Button("Set up again…") { store.forget(); openMain() }
            case .connected:
                EmptyView()
            }
        }
        .font(compact ? .callout : .body)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}

func openLocalNetworkSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
        NSWorkspace.shared.open(url)
    }
}

/// A thin line between sections, inset like the ones in the system's own menus.
struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }
}

/// A plain clickable row that highlights on hover, like "Wi-Fi Settings…" in the system menu.
struct MenuItemButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.1) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
