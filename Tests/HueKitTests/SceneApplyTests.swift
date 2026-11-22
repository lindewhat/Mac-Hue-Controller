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

@Test func sceneChangesOnlyLightsThatAreOn() {
    let lights = ["a": light("a", on: true), "b": light("b", on: false), "c": light("c", on: true)]
    let s = scene([("a", .init(on: true, brightness: 80, mirek: 400)),
                   ("b", .init(on: true, brightness: 80, mirek: 400)),
                   ("c", .init(on: true, brightness: 30, xy: XY(x: 0.5, y: 0.4)))])
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(changes.map(\.lightID) == ["a", "c"])                 // b is off and stays untouched
    #expect(changes.allSatisfy { $0.command.on == nil })            // nothing is switched on
    #expect(changes[0].command == Command(brightness: 80, mirek: 400))
    #expect(changes[1].command == Command(brightness: 30, xy: XY(x: 0.5, y: 0.4)))
}

@Test func aSceneCanSwitchALitLightOffButNeverOneOn() {
    let lights = ["a": light("a", on: true), "b": light("b", on: true)]
    let s = scene([("a", .init(on: false)), ("b", .init(on: true, brightness: 60))])
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(changes.first { $0.lightID == "a" }?.command.on == OnState(on: false))
    #expect(changes.first { $0.lightID == "b" }?.command.on == nil)
}

@Test func whenEverythingIsOffTheSceneIsStoredButNothingTurnsOn() {
    let lights = ["a": light("a", on: false), "b": light("b", on: false)]
    let s = scene([("a", .init(on: true, brightness: 80)), ("b", .init(on: true, brightness: 20))])
    let changes = SceneApply.changes(for: s, lights: lights)
    #expect(changes.count == 2)
    #expect(changes.allSatisfy { $0.command.on == nil })
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
