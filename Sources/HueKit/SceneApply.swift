import Foundation

/// Applies a scene's look (colour, white warmth or gradient) to the lights that are on.
///
/// The rules (the owner's, so they are tested):
/// - A scene changes only how a light looks: its colour, its white warmth, or its gradient.
/// - It never changes a light's brightness and never switches a light on or off, whatever the scene says.
/// - Only lights that are on change; lights that are off stay off and untouched. If every light in the scene is off,
///   each one gets the look stored but stays off, so it shows the scene's look when switched on.
/// - Colours are fitted to what each light can show; white-only bulbs get only the warmth; gradient lights get the
///   gradient.
/// - No "recall" command is sent: the bridge's own recall switches lights on and sets their brightness.
public enum SceneApply {
    public struct Change: Equatable, Sendable {
        public var lightID: String
        public var command: Command
    }

    public static func changes(for scene: Scene, lights: [String: Light]) -> [Change] {
        let steps = (scene.actions ?? []).compactMap { a -> (Light, SceneAction.Values)? in
            guard a.target.rtype == "light", let light = lights[a.target.rid] else { return nil }
            return (light, a.action)
        }
        let anyOn = steps.contains { $0.0.on.on }
        return steps.compactMap { light, values in
            if anyOn && !light.on.on { return nil } // off stays off, untouched
            let c = look(values, for: light)
            return c.isEmpty ? nil : Change(lightID: light.id, command: c)
        }
    }

    /// Only the look: `on` and `dimming` are never set here.
    private static func look(_ values: SceneAction.Values, for light: Light) -> Command {
        var c = Command()
        if light.supportsColor, let g = values.gradient, !g.points.isEmpty {
            c.gradient = g
        } else if light.supportsColor, let xy = values.color?.xy {
            c.color = .init(xy: ColorConversion.clamp(xy, to: light.color?.gamut ?? .c))
        } else if light.supportsWhiteTemperature, let m = values.colorTemperature?.mirek {
            let s = light.colorTemperature?.mirekSchema ?? .standard
            c.colorTemperature = .init(mirek: min(max(m, s.mirekMinimum), s.mirekMaximum))
        }
        return c
    }
}

extension Scene {
    /// True when the scene has a look to apply: a colour, a white warmth or a gradient for at least one light.
    /// A scene that only sets brightness or on/off has nothing the app applies, so it isn't offered.
    public var changesLook: Bool {
        (actions ?? []).contains { a in
            a.action.color != nil
                || a.action.colorTemperature?.mirek != nil
                || !(a.action.gradient?.points.isEmpty ?? true)
        }
    }
}
