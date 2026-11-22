import Foundation
import Testing
@testable import HueKit

private func decode<T: Decodable>(_ json: String, as: T.Type) throws -> [T] {
    try JSON.decoder().decode(Envelope<T>.self, from: Data(json.utf8)).data
}

private func snapshot() throws -> Snapshot {
    Snapshot(lights: try decode(Fixtures.lights, as: Light.self),
             rooms: try decode(Fixtures.rooms, as: Area.self),
             zones: try decode(Fixtures.zones, as: Area.self),
             groupedLights: try decode(Fixtures.groupedLights, as: GroupedLight.self),
             scenes: try decode(Fixtures.scenes, as: Scene.self),
             devices: try decode(Fixtures.devices, as: Device.self))
}

// MARK: - Reading the bridge's answers

@Test func lightsDecodeAndABrokenOneIsSkipped() throws {
    let lights = try decode(Fixtures.lights, as: Light.self)
    #expect(lights.map(\.id) == ["l-sofa", "l-ceiling", "l-plug", "l-strip"])
    let sofa = lights[0]
    #expect(sofa.on.on && sofa.dimming?.brightness == 62.5)
    #expect(sofa.colorTemperature?.mirekSchema == MirekSchema(mirekMinimum: 153, mirekMaximum: 500))
    #expect(sofa.color?.gamut == Gamut.c)
    #expect(sofa.isInWhiteMode)
    #expect(!lights[1].isInWhiteMode) // mirek null: not showing a white
    #expect(!lights[2].supportsDimming && !lights[2].supportsColor) // a smart plug
    #expect(lights[3].color?.gamut == nil) // gamut missing is fine
}

@Test func roomsAndZonesBecomeGroupsWithTheirLightsAndScenes() throws {
    let (rooms, zones) = Topology.build(try snapshot())
    #expect(rooms.map(\.name) == ["Living room", "Office"])
    let living = rooms[0]
    #expect(living.groupedLightID == "g-living")
    // Lights come from the room's devices (the dimmer switch has no light), sorted by name.
    #expect(living.lightIDs == ["l-ceiling", "l-plug", "l-sofa"])
    #expect(living.sceneIDs == ["s-bright", "s-relax"])
    // Zones list lights directly; a light the bridge no longer has is left out.
    #expect(zones.map(\.name) == ["Cosy corner"])
    #expect(zones[0].lightIDs == ["l-strip", "l-sofa"])
    #expect(zones[0].kind == .zone)
}

@Test func scenesKnowWhetherTheyAreActive() throws {
    let scenes = try decode(Fixtures.scenes, as: Scene.self)
    #expect(scenes.map(\.isActive) == [true, false, false])
}

