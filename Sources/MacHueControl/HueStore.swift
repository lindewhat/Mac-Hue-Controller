import AppKit
import HueKit
import Observation

/// Everything the menu and window show, kept in step with the bridge.
///
/// The bridge is the source of truth: clicks change what's shown at once (so the app feels instant), the change is
/// sent, and the bridge's live updates then confirm or correct it. If a change fails, everything is re-read.
@MainActor @Observable
final class HueStore {
    enum Status: Equatable {
        case notPaired, connecting, connected, unreachable, localNetworkDenied, certificateChanged, notAuthorized
    }

    private(set) var status: Status = .notPaired
    private(set) var bridge: SavedBridge?
    private(set) var lights: [String: Light] = [:]
    private(set) var scenes: [String: Scene] = [:]
    private(set) var rooms: [LightGroup] = []
    private(set) var zones: [LightGroup] = []
    /// The last problem with a change, in plain language. Cleared by the next successful read.
    var message: String?

    private var client: HueClient?
    private var outbox: AsyncStream<(Target, Command)>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var generation = 0
    private var lastRefresh: ContinuousClock.Instant?
    private var refreshSoonTask: Task<Void, Never>?
    private var lastRelocate: ContinuousClock.Instant?

    private static let bridgeKey = "savedBridge"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.bridgeKey),
           let saved = try? JSONDecoder().decode(SavedBridge.self, from: data),
           Keychain.load(account: saved.id) != nil {
            bridge = saved
            connect()
        }
    }

    var isPaired: Bool { bridge != nil }

    // MARK: - Connecting

    /// Called by the setup window once the link button was pressed.
    func didPair(_ found: DiscoveredBridge, credentials: PairedCredentials) async {
        var name = found.name
        if let probed = try? await BridgePairing.probe(host: found.host) { name = probed.name }
        if !Keychain.save(credentials.appKey, account: found.id) {
            message = "Couldn't save the bridge's key in the Keychain. You may need to set it up again after a restart."
        }
        pendingKey = credentials.appKey
        save(SavedBridge(id: found.id, name: name, host: found.host, certificateHash: credentials.certificateHash))
        connect()
    }

    /// Keeps the key in memory if the Keychain refused it, so the app still works until it quits.
    private var pendingKey: String?

    /// Forgets the bridge (for "Set up again").
    func forget() {
        disconnect()
        if let bridge { Keychain.delete(account: bridge.id) }
        UserDefaults.standard.removeObject(forKey: Self.bridgeKey)
        bridge = nil
        pendingKey = nil
        lights = [:]; scenes = [:]; rooms = []; zones = []
        message = nil
        status = .notPaired
    }

    func retry() {
        connect()
    }

    private func save(_ saved: SavedBridge) {
        bridge = saved
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: Self.bridgeKey) }
    }

    private func connect() {
        disconnect()
        guard let bridge, let key = Keychain.load(account: bridge.id) ?? pendingKey else {
            status = .notPaired
            return
        }
        generation += 1
        let gen = generation
        status = .connecting
        let client = HueClient(host: bridge.host, appKey: key, certificateHash: bridge.certificateHash)
        self.client = client

        // Changes go through one ordered pipe into the command queue, so clicks reach the bridge in the order made.
        let queue = CommandQueue(
            send: { target, command in try await client.send(command, to: target) },
            onError: { [weak self] _, error in await self?.commandFailed(error, generation: gen) })
        let (stream, continuation) = AsyncStream<(Target, Command)>.makeStream()
        outbox = continuation
        tasks.append(Task {
            for await (target, command) in stream { await queue.enqueue(command, for: target) }
        })

        tasks.append(Task { [weak self] in
            await self?.refresh()
            await self?.listen(client, generation: gen)
        })
    }

    private func disconnect() {
        generation += 1
        tasks.forEach { $0.cancel() }
        tasks = []
        outbox?.finish()
        outbox = nil
        client?.close()
        client = nil
        refreshSoonTask?.cancel()
    }

    /// Keeps the live update stream open, reconnecting with growing pauses if it drops.
    private func listen(_ client: HueClient, generation gen: Int) async {
        var pause: Duration = .seconds(1)
        while !Task.isCancelled && gen == generation {
            do {
                try await client.listen(
                    onConnected: { [weak self] in await self?.refresh() },
                    onEvents: { [weak self] events in await self?.apply(events, generation: gen) })
            } catch {
                guard gen == generation else { return }
                let hue = HueError.from(error)
                if hue == .certificateChanged || hue == .notAuthorized {
                    fail(with: hue)
                    return
                }
            }
            guard gen == generation, !Task.isCancelled else { return }
            if status == .connected { pause = .seconds(1) } // it had been working: retry quickly
            try? await Task.sleep(for: pause)
            pause = min(pause * 2, .seconds(30))
            await refresh()
        }
    }

    // MARK: - Reading

    /// Re-reads everything from the bridge.
    func refresh() async {
        guard let client else { return }
        let gen = generation
        do {
            let snapshot = try await client.snapshot()
            guard gen == generation else { return }
            apply(snapshot)
            status = .connected
            lastRefresh = .now
            if bridge?.certificateHash == nil, var b = bridge, let seen = client.seenCertificateHash {
                b.certificateHash = seen
                save(b)
            }
        } catch {
            guard gen == generation else { return }
            fail(with: HueError.from(error))
        }
    }

    /// Called when the menu opens: re-reads if it's been a while, so the menu never shows something old.
    func refreshIfStale() {
        guard isPaired else { return }
        if status == .unreachable || status == .localNetworkDenied { connect(); return }
        if let last = lastRefresh, ContinuousClock.now - last < .seconds(5) { return }
        Task { await refresh() }
    }

    private func refreshSoon() {
        refreshSoonTask?.cancel()
        refreshSoonTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func apply(_ s: Snapshot) {
        lights = Dictionary(s.lights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        scenes = Dictionary(s.scenes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let (r, z) = Topology.build(s)
        if r != rooms { rooms = r }
        if z != zones { zones = z }
    }

    private func apply(_ events: [HueEvent], generation gen: Int) {
        guard gen == generation else { return }
        var needsRefresh = false
        for event in events {
            guard event.type == "update" else {
                // Something was added or removed (a new light, a deleted scene...): re-read.
                needsRefresh = true
                continue
            }
            for update in event.data {
                switch update.type {
                case "light":
                    if let light = lights[update.id] { lights[update.id] = update.applied(to: light) }
                    else { needsRefresh = true }
                case "scene":
                    if var scene = scenes[update.id] {
                        if let status = update.status { scene.status = status }
                        if let metadata = update.metadata { scene.metadata.name = metadata.name; needsRefresh = true }
                        scenes[update.id] = scene
                    }
                case "room", "zone", "device":
                    needsRefresh = true // renamed, or lights moved between rooms
                default:
                    break
                }
            }
        }
        if needsRefresh { refreshSoon() }
    }

    private func fail(with error: HueError) {
        switch error {
        case .certificateChanged: status = .certificateChanged
        case .notAuthorized: status = .notAuthorized
        default:
            status = .unreachable
            Task { await relocate() }
        }
    }

    /// If the bridge got a new address from the router, find it again by its id and reconnect.
    private func relocate() async {
        guard let bridge else { return }
        if let last = lastRelocate, ContinuousClock.now - last < .seconds(30) { return }
        lastRelocate = .now
        let result = await BridgeDiscovery().discover()
        guard self.bridge?.id == bridge.id, status != .connected else { return }
        if result.localNetworkDenied {
            status = .localNetworkDenied
        } else if let found = result.bridges.first(where: { $0.id == bridge.id }), found.host != bridge.host {
            var moved = bridge
            moved.host = found.host
            save(moved)
            connect()
        }
    }

    private func commandFailed(_ error: Error, generation gen: Int) async {
        guard gen == generation else { return }
        let hue = HueError.from(error)
        if hue == .certificateChanged || hue == .notAuthorized || hue == .unreachable {
            fail(with: hue)
        } else {
            message = hue.localizedDescription
        }
        await refresh() // put back what's really true
    }

    // MARK: - What the views ask

    func lights(in group: LightGroup) -> [Light] { group.lightIDs.compactMap { lights[$0] } }
    func scenes(in group: LightGroup) -> [Scene] { group.sceneIDs.compactMap { scenes[$0] } }

    /// A room counts as on when any of its lights is on (no half-on state, so a click always does the obvious thing).
    func isOn(_ group: LightGroup) -> Bool { lights(in: group).contains { $0.on.on } }

    /// The average brightness of the lights that are on (or of all of them when the room is off).
    func brightness(_ group: LightGroup) -> Double {
        let all = lights(in: group).filter(\.supportsDimming)
        let on = all.filter(\.on.on)
        let pool = on.isEmpty ? all : on
        guard !pool.isEmpty else { return 0 }
        return pool.compactMap(\.dimming?.brightness).reduce(0, +) / Double(pool.count)
    }

    func canDim(_ group: LightGroup) -> Bool { lights(in: group).contains(where: \.supportsDimming) }
    func canColor(_ group: LightGroup) -> Bool { lights(in: group).contains(where: \.supportsColor) }
    func canWhite(_ group: LightGroup) -> Bool { lights(in: group).contains(where: \.supportsWhiteTemperature) }

    var anyLightOn: Bool { lights.values.contains { $0.on.on } }

    /// The white range the room's lights share (for the temperature slider).
    func mirekRange(_ group: LightGroup) -> ClosedRange<Int> {
        let schemas = lights(in: group).compactMap(\.colorTemperature?.mirekSchema)
        guard !schemas.isEmpty else { return 153...500 }
        return (schemas.map(\.mirekMinimum).min() ?? 153)...(schemas.map(\.mirekMaximum).max() ?? 500)
    }

    // MARK: - Changing things

    func toggle(_ group: LightGroup) {
        // Decide from what's really on, never from the switch's own state (a lesson from the Sonos app).
        let on = !isOn(group)
        update(group) { $0.on.on = on }
        send(Command(on: on), to: group)
    }

    func setBrightness(_ value: Double, for group: LightGroup) {
        let v = min(max(value, 1), 100)
        update(group) { l in
            guard l.supportsDimming else { return }
            l.on.on = true
            l.dimming?.brightness = v
        }
        send(Command(on: true, brightness: v), to: group)
    }

    func setColor(_ xy: XY, for group: LightGroup) {
        update(group) { l in
            guard let color = l.color else { return }
            l.on.on = true
            l.color?.xy = ColorConversion.clamp(xy, to: color.gamut ?? .c)
            l.colorTemperature?.mirek = nil
            l.colorTemperature?.mirekValid = false
        }
        send(Command(on: true, xy: xy), to: group)
    }

    func setMirek(_ mirek: Int, for group: LightGroup) {
        update(group) { l in
            guard let schema = l.colorTemperature?.mirekSchema ?? (l.colorTemperature != nil ? .standard : nil) else { return }
            l.on.on = true
            l.colorTemperature?.mirek = min(max(mirek, schema.mirekMinimum), schema.mirekMaximum)
            l.colorTemperature?.mirekValid = true
        }
        send(Command(on: true, mirek: mirek), to: group)
    }

    func toggle(_ light: Light) {
        let on = !(lights[light.id]?.on.on ?? light.on.on)
        lights[light.id]?.on.on = on
        enqueue(Command(on: on), Target(.light, light.id))
    }

    func setBrightness(_ value: Double, for light: Light) {
        let v = min(max(value, 1), 100)
        lights[light.id]?.on.on = true
        lights[light.id]?.dimming?.brightness = v
        enqueue(Command(on: true, brightness: v), Target(.light, light.id))
    }

    func setColor(_ xy: XY, for light: Light) {
        let clamped = ColorConversion.clamp(xy, to: light.color?.gamut ?? .c)
        lights[light.id]?.on.on = true
        lights[light.id]?.color?.xy = clamped
        lights[light.id]?.colorTemperature?.mirek = nil
        lights[light.id]?.colorTemperature?.mirekValid = false
        enqueue(Command(on: true, xy: clamped), Target(.light, light.id))
    }

    func setMirek(_ mirek: Int, for light: Light) {
        let schema = light.colorTemperature?.mirekSchema ?? .standard
        let m = min(max(mirek, schema.mirekMinimum), schema.mirekMaximum)
        lights[light.id]?.on.on = true
        lights[light.id]?.colorTemperature?.mirek = m
        lights[light.id]?.colorTemperature?.mirekValid = true
        enqueue(Command(on: true, mirek: m), Target(.light, light.id))
    }

    func recall(_ scene: Scene) {
        enqueue(Command(recallScene: true), Target(.scene, scene.id))
    }

    private func update(_ group: LightGroup, _ change: (inout Light) -> Void) {
        for id in group.lightIDs {
            guard var light = lights[id] else { continue }
            change(&light)
            lights[id] = light
        }
    }

    private func send(_ command: Command, to group: LightGroup) {
        if let grouped = group.groupedLightID {
            enqueue(command, Target(.groupedLight, grouped))
        } else {
            for id in group.lightIDs { enqueue(command, Target(.light, id)) }
        }
    }

    private func enqueue(_ command: Command, _ target: Target) {
        message = nil
        outbox?.yield((target, command))
    }
}
