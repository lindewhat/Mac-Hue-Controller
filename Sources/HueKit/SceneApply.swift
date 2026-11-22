import Foundation

/// Applies a scene only to the lights that are on.
///
/// The bridge's own "recall scene" switches on every light in the scene. Instead, this reads the scene's setting for
/// each light and sends it straight to that light, but only to lights that are on; lights that are off stay off.
/// If every light in the scene is off, each one gets the scene's setting stored but stays off (just like dragging
/// brightness on an off room), so it shows the scene when switched on.
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
            var c = Command()
            // A scene can switch a lit light off; it never switches one on.
            if light.on.on, values.on?.on == false { c.on = OnState(on: false) }
            if light.supportsDimming, let b = values.dimming?.brightness { c.dimming = .init(brightness: max(b, 1)) }
            if light.supportsColor, let g = values.gradient, !g.points.isEmpty {
                c.gradient = g
            } else if light.supportsColor, let xy = values.color?.xy {
                c.color = .init(xy: ColorConversion.clamp(xy, to: light.color?.gamut ?? .c))
            } else if light.supportsWhiteTemperature, let m = values.colorTemperature?.mirek {
                let s = light.colorTemperature?.mirekSchema ?? .standard
                c.colorTemperature = .init(mirek: min(max(m, s.mirekMinimum), s.mirekMaximum))
            }
            return c.isEmpty ? nil : Change(lightID: light.id, command: c)
        }
    }

    /// What a light will look like after the change (shown at once, before the bridge confirms).
    public static func preview(_ light: Light, after c: Command) -> Light {
        var l = light
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
