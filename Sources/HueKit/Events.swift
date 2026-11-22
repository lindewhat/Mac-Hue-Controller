import Foundation

/// One message from the bridge's live event stream: something was added, changed or removed.
public struct HueEvent: Decodable, Sendable, Equatable {
    public var type: String          // "update", "add", "delete", "error"
    public var data: [ResourceUpdate]

    public init(type: String, data: [ResourceUpdate]) { self.type = type; self.data = data }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        data = (try c.decodeIfPresent([Lenient<ResourceUpdate>].self, forKey: .data) ?? []).compactMap(\.value)
    }

    enum CodingKeys: String, CodingKey { case type, data }
}

/// The part of a resource that changed. Only the fields the bridge sent are filled in.
public struct ResourceUpdate: Decodable, Sendable, Equatable {
    public struct ColorUpdate: Decodable, Sendable, Equatable { public var xy: XY? }
    public struct TemperatureUpdate: Decodable, Sendable, Equatable {
        public var mirek: Int?
        public var mirekValid: Bool?
    }

    public var id: String
    public var type: String          // "light", "grouped_light", "scene", "room", ...
    public var on: OnState?
    public var dimming: Dimming?
    public var color: ColorUpdate?
    public var colorTemperature: TemperatureUpdate?
    public var status: SceneStatus?
    public var metadata: Metadata?

    public init(id: String, type: String, on: OnState? = nil, dimming: Dimming? = nil, color: ColorUpdate? = nil,
                colorTemperature: TemperatureUpdate? = nil, status: SceneStatus? = nil, metadata: Metadata? = nil) {
        self.id = id; self.type = type; self.on = on; self.dimming = dimming; self.color = color
        self.colorTemperature = colorTemperature; self.status = status; self.metadata = metadata
    }

    /// Only id and type are required; any other field the bridge sends in an unexpected shape is ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(String.self, forKey: .type)
        on = try? c.decodeIfPresent(OnState.self, forKey: .on)
        dimming = try? c.decodeIfPresent(Dimming.self, forKey: .dimming)
        color = try? c.decodeIfPresent(ColorUpdate.self, forKey: .color)
        colorTemperature = try? c.decodeIfPresent(TemperatureUpdate.self, forKey: .colorTemperature)
        status = try? c.decodeIfPresent(SceneStatus.self, forKey: .status)
        metadata = try? c.decodeIfPresent(Metadata.self, forKey: .metadata)
    }

    enum CodingKeys: String, CodingKey { case id, type, on, dimming, color, colorTemperature, status, metadata }

    /// Applies this change to a light. Returns the light unchanged if the update is about something else.
    public func applied(to light: Light) -> Light {
        guard id == light.id else { return light }
        var l = light
        if let on { l.on = on }
        if let dimming { l.dimming = dimming }
        if let xy = color?.xy {
            l.color = LightColor(xy: xy, gamut: l.color?.gamut, gamutType: l.color?.gamutType)
        }
        if let ct = colorTemperature {
            let schema = l.colorTemperature?.mirekSchema
            // The bridge sends mirek = null when the light switched to a colour.
            l.colorTemperature = ColorTemperature(mirek: ct.mirek, mirekValid: ct.mirekValid ?? (ct.mirek != nil),
                                                  mirekSchema: schema)
        }
        if let metadata { l.metadata = metadata }
        return l
    }
}

/// Reads the bridge's event stream format (Server-Sent Events): lines of "id: ...", "data: ..." and ": comment",
/// with a blank line ending each message. Feed it raw bytes; it hands back each finished message's data.
public struct EventStreamParser: Sendable {
    private var lineBuffer: [UInt8] = []
    private var dataLines: [String] = []

    public init() {}

    /// Feeds bytes as they arrive (chunks may split lines anywhere). Returns the data of every message completed.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [String] where S.Element == UInt8 {
        var finished: [String] = []
        for byte in bytes {
            if byte == UInt8(ascii: "\n") {
                var line = lineBuffer
                if line.last == UInt8(ascii: "\r") { line.removeLast() }
                lineBuffer.removeAll(keepingCapacity: true)
                if let message = handle(String(decoding: line, as: UTF8.self)) { finished.append(message) }
            } else {
                lineBuffer.append(byte)
            }
        }
        return finished
    }

    private mutating func handle(_ line: String) -> String? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil } // keep-alive / comment
        let field: Substring, value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            var v = line[line.index(after: colon)...]
            if v.first == " " { v = v.dropFirst() }
            value = v
        } else {
            field = Substring(line); value = ""
        }
        switch field {
        case "data":
            dataLines.append(String(value))
            return nil
        case "id":
            // A new message started without a blank line before it: finish the previous one rather than lose it.
            return dispatch()
        default:
            return nil
        }
    }

    private mutating func dispatch() -> String? {
        guard !dataLines.isEmpty else { return nil }
        let message = dataLines.joined(separator: "\n")
        dataLines.removeAll()
        return message
    }

    /// Turns one message's data into events. Unreadable messages are skipped.
    public static func events(from message: String) -> [HueEvent] {
        guard let data = message.data(using: .utf8),
              let items = try? JSON.decoder().decode([Lenient<HueEvent>].self, from: data) else { return [] }
        return items.compactMap(\.value)
    }
}
