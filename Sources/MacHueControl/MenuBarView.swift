import AppKit
import HueKit
import SwiftUI

/// The panel that opens from the menu bar icon: every room and zone with a switch and a brightness slider.
/// Each one opens up to show its scenes and single lights.
struct MenuBarView: View {
    @Environment(HueStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.status == .connected {
                content
            } else {
                StatusPanel(compact: true)
                    .padding(14)
            }
            if let message = store.message {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .frame(width: 340)
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
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if store.rooms.isEmpty && store.zones.isEmpty {
                    Text("No rooms or zones yet. Set them up in the Hue app on your phone.")
                        .font(.callout).foregroundStyle(.secondary).padding(14)
                }
                section("Rooms", store.rooms)
                section("Zones", store.zones)
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func section(_ title: String, _ groups: [LightGroup]) -> some View {
        if !groups.isEmpty {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 8)
            ForEach(groups) { group in
                MenuGroupRow(group: group, isExpanded: Binding(
                    get: { expanded.contains(group.id) },
                    set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } }))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Hue Control…") {
                openWindow(id: "main")
                NSApp.activate()
            }
            Spacer()
            Button {
                openSettings()
                NSApp.activate()
            } label: { Image(systemName: "gearshape") }
            .help("Settings")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct MenuGroupRow: View {
    @Environment(HueStore.self) private var store
    let group: LightGroup
    @Binding var isExpanded: Bool

    var body: some View {
        let isOn = store.isOn(group)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(isExpanded ? "Hide lights" : "Show lights")

                Text(group.name).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                PowerSwitch(isOn: isOn, toggle: { store.toggle(group) }, size: .mini)
            }
            if store.canDim(group) {
                BrightnessSlider(value: store.brightness(group),
                                 onChange: { store.setBrightness($0, for: group) }, onDim: isOn)
                    .controlSize(.small)
                    .padding(.leading, 22)
            }
            if isExpanded {
                expandedContent.padding(.leading, 22)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    @ViewBuilder
    private var expandedContent: some View {
        let scenes = store.scenes(in: group)
        if !scenes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(scenes) { scene in
                        Button(scene.name) { store.recall(scene) }
                            .buttonStyle(SceneChipStyle(active: scene.isActive))
                    }
                }
            }
        }
        ForEach(store.lights(in: group)) { light in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle().fill(light.displayColor).frame(width: 10, height: 10)
                    Text(light.name).font(.callout).lineLimit(1)
                    Spacer()
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
