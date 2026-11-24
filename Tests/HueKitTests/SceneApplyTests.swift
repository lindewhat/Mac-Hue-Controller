import Foundation
import Testing
@testable import HueKit

private func light(_ id: String, on: Bool, color: Bool = true) -> Light {
    Light(id: id, metadata: Metadata(name: id), on: OnState(on: on), dimming: Dimming(brightness: 50),
          color: color ? LightColor(xy: XY(x: 0.3, y: 0.3), gamut: .c) : nil,
          colorTemperature: ColorTemperature(mirek: 300, mirekValid: true, mirekSchema: .standard))
}

private func scene(_ actions: [(String, SceneAction.Values)]) -> Scene {
    Scene(id: "s", metadata: Metadata(name: "Relax"), group: ResourceRef(rid: "r", rtype: "room"),
          actions: actions.map { SceneAction(target: ResourceRef(rid: $0.0, rtype: "light"), action: $0.1) })
}

private func gradient(_ points: [XY]) -> Gradient {
    Gradient(points: points.map { .init(color: .init(xy: $0)) }, mode: "interpolated_palette")
}

@Test func sceneChangesOnlyTheLookOfLightsThatAreOn() {
    let lights = ["a": light("a", on: true), "b": light("b", on: false), "c": light("c", on: true)]
    let s = scene([("a", .init(on: true, brightness: 80, mirek: 400)),
                   ("b", .init(on: true, brightness: 80, mirek: 400)),
                   ("c", .init(on: true, brightness: 30, xy: XY(x: 0.5, y: 0.4)))])
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(changes.map(\.lightID) == ["a", "c"])                 // b is off and stays untouched
    #expect(changes[0].command == Command(mirek: 400))              // warmth only, no brightness
    #expect(changes[1].command == Command(xy: XY(x: 0.5, y: 0.4)))  // colour only, no brightness
}

@Test func aSceneNeverSwitchesAnyLightOnOrOff() {
    let lights = ["a": light("a", on: true), "b": light("b", on: true), "c": light("c", on: false),
                  "d": light("d", on: true)]
    let s = scene([("a", .init(on: false, mirek: 350)),               // says off: the look applies, it stays on
                   ("b", .init(on: true, xy: XY(x: 0.4, y: 0.4))),
                   ("c", .init(on: true, mirek: 250)),                // off: stays off and untouched
                   ("d", .init(on: false))])                          // says only off: nothing to do
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(Set(changes.map(\.lightID)) == ["a", "b"])
    #expect(changes.allSatisfy { $0.command.on == nil })
}

@Test func whenEverythingIsOffTheLookIsStoredButNothingTurnsOn() {
    let lights = ["a": light("a", on: false), "b": light("b", on: false)]
    let s = scene([("a", .init(on: true, brightness: 80, mirek: 420)),
                   ("b", .init(on: true, brightness: 20, xy: XY(x: 0.3, y: 0.3)))])
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(changes.count == 2)
    #expect(changes.allSatisfy { $0.command.on == nil && $0.command.dimming == nil })
    #expect(changes.first { $0.lightID == "a" }?.command == Command(mirek: 420))
}

@Test(arguments: [1.0, 100.0, 0.5, 56.3])
func aSceneNeverChangesBrightness(_ brightness: Double) throws {
    let lights = ["x": light("x", on: true), "m": light("m", on: true), "g": light("g", on: true),
                  "w": light("w", on: true, color: false), "b": light("b", on: true)]
    var withGradient = SceneAction.Values(on: true, brightness: brightness)
    withGradient.gradient = gradient([XY(x: 0.6, y: 0.3), XY(x: 0.2, y: 0.1)])
    let s = scene([("x", .init(on: true, brightness: brightness, xy: XY(x: 0.45, y: 0.4))),
                   ("m", .init(on: true, brightness: brightness, mirek: 300)),
                   ("g", withGradient),
                   ("w", .init(on: true, brightness: brightness, xy: XY(x: 0.5, y: 0.4), mirek: 450)),
                   ("b", .init(on: true, brightness: brightness))])  // brightness only: nothing to do
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(Set(changes.map(\.lightID)) == ["x", "m", "g", "w"])
    for change in changes {
        #expect(change.command.dimming == nil)
        #expect(change.command.on == nil)
        let json = String(decoding: try change.command.json(), as: UTF8.self)
        #expect(!json.contains("dimming"), "\(change.lightID): \(json)")
        #expect(!json.contains(#""on""#), "\(change.lightID): \(json)")
    }
    #expect(changes.first { $0.lightID == "g" }?.command.gradient?.points.count == 2)
}

