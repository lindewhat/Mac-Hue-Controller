import HueKit
import SwiftUI

/// First-time setup: find the bridge, press its link button, done.
@MainActor @Observable
final class SetupModel {
    enum Step: Equatable {
        case searching
        case choose([DiscoveredBridge])
        case pressButton(DiscoveredBridge, secondsLeft: Int)
        case failed(String, retry: DiscoveredBridge?)
        case localNetworkDenied
    }

    var step: Step = .searching
    var manualAddress = ""
    var checkingAddress = false
    var addressProblem: String?
    private var work: Task<Void, Never>?

    func search() {
        work?.cancel()
        step = .searching
        work = Task {
            var result = await BridgeDiscovery().discover()
            // The very first search often runs while macOS is still asking "allow local network?", so it sees
            // nothing. Search once more by itself before saying no bridge was found.
            if result.bridges.isEmpty && !result.localNetworkDenied && !Task.isCancelled {
                result = await BridgeDiscovery().discover(maxWait: 8)
            }
            guard !Task.isCancelled else { return }
            Log.info("setup", "search found \(result.bridges.count) bridge(s)")
            if result.localNetworkDenied {
                Log.error("setup", "Local Network access is off; user sees the Local Network message")
                step = .localNetworkDenied
            } else if result.bridges.count == 1 {
                // Only one bridge: go straight to the link button.
                pair(result.bridges[0], store: nil)
            } else {
                step = .choose(result.bridges)
            }
        }
    }

    weak var store: HueStore?

    func pair(_ bridge: DiscoveredBridge, store: HueStore?) {
        if let store { self.store = store }
        work?.cancel()
        step = .pressButton(bridge, secondsLeft: 180)
        work = Task {
            do {
                let credentials = try await BridgePairing.pair(host: bridge.host) { left in
                    await MainActor.run {
                        if case .pressButton(let b, _) = self.step { self.step = .pressButton(b, secondsLeft: left) }
                    }
                }
                await self.store?.didPair(bridge, credentials: credentials)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                Log.error("setup", "pairing failed: \(Log.describe(error)); user sees: \(HueError.from(error).logKind)")
                step = .failed(HueError.from(error).localizedDescription, retry: bridge)
            }
        }
    }

    func useAddress(store: HueStore) {
        let address = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        checkingAddress = true
        addressProblem = nil
        Task {
            defer { checkingAddress = false }
            do {
                let bridge = try await BridgePairing.probe(host: address)
                pair(bridge, store: store)
            } catch {
                Log.warn("setup", "typed address: \(Log.describe(error)); user sees: \(HueError.from(error).logKind)")
                addressProblem = HueError.from(error).localizedDescription
            }
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}

struct SetupView: View {
    @Environment(HueStore.self) private var store
    @State private var model = SetupModel()

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lightbulb.2.fill")
                .font(.system(size: 46))
                .foregroundStyle(.yellow.gradient)
            Text("Connect to your Hue Bridge").font(.title.weight(.semibold))

            Group {
                switch model.step {
                case .searching:
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for your Hue Bridge on this network…").foregroundStyle(.secondary)
                    }
                case .choose(let bridges):
                    chooseView(bridges)
                case .pressButton(let bridge, let left):
                    VStack(spacing: 12) {
                        Image(systemName: "hand.point.down.fill").font(.system(size: 30)).foregroundStyle(.tint)
                        Text("Press the round link button on top of your bridge.")
                            .font(.title3)
                        Text("\(bridge.name) · waiting \(left) s").foregroundStyle(.secondary).monospacedDigit()
                        ProgressView(value: Double(left), total: 180).frame(width: 240)
                        Button("Cancel") { model.cancel(); model.search() }
                    }
                case .failed(let text, let retry):
                    VStack(spacing: 12) {
                        Text(text).multilineTextAlignment(.center)
                        HStack {
                            if let retry { Button("Try again") { model.pair(retry, store: store) }.keyboardShortcut(.defaultAction) }
                            Button("Search again") { model.search() }
                        }
                    }
                case .localNetworkDenied:
                    VStack(spacing: 12) {
                        Text(HueError.localNetworkDenied.localizedDescription).multilineTextAlignment(.center)
                        Text("Turn on Mac Hue Control under Privacy & Security ▸ Local Network, then search again.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        HStack {
                            Button("Open Local Network settings…") { openLocalNetworkSettings() }
                            Button("Search again") { model.search() }.keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .frame(maxWidth: 420)

            if !isPairing {
                Divider().frame(maxWidth: 360)
                addressField
            }
        }
        .padding(40)
        .frame(minWidth: 560, minHeight: 460)
        .onAppear {
            model.store = store
            model.search()
        }
        .onDisappear { model.cancel() }
    }

    private var isPairing: Bool {
        if case .pressButton = model.step { return true }
        return false
    }

    @ViewBuilder
    private func chooseView(_ bridges: [DiscoveredBridge]) -> some View {
        if bridges.isEmpty {
            VStack(spacing: 10) {
                Text("No Hue Bridge found.").font(.title3)
                Text("Is this Mac on the same Wi-Fi as your bridge, and is the bridge's power light on?")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Search again") { model.search() }.keyboardShortcut(.defaultAction)
            }
        } else {
            VStack(spacing: 8) {
                Text("Pick your bridge:").foregroundStyle(.secondary)
                ForEach(bridges) { bridge in
                    Button {
                        model.pair(bridge, store: store)
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.connected.to.line.below")
                            Text(bridge.name)
                            Spacer()
                            Text(bridge.host).foregroundStyle(.secondary)
                        }
                        .frame(width: 320)
                    }
                    .controlSize(.large)
                }
            }
        }
    }

    private var addressField: some View {
        VStack(spacing: 6) {
            Text("Or type your bridge's address (you'll find it in the Hue app under Settings ▸ Bridges):")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                TextField("For example 192.168.1.20", text: $model.manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { model.useAddress(store: store) }
                Button("Connect") { model.useAddress(store: store) }
                    .disabled(model.checkingAddress || model.manualAddress.isEmpty)
                if model.checkingAddress { ProgressView().controlSize(.small) }
            }
            if let problem = model.addressProblem {
                Text(problem).font(.callout).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: 420)
    }
}
