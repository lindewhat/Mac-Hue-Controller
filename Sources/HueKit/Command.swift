import Foundation

/// What to send to one light, one room/zone (its grouped_light) or one scene.
public struct Target: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case light, groupedLight = "grouped_light", scene }
    public var kind: Kind
    public var id: String
    public init(_ kind: Kind, _ id: String) { self.kind = kind; self.id = id }
    public var description: String { "\(kind.rawValue)/\(id)" }
}

/// One change to send. Only the fields that are set are sent.
public struct Command: Encodable, Hashable, Sendable {
    public struct DimmingValue: Encodable, Hashable, Sendable { public var brightness: Double }
    public struct ColorValue: Encodable, Hashable, Sendable { public var xy: XY }
    public struct MirekValue: Encodable, Hashable, Sendable { public var mirek: Int }
    public struct Recall: Encodable, Hashable, Sendable { public var action: String }

    public var on: OnState?
    public var dimming: DimmingValue?
    public var color: ColorValue?
    public var colorTemperature: MirekValue?
    public var recall: Recall?

    public init(on: Bool? = nil, brightness: Double? = nil, xy: XY? = nil, mirek: Int? = nil, recallScene: Bool = false) {
        self.on = on.map(OnState.init(on:))
        self.dimming = brightness.map { DimmingValue(brightness: min(max($0, 0), 100)) }
        self.color = xy.map(ColorValue.init(xy:))
        self.colorTemperature = mirek.map(MirekValue.init(mirek:))
        self.recall = recallScene ? Recall(action: "active") : nil
    }

    public var isEmpty: Bool { on == nil && dimming == nil && color == nil && colorTemperature == nil && recall == nil }

    /// Combines a waiting command with a newer one: the newer value wins for every field it sets, and nothing the
    /// older one asked for is lost. Colour and white temperature exclude each other, so the newer one wins there.
    public func merging(_ newer: Command) -> Command {
        var m = self
        if let v = newer.on { m.on = v }
        if let v = newer.dimming { m.dimming = v }
        if let v = newer.color { m.color = v; m.colorTemperature = nil }
        if let v = newer.colorTemperature { m.colorTemperature = v; m.color = nil }
        if let v = newer.recall { m.recall = v }
        return m
    }

    public func json() throws -> Data { try JSON.encoder().encode(self) }
}
