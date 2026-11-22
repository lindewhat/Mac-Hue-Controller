import AppKit
import HueKit
import Observation

/// One light's current state. Each light is its own observable object, so a change to one light only redraws the
/// rows that show it, not the whole panel (that kept sliders smooth while dragging).
@MainActor @Observable
final class LightState {
    var light: Light
    init(_ light: Light) { self.light = light }
}

/// Everything the menu and window show, kept in step with the bridge.
///
/// The bridge is the source of truth: clicks change what's shown at once (so the app feels instant), the change is
/// sent, and the bridge's live updates then confirm or correct it. If a change fails, everything is re-read.
///
/// The bridge reports changes a little behind what you do: during and just after a drag it still reports the
/// in-between values. So for a few seconds after you change a light, its reports are held back ("shielded") instead
/// of moving the switch or slider back; when the time is up the latest report is applied, so the app always ends up
/// showing the real state.
@MainActor @Observable
final class HueStore {
    enum Status: Equatable {
        case notPaired, connecting, connected, unreachable, localNetworkDenied, certificateChanged, notAuthorized
    }

    private(set) var status: Status = .notPaired
    private(set) var bridge: SavedBridge?
    private(set) var lightStates: [String: LightState] = [:]
    private(set) var scenes: [String: Scene] = [:]
    private(set) var rooms: [LightGroup] = []
    private(set) var zones: [LightGroup] = []
    /// The last problem with a change, in plain language. Cleared by the next change.
    var message: String?

    @ObservationIgnored private var client: HueClient?
    @ObservationIgnored private var outbox: AsyncStream<(Target, Command)>.Continuation?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?
    @ObservationIgnored private var refreshSoonTask: Task<Void, Never>?
    @ObservationIgnored private var lastRelocate: ContinuousClock.Instant?
    @ObservationIgnored private var pendingKey: String?

