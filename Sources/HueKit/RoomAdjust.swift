import Foundation

/// Decides what to send when brightness, colour or white is changed for a whole room or zone.
///
/// The rules (the owner's, so they are tested):
/// - Nothing is ever switched on or off here; only the on/off switches do that.
/// - Room on: only the lights that are on change. Lights that are off stay off and keep their setting.
/// - Room completely off: every light's setting changes, but they all stay off (it shows when switched on).
/// - Only lights that can do it are touched (no colour sent to a white-only bulb), and values are fitted to what
///   each light can show.
/// - Changes go light by light, except when a big room (more than 4 lights) is entirely on: then one whole-room
///   command, which the bridge handles better for many lights.
public enum RoomAdjust {
    public enum Setting: Equatable, Sendable {
        case brightness(Double)
        case color(XY)
        case mirek(Int)
    }

    public struct Plan: Equatable, Sendable {
        /// What each affected light gets (also used to show the change at once).
        public var changes: [SceneApply.Change]
        /// Send `changes[0].command` once to the whole room instead of light by light.
        public var asWholeRoom: Bool
    }

    public static func plan(_ setting: Setting, lights all: [Light], roomCommandAvailable: Bool) -> Plan {
        let capable = all.filter { supports($0, setting) }
        let lit = capable.filter(\.on.on)
        let targets = lit.isEmpty ? capable : lit
        let changes = targets.map { SceneApply.Change(lightID: $0.id, command: command(setting, for: $0)) }
        let everythingOn = !lit.isEmpty && all.allSatisfy(\.on.on) && lit.count == capable.count
        return Plan(changes: changes, asWholeRoom: everythingOn && lit.count > 4 && roomCommandAvailable)
    }

    static func supports(_ light: Light, _ setting: Setting) -> Bool {
        switch setting {
        case .brightness: light.supportsDimming
        case .color: light.supportsColor
        case .mirek: light.supportsWhiteTemperature
        }
    }

    static func command(_ setting: Setting, for light: Light) -> Command {
        switch setting {
        case .brightness(let b):
            return Command(brightness: min(max(b.rounded(), 1), 100))
        case .color(let xy):
            return Command(xy: ColorConversion.clamp(xy, to: light.color?.gamut ?? .c))
        case .mirek(let m):
            let s = light.colorTemperature?.mirekSchema ?? .standard
            return Command(mirek: min(max(m, s.mirekMinimum), s.mirekMaximum))
        }
    }
}

extension Light {
    /// What the light will look like after a command (shown at once, before the bridge confirms).
    public func applying(_ c: Command) -> Light {
        var l = self
        if let on = c.on { l.on = on }
        if let b = c.dimming?.brightness { l.dimming?.brightness = b }
        if let xy = c.color?.xy ?? c.gradient?.points.first?.color.xy {
            l.color?.xy = xy
            l.colorTemperature?.mirek = nil
            l.colorTemperature?.mirekValid = false
        }
        if let m = c.colorTemperature?.mirek {
            l.colorTemperature?.mirek = m
            l.colorTemperature?.mirekValid = true
        }
        return l
    }
}
