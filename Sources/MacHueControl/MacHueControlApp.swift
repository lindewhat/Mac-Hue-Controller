import AppKit
import SwiftUI

@main
struct MacHueControlApp: App {
    @State private var store = HueStore()

    var body: some Scene {
        // The menu bar icon and its panel. Filled bulb: some light is on. Outline: all off. Triangle: a problem.
        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            Image(systemName: menuIcon)
                .accessibilityLabel("Mac Hue Control")
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
    }

    private var menuIcon: String {
        switch store.status {
        case .connected, .connecting, .notPaired:
            store.anyLightOn ? "lightbulb.fill" : "lightbulb"
        default:
            "exclamationmark.triangle.fill"
        }
    }
}