@Test func onlyScenesWithColourWarmthOrGradientChangeTheLook() {
    func lookOf(_ values: SceneAction.Values) -> Bool { scene([("a", values)]).changesLook }
    #expect(!lookOf(.init(brightness: 40)))                 // brightness only
    #expect(!lookOf(.init(on: true)))                       // on/off only
    #expect(!lookOf(.init(on: false, brightness: 10)))
    #expect(lookOf(.init(mirek: 366)))
    #expect(lookOf(.init(xy: XY(x: 0.3, y: 0.3))))
    var g = SceneAction.Values(brightness: 50)
    g.gradient = gradient([XY(x: 0.6, y: 0.3), XY(x: 0.2, y: 0.1)])
    #expect(lookOf(g))
    var empty = SceneAction.Values(brightness: 50)
    empty.gradient = gradient([])
    #expect(!lookOf(empty))                                 // an empty gradient is no look
    var noMirek = SceneAction.Values(brightness: 50)
    noMirek.colorTemperature = .init(mirek: nil)
    #expect(!lookOf(noMirek))                               // warmth without a value is no look
    let noActions = Scene(id: "s", metadata: Metadata(name: "Old"), group: ResourceRef(rid: "r", rtype: "room"),
                          actions: nil)
    #expect(!noActions.changesLook)
}

@Test func coloursFitTheLightAndWhiteOnlyLightsGetWhite() {
    let lights = ["a": light("a", on: true), "w": light("w", on: true, color: false)]
    let s = scene([("a", .init(xy: XY(x: 0.75, y: 0.25))), ("w", .init(xy: XY(x: 0.5, y: 0.4), mirek: 450))])
    let changes = SceneApply.changes(for: s, lights: lights)
    let a = changes.first { $0.lightID == "a" }!.command.color!.xy
    #expect(a != XY(x: 0.75, y: 0.25))   // moved inside what the light can show
    #expect(changes.first { $0.lightID == "w" }!.command == Command(mirek: 450))
}

@Test func scenesFromTheBridgeAreRead() throws {
    let json = #"""
    {"errors":[],"data":[{"id":"s1","type":"scene","metadata":{"name":"Relax"},"group":{"rid":"r","rtype":"room"},
      "actions":[{"target":{"rid":"l1","rtype":"light"},"action":{"on":{"on":true},"dimming":{"brightness":56.3},
        "color_temperature":{"mirek":447}}},
        {"target":{"rid":"l2","rtype":"light"},"action":{"on":{"on":true},
        "gradient":{"points":[{"color":{"xy":{"x":0.6,"y":0.3}}},{"color":{"xy":{"x":0.2,"y":0.1}}}],"mode":"interpolated_palette"},
        "effects":{"effect":"candle"}}}],
      "status":{"active":"inactive"}}]}
    """#
    let scenes = try JSON.decoder().decode(Envelope<Scene>.self, from: Data(json.utf8)).data
    #expect(scenes.count == 1)
    #expect(scenes[0].actions?.count == 2)
    #expect(scenes[0].actions?[0].action.colorTemperature?.mirek == 447)
    #expect(scenes[0].actions?[1].action.gradient?.points.count == 2)
    let gradientJSON = String(decoding: try Command(brightness: 50).merging({
        var c = Command(); c.gradient = scenes[0].actions?[1].action.gradient; return c }()).json(), as: UTF8.self)
    #expect(gradientJSON.contains(#""gradient":{"mode":"interpolated_palette","points":[{"color":{"xy""#))
}
