import Foundation

/// Sends commands to the bridge without flooding it and without ever losing a click.
///
/// Each light, room or scene has its own lane. A lane sends the first command at once. Commands that arrive while it
/// waits are merged (the newest value wins, nothing asked for is dropped), and the merged command goes out once the
/// lane's minimum gap has passed. A slider dragged across 50 values sends maybe 5 commands, and always the final one.
/// The bridge takes about 10 light commands a second and about 1 room/zone command a second.
public actor CommandQueue {
    public typealias Sender = @Sendable (Target, Command) async throws -> Void
    public typealias ErrorHandler = @Sendable (Target, Error) async -> Void

    private struct Lane {
        var pending: Command?
        var nextAllowed: ContinuousClock.Instant = .now
        var worker: Task<Void, Never>?
    }

    private let send: Sender
    private let onError: ErrorHandler
    private let gap: @Sendable (Target) -> Duration
    private var lanes: [Target: Lane] = [:]
    private let lightSpacing: Duration
    private var nextLightSlot: ContinuousClock.Instant = .now

    public static let defaultGap: @Sendable (Target) -> Duration = { target in
        switch target.kind {
        case .light: .milliseconds(110)
        case .groupedLight: .milliseconds(1000)
        case .scene: .milliseconds(250)
        }
    }

    public init(gap: @escaping @Sendable (Target) -> Duration = CommandQueue.defaultGap,
                lightSpacing: Duration = .milliseconds(100),
                send: @escaping Sender, onError: @escaping ErrorHandler) {
        self.gap = gap
        self.lightSpacing = lightSpacing
        self.send = send
        self.onError = onError
    }

    public func enqueue(_ command: Command, for target: Target) {
        guard !command.isEmpty else { return }
        var lane = lanes[target] ?? Lane()
        lane.pending = lane.pending.map { $0.merging(command) } ?? command
        if lane.worker == nil {
            lane.worker = Task { await self.drain(target) }
        }
        lanes[target] = lane
    }

    /// Waits until every lane has sent everything (used by tests and before disconnecting).
    public func waitUntilIdle() async {
        while let worker = lanes.values.compactMap(\.worker).first {
            await worker.value
        }
    }

    private func drain(_ target: Target) async {
        while true {
            guard let laneWait = lanes[target]?.nextAllowed else { return }
            var slot = max(laneWait, ContinuousClock.now)
            if target.kind == .light {
                // All lights share one budget (about 10 commands a second for the whole bridge), so a room's worth
                // of lights changing at once doesn't overload it and make everything lag. Book the next free slot.
                slot = max(slot, nextLightSlot)
                nextLightSlot = slot + lightSpacing
            }
            let now = ContinuousClock.now
            if slot > now { try? await Task.sleep(for: slot - now) }

            guard let command = lanes[target]?.pending else {
                lanes[target]?.worker = nil
                return
            }
            lanes[target]?.pending = nil
            lanes[target]?.nextAllowed = .now + gap(target)
            do {
                try await send(target, command)
            } catch HueError.rateLimited {
                // The bridge asked us to slow down: keep the command (newer changes still win) and try again shortly.
                Log.warn("command", "\(Log.label(target)): bridge busy, trying again in 1 s")
                let newer = lanes[target]?.pending
                lanes[target]?.pending = newer.map { command.merging($0) } ?? command
                lanes[target]?.nextAllowed = .now + .seconds(1)
            } catch {
                await onError(target, error)
            }
            // Nothing more waiting: stop now. The gap is remembered, so a later command still respects it.
            if lanes[target]?.pending == nil {
                lanes[target]?.worker = nil
                return
            }
        }
    }
}
