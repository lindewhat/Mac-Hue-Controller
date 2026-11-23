import AppKit
import HueKit
import SwiftUI

extension Notification.Name {
    static let openMainWindow = Notification.Name("MacHueControl.openMainWindow")
}

/// Opening the app again (from Finder, Spotlight or Launchpad) while it already runs in the menu bar shows the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { NotificationCenter.default.post(name: .openMainWindow, object: nil) }
        return true
    }
}

@main
struct MacHueControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: HueStore

    init() {
        // The log starts before anything connects, so the first problem is already recorded.
        // `--verbose` adds a line for every request (for chasing a rare fault).
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        Log.start(verbose: CommandLine.arguments.contains("--verbose"),
                  startLine: "Mac Hue Control \(version) started on macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        _store = State(initialValue: HueStore())
    }

    var body: some SwiftUI.Scene {
        // The menu bar icon and its panel. Filled bulb: some light is on. Outline: all off. Triangle: a problem.
        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            MenuBarIcon(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("Mac Hue Control", id: "main") {
            MainWindow().environment(store)
        }
        .defaultSize(width: 900, height: 640)
        // The first time (nothing set up yet) the window opens by itself to walk through setup.
        .defaultLaunchBehavior(store.isPaired ? .suppressed : .presented)

        Settings {
            SettingsView().environment(store)
        }

        // For checking the panel's look during development: `open -a "Mac Hue Control" --args --panel-preview`
        // shows the menu bar panel in an ordinary window. Never shown otherwise.
        Window("Panel preview", id: "panel-preview") {
            MenuBarView().environment(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Self.panelPreview ? .presented : .suppressed)
        .commandsRemoved()
    }

    private static let panelPreview = CommandLine.arguments.contains("--panel-preview")
}

/// The menu bar icon. It is always on screen, so it is also what opens the window when the app is opened again.
private struct MenuBarIcon: View {
    let store: HueStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: name)
            .accessibilityLabel("Mac Hue Control")
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate()
            }
    }

    private var name: String {
        switch store.status {
        case .connected, .connecting, .notPaired:
            store.anyLightOn ? "lightbulb.fill" : "lightbulb"
        default:
            "exclamationmark.triangle.fill"
        }
    }
}
