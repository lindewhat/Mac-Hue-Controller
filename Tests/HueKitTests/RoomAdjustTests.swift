import Testing
@testable import HueKit

private func light(_ id: String, on: Bool, dim: Bool = true, color: Bool = true, white: Bool = true) -> Light {
    Light(id: id, metadata: Metadata(name: id), on: OnState(on: on),
          dimming: dim ? Dimming(brightness: 50) : nil,
          color: color ? LightColor(xy: XY(x: 0.3, y: 0.3), gamut: .c) : nil,
          colorTemperature: white ? ColorTemperature(mirek: 300, mirekValid: true,
                                                     mirekSchema: MirekSchema(mirekMinimum: 153, mirekMaximum: 454)) : nil)
}

@Test func roomBrightnessLeavesLightsThatAreOffAlone() {
    let lights = [light("a", on: true), light("b", on: false), light("c", on: true)]
    let plan = RoomAdjust.plan(.brightness(30), lights: lights, roomCommandAvailable: true)
    #expect(plan.changes.map(\.lightID) == ["a", "c"])
    #expect(plan.changes.allSatisfy { $0.command == Command(brightness: 30) }) // no "on" anywhere
    #expect(!plan.asWholeRoom) // a whole-room command would reach the light that's off
}

@Test func roomWarmthAndColourLeaveLightsThatAreOffAlone() {
    let lights = [light("a", on: true), light("b", on: false)]
    #expect(RoomAdjust.plan(.mirek(400), lights: lights, roomCommandAvailable: true).changes.map(\.lightID) == ["a"])
    #expect(RoomAdjust.plan(.color(XY(x: 0.5, y: 0.4)), lights: lights, roomCommandAvailable: true)
        .changes.map(\.lightID) == ["a"])
}

@Test func aRoomThatIsOffGetsTheSettingButStaysOff() {
    let lights = [light("a", on: false), light("b", on: false)]
    let plan = RoomAdjust.plan(.brightness(80), lights: lights, roomCommandAvailable: true)
    #expect(plan.changes.map(\.lightID) == ["a", "b"])
    #expect(plan.changes.allSatisfy { $0.command.on == nil })
    #expect(!plan.asWholeRoom)
    #expect(lights[0].applying(plan.changes[0].command).on.on == false)
}

@Test func onlyLightsThatCanDoItAreTouched() {
    let lights = [light("colour", on: true), light("white", on: true, color: false), light("plug", on: true, dim: false, color: false, white: false)]
    #expect(RoomAdjust.plan(.color(XY(x: 0.5, y: 0.4)), lights: lights, roomCommandAvailable: false).changes.map(\.lightID) == ["colour"])
    #expect(RoomAdjust.plan(.brightness(40), lights: lights, roomCommandAvailable: false).changes.map(\.lightID) == ["colour", "white"])
}

@Test func valuesAreFittedToEachLight() {
    let plan = RoomAdjust.plan(.mirek(500), lights: [light("a", on: true)], roomCommandAvailable: false)
    #expect(plan.changes[0].command == Command(mirek: 454)) // this light's warmest white
    #expect(RoomAdjust.plan(.brightness(0.2), lights: [light("a", on: true)], roomCommandAvailable: false)
        .changes[0].command == Command(brightness: 1))
}

@Test func aBigRoomThatIsAllOnGoesAsOneCommand() {
    let big = (1...5).map { light("l\($0)", on: true) }
    #expect(RoomAdjust.plan(.brightness(60), lights: big, roomCommandAvailable: true).asWholeRoom)
    #expect(!RoomAdjust.plan(.brightness(60), lights: big, roomCommandAvailable: false).asWholeRoom)
    var mixed = big; mixed[0].on.on = false
    #expect(!RoomAdjust.plan(.brightness(60), lights: mixed, roomCommandAvailable: true).asWholeRoom)
}