@Test func pairingAnswersAreUnderstood() throws {
    let waiting = Data(#"[{"error":{"type":101,"address":"","description":"link button not pressed"}}]"#.utf8)
    #expect(try BridgePairing.parsePairingAnswer(waiting) == nil)
    let ok = Data(#"[{"success":{"username":"abc123","clientkey":"XYZ"}}]"#.utf8)
    #expect(try BridgePairing.parsePairingAnswer(ok) == "abc123")
    let other = Data(#"[{"error":{"type":7,"address":"","description":"invalid value"}}]"#.utf8)
    #expect(throws: HueError.bridgeSaid("invalid value")) { try BridgePairing.parsePairingAnswer(other) }
    #expect(throws: HueError.unexpectedAnswer) { try BridgePairing.parsePairingAnswer(Data("<html>".utf8)) }
}

// MARK: - Commands

@Test func commandsSendOnlyWhatIsSet() throws {
    let json = String(decoding: try Command(on: true, brightness: 40).json(), as: UTF8.self)
    #expect(json == #"{"dimming":{"brightness":40},"on":{"on":true}}"#)
    let white = String(decoding: try Command(mirek: 300).json(), as: UTF8.self)
    #expect(white == #"{"color_temperature":{"mirek":300}}"#)
    let scene = String(decoding: try Command(recallScene: true).json(), as: UTF8.self)
    #expect(scene == #"{"recall":{"action":"active"}}"#)
}

@Test func mergingKeepsEverythingAndNewestWins() {
    let merged = Command(on: false).merging(Command(brightness: 30)).merging(Command(brightness: 70))
    #expect(merged == Command(on: false, brightness: 70))
    // Colour and white exclude each other: the newer one wins.
    #expect(Command(xy: XY(x: 0.5, y: 0.4)).merging(Command(mirek: 250)) == Command(mirek: 250))
    #expect(Command(mirek: 250).merging(Command(xy: XY(x: 0.5, y: 0.4))) == Command(xy: XY(x: 0.5, y: 0.4)))
}

// MARK: - Live event stream

@Test func eventStreamMessagesAreParsed() {
    var parser = EventStreamParser()
    let messages = parser.feed(Array(Fixtures.stream.utf8))
    #expect(messages.count == 2) // the ": hi" keep-alive is ignored
    let events = messages.flatMap(EventStreamParser.events(from:))
    #expect(events.count == 2)
    #expect(events[0].data[0] == ResourceUpdate(id: "l-sofa", type: "light", on: OnState(on: false)))
    #expect(events[1].data.count == 2)
}

@Test func eventStreamSurvivesChunksSplitAnywhere() {
    let bytes = Array(Fixtures.stream.utf8)
    for size in [1, 3, 7, 50] {
        var parser = EventStreamParser()
        var messages: [String] = []
        var i = 0
        while i < bytes.count {
            messages += parser.feed(bytes[i..<min(i + size, bytes.count)])
            i += size
        }
        #expect(messages.count == 2, "chunk size \(size)")
    }
}

@Test func eventStreamHandlesMultiLineDataAndMissingBlankLines() {
    var parser = EventStreamParser()
    let text = "data: [\ndata: ]\n\nid: 2\ndata: [1]\nid: 3\ndata: [2]\n\n"
    #expect(parser.feed(Array(text.utf8)) == ["[\n]", "[1]", "[2]"])
}

@Test func updatesChangeOnlyWhatTheySay() throws {
    let sofa = try decode(Fixtures.lights, as: Light.self)[0]
    var parser = EventStreamParser()
    let events = parser.feed(Array(Fixtures.stream.utf8)).flatMap(EventStreamParser.events(from:))
    var light = sofa
    for update in events.flatMap(\.data) { light = update.applied(to: light) }
    #expect(light.on.on == false)
    #expect(light.dimming?.brightness == 20)
    #expect(light.color?.xy == XY(x: 0.6, y: 0.3))
    #expect(light.color?.gamut == Gamut.c)                       // kept from before
    #expect(light.colorTemperature?.mirekSchema?.mirekMaximum == 500) // kept from before
    #expect(!light.isInWhiteMode)
    #expect(light.name == "Sofa lamp")
    // An update for another light changes nothing.
    #expect(ResourceUpdate(id: "other", type: "light", on: OnState(on: false)).applied(to: sofa) == sofa)
}

// MARK: - Colour maths

@Test func colourRoundTripsThroughXY() {
    let samples = [RGB(r: 1, g: 0, b: 0), RGB(r: 0, g: 1, b: 0), RGB(r: 0, g: 0, b: 1),
                   RGB(r: 1, g: 0.5, b: 0), RGB(r: 0.2, g: 0.6, b: 1), RGB(r: 1, g: 1, b: 1)]
    for c in samples {
        let back = ColorConversion.rgb(from: ColorConversion.xy(from: c))
        #expect(abs(back.r - c.r) < 0.01 && abs(back.g - c.g) < 0.01 && abs(back.b - c.b) < 0.01, "\(c) -> \(back)")
    }
    let white = ColorConversion.xy(from: .white)
    #expect(abs(white.x - 0.3127) < 0.001 && abs(white.y - 0.329) < 0.001)
}

@Test func coloursOutsideALightsRangeMoveToItsEdge() {
    let inside = XY(x: 0.4, y: 0.4)
    #expect(ColorConversion.clamp(inside, to: .c) == inside)
    let outside = XY(x: 0.75, y: 0.25) // redder than any Hue light can show
    let clamped = ColorConversion.clamp(outside, to: .c)
    #expect(clamped != outside)
    #expect(ColorConversion.isInside(XY(x: clamped.x - 0.0001, y: clamped.y), .c) || ColorConversion.isInside(clamped, .c))
    #expect(abs(clamped.x - 0.6915) < 0.05)
}

@Test func whiteTemperatureConversions() {
    #expect(ColorConversion.mirek(fromKelvin: 2700) == 370)
    #expect(Int(ColorConversion.kelvin(fromMirek: 153)) == 6535)
    let warm = ColorConversion.rgb(kelvin: 2200), cool = ColorConversion.rgb(kelvin: 6500)
    #expect(warm.r > warm.b && cool.b > warm.b)
}

@Test func wheelColoursRoundTrip() {
    for hue in stride(from: 0.0, to: 1.0, by: 0.1) {
        let hsb = HSB(hue: hue, saturation: 0.8, brightness: 1)
        let back = ColorConversion.hsb(from: ColorConversion.rgb(from: hsb))
        #expect(abs(back.hue - hue) < 0.001 && abs(back.saturation - 0.8) < 0.001)
    }
}
