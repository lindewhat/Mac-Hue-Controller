import AppKit
import HueKit
import ServiceManagement
import SwiftUI

/// "Open when I log in", using Apple's built-in login item support (same as Mac Sonos Control).
enum LaunchAtLogin {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// True when macOS wants the user to approve the login item in System Settings.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct SettingsView: View {
    @Environment(HueStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LaunchAtLogin.isOn
    @State private var loginNote: String?

    var body: some View {
        Form {
            Section("Hue Bridge") {
                if let bridge = store.bridge {
                    LabeledContent("Name", value: bridge.name)
                    LabeledContent("Address", value: bridge.host)
                    LabeledContent("Status", value: statusText)
                    Button("Set up the bridge again…") {
                        store.forget()
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                } else {
                    Text("No bridge set up yet.")
                    Button("Set up…") {
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                }
            }
            Section {
                Toggle("Open Mac Hue Control when I log in", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if let loginNote {
                    Text(loginNote).font(.callout).foregroundStyle(.secondary)
                    if LaunchAtLogin.needsApproval {
                        Button("Open Login Items…") { LaunchAtLogin.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private var statusText: String {
        switch store.status {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .unreachable: "Can't reach the bridge"
        case .localNetworkDenied: "Local Network access is off"
        case .certificateChanged: "Needs setting up again"
        case .notAuthorized: "Needs setting up again"
        case .notPaired: "Not set up"
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginNote = LaunchAtLogin.needsApproval
                ? "Approve Mac Hue Control under Login Items in System Settings." : nil
        } catch {
            Log.error("settings", "Open when I log in could not be changed: \(Log.describe(error)); user sees a note")
            loginNote = "Couldn't change this setting. It only works when the app is in your Applications folder."
        }
        launchAtLogin = LaunchAtLogin.isOn
    }
}