    // Shields: lights changed here recently, and the bridge's latest word on them, held back until the shield ends.
    @ObservationIgnored private var shieldUntil: [String: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var heldTruth: [String: Light] = [:]
    @ObservationIgnored private var shieldTasks: [String: Task<Void, Never>] = [:]
    private static let shieldTime: Duration = .seconds(3)

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

    /// Forgets the bridge (for "Set up again").
    func forget() {
        disconnect()
        if let bridge { Keychain.delete(account: bridge.id) }
        UserDefaults.standard.removeObject(forKey: Self.bridgeKey)
        bridge = nil
        pendingKey = nil
        lightStates = [:]; scenes = [:]; rooms = []; zones = []
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
        shieldTasks.values.forEach { $0.cancel() }
        shieldTasks = [:]; shieldUntil = [:]; heldTruth = [:]
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
        var states = lightStates
        var changedSet = false
        let incoming = Set(s.lights.map(\.id))
        for light in s.lights {
            if let state = states[light.id] {
                receive(light, into: state)
            } else {
                states[light.id] = LightState(light)
                changedSet = true
            }
        }
        for id in states.keys where !incoming.contains(id) {
            states[id] = nil
            changedSet = true
        }
        if changedSet { lightStates = states }

        let newScenes = Dictionary(s.scenes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if newScenes != scenes { scenes = newScenes }
        let (r, z) = Topology.build(s)
        if r != rooms { rooms = r }
        if z != zones { zones = z }
    }

    /// The bridge's word on a light: shown at once, unless the light was changed here moments ago.
    private func receive(_ light: Light, into state: LightState) {
        if let until = shieldUntil[light.id], until > .now {
            heldTruth[light.id] = light
        } else if state.light != light {
            state.light = light
        }
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
                    guard let state = lightStates[update.id] else { needsRefresh = true; continue }
                    if update.metadata != nil { needsRefresh = true } // renamed: its place in the list may change
                    // Updates only list what changed, so build on the newest known bridge state.
                    let base = heldTruth[update.id] ?? state.light
                    receive(update.applied(to: base), into: state)
                case "scene":
                    if var scene = scenes[update.id] {
                        if let status = update.status { scene.status = status }
                        if let metadata = update.metadata { scene.metadata.name = metadata.name; needsRefresh = true }
                        if scenes[update.id] != scene { scenes[update.id] = scene }
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
        // Put back what's really true: drop the shields so the fresh read shows at once.
        for id in Array(shieldUntil.keys) { endShield(id) }
        await refresh()
    }

    // MARK: - Shields

    private func shield(_ id: String) {
        shieldUntil[id] = .now + Self.shieldTime
        guard shieldTasks[id] == nil else { return }
        shieldTasks[id] = Task { [weak self] in
            while let until = self?.shieldUntil[id], until > .now {
                try? await Task.sleep(for: until - .now)
                if Task.isCancelled { return }
            }
            self?.endShield(id)
        }
    }

    private func endShield(_ id: String) {
        shieldTasks[id]?.cancel()
        shieldTasks[id] = nil
        shieldUntil[id] = nil
        if let truth = heldTruth.removeValue(forKey: id), let state = lightStates[id], state.light != truth {
            state.light = truth
        }
    }

    // MARK: - What the views ask

    func light(_ id: String) -> Light? { lightStates[id]?.light }
    func lights(in group: LightGroup) -> [Light] { group.lightIDs.compactMap { lightStates[$0]?.light } }
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

    var anyLightOn: Bool { lightStates.values.contains { $0.light.on.on } }

    /// The white range the room's lights share (for the temperature slider).
    func mirekRange(_ group: LightGroup) -> ClosedRange<Int> {
        let schemas = lights(in: group).compactMap(\.colorTemperature?.mirekSchema)
        guard !schemas.isEmpty else { return 153...500 }
        return (schemas.map(\.mirekMinimum).min() ?? 153)...(schemas.map(\.mirekMaximum).max() ?? 500)
    }

    // MARK: - Changing a room or zone

    func toggle(_ group: LightGroup) {
        // Decide from what's really on, never from the switch's own state (a lesson from the Sonos app).
        let on = !isOn(group)
        for light in lights(in: group) { change(light.id) { $0.on.on = on } }
        sendWhole(Command(on: on), to: group)
    }

    func setBrightness(_ value: Double, for group: LightGroup) {
        let v = min(max(value.rounded(), 1), 100)
        adjust(group, supports: \.supportsDimming,
               change: { $0.dimming?.brightness = v },
               command: { _ in Command(brightness: v) })
    }

    func setColor(_ xy: XY, for group: LightGroup) {
        adjust(group, supports: \.supportsColor,
               change: { l in
                   let gamut = l.color?.gamut ?? .c
                   l.color?.xy = ColorConversion.clamp(xy, to: gamut)
                   l.colorTemperature?.mirek = nil
                   l.colorTemperature?.mirekValid = false
               },
               command: { l in Command(xy: ColorConversion.clamp(xy, to: l.color?.gamut ?? .c)) })
    }

    func setMirek(_ mirek: Int, for group: LightGroup) {
        func fitted(_ l: Light) -> Int {
            let s = l.colorTemperature?.mirekSchema ?? .standard
            return min(max(mirek, s.mirekMinimum), s.mirekMaximum)
        }
        adjust(group, supports: \.supportsWhiteTemperature,
               change: { l in
                   let m = fitted(l)
                   l.colorTemperature?.mirek = m
                   l.colorTemperature?.mirekValid = true
               },
               command: { l in Command(mirek: fitted(l)) })
    }

    /// Brightness, colour or white for a room. Never switches anything on or off: only the on/off switches do that.
    /// - room on: only the lights that are on change; lights that are off stay off and keep their setting.
    /// - room completely off: every light's setting changes, but they all stay off (it shows when they're turned on).
    /// Lights get the change one by one (sharing the bridge's speed limit). Only when a big room is entirely on
    /// does it go as one whole-room command, which the bridge handles better for many lights.
    private func adjust(_ group: LightGroup, supports: (Light) -> Bool,
                        change: (inout Light) -> Void, command: (Light) -> Command) {
        let all = lights(in: group)
        let capable = all.filter(supports)
        guard !capable.isEmpty else { return }
        let lit = capable.filter(\.on.on)
        let targets = lit.isEmpty ? capable : lit

        for l in targets { self.change(l.id) { change(&$0) } }
        let everythingOn = all.allSatisfy(\.on.on) && lit.count == capable.count
        if everythingOn && lit.count > 4, group.groupedLightID != nil {
            sendWhole(command(lit[0]), to: group)
        } else {
            for l in targets { enqueue(command(l), Target(.light, l.id)) }
        }
    }

    // MARK: - Changing one light

    func toggle(_ light: Light) {
        let on = !(self.light(light.id)?.on.on ?? light.on.on)
        change(light.id) { $0.on.on = on }
        enqueue(Command(on: on), Target(.light, light.id))
    }

    /// Brightness, colour and white never switch a light on or off; a light that's off keeps the new setting
    /// for when it's turned on.
    func setBrightness(_ value: Double, for light: Light) {
        let v = min(max(value.rounded(), 1), 100)
        change(light.id) { $0.dimming?.brightness = v }
        enqueue(Command(brightness: v), Target(.light, light.id))
    }

    func setColor(_ xy: XY, for light: Light) {
        let clamped = ColorConversion.clamp(xy, to: light.color?.gamut ?? .c)
        change(light.id) { l in
            l.color?.xy = clamped
            l.colorTemperature?.mirek = nil
            l.colorTemperature?.mirekValid = false
        }
        enqueue(Command(xy: clamped), Target(.light, light.id))
    }

    func setMirek(_ mirek: Int, for light: Light) {
        let schema = light.colorTemperature?.mirekSchema ?? .standard
        let m = min(max(mirek, schema.mirekMinimum), schema.mirekMaximum)
        change(light.id) { l in
            l.colorTemperature?.mirek = m
            l.colorTemperature?.mirekValid = true
        }
        enqueue(Command(mirek: m), Target(.light, light.id))
    }

    /// Puts a scene's settings on the lights that are on; lights that are off stay off (see SceneApply).
    func recall(_ scene: Scene) {
        var current: [String: Light] = [:]
        for (id, state) in lightStates { current[id] = state.light }
        let changes = SceneApply.changes(for: scene, lights: current)
        for change in changes {
            self.change(change.lightID, keepScene: true) { $0 = SceneApply.preview($0, after: change.command) }
            enqueue(change.command, Target(.light, change.lightID))
        }
        chosenScene[scene.group.rid] = scene.id
    }

    /// The scene last chosen here for each room/zone. The bridge doesn't mark a scene as active when its settings
    /// are sent light by light, so the app remembers it until a light in that room is changed some other way.
    private(set) var chosenScene: [String: String] = [:]

    func isActive(_ scene: Scene) -> Bool {
        if let chosen = chosenScene[scene.group.rid] { return chosen == scene.id }
        return scene.isActive
    }

    // MARK: - Plumbing

    /// Changes what's shown for a light right away and shields it from the bridge's late reports.
    private func change(_ id: String, keepScene: Bool = false, _ edit: (inout Light) -> Void) {
        guard let state = lightStates[id] else { return }
        if !keepScene { forgetChosenScene(containing: id) }
        var l = state.light
        edit(&l)
        shield(id)
        if l != state.light { state.light = l }
    }

    private func forgetChosenScene(containing lightID: String) {
        guard !chosenScene.isEmpty else { return }
        for group in rooms + zones where chosenScene[group.id] != nil && group.lightIDs.contains(lightID) {
            chosenScene[group.id] = nil
        }
    }

    private func sendWhole(_ command: Command, to group: LightGroup) {
        if let grouped = group.groupedLightID {
            enqueue(command, Target(.groupedLight, grouped))
        } else {
            for id in group.lightIDs { enqueue(command, Target(.light, id)) }
        }
    }

    private func enqueue(_ command: Command, _ target: Target) {
        if message != nil { message = nil }
        outbox?.yield((target, command))
    }
}
