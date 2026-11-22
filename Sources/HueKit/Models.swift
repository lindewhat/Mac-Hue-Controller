import Foundation

// The Hue API v2 ("CLIP") resources this app uses. Field names follow the bridge's JSON (snake_case is
// converted automatically). Everything optional that some lights don't have (dimming, colour) is optional here.

public struct ResourceRef: Codable, Hashable, Sendable {
    public var rid: String
    public var rtype: String
    public init(rid: String, rtype: String) { self.rid = rid; self.rtype = rtype }
}

public struct Metadata: Codable, Hashable, Sendable {
    public var name: String
    public var archetype: String?
    public init(name: String, archetype: String? = nil) { self.name = name; self.archetype = archetype }
}

public struct OnState: Codable, Hashable, Sendable {
    public var on: Bool
    public init(on: Bool) { self.on = on }
}

public struct Dimming: Codable, Hashable, Sendable {
    /// 0...100 (the bridge never goes below the light's minimum when the light is on).
    public var brightness: Double
    public init(brightness: Double) { self.brightness = brightness }
}

public struct XY: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Gamut: Codable, Hashable, Sendable {
    public var red: XY
    public var green: XY
    public var blue: XY
    public init(red: XY, green: XY, blue: XY) { self.red = red; self.green = green; self.blue = blue }

    /// Philips' published gamuts, used when a light doesn't report its own.
    public static let a = Gamut(red: XY(x: 0.704, y: 0.296), green: XY(x: 0.2151, y: 0.7106), blue: XY(x: 0.138, y: 0.08))
    public static let b = Gamut(red: XY(x: 0.675, y: 0.322), green: XY(x: 0.409, y: 0.518), blue: XY(x: 0.167, y: 0.04))
    public static let c = Gamut(red: XY(x: 0.6915, y: 0.3083), green: XY(x: 0.17, y: 0.7), blue: XY(x: 0.1532, y: 0.0475))
}

public struct LightColor: Codable, Hashable, Sendable {
    public var xy: XY
    public var gamut: Gamut?
    public var gamutType: String?
    public init(xy: XY, gamut: Gamut? = nil, gamutType: String? = nil) {
        self.xy = xy; self.gamut = gamut; self.gamutType = gamutType
    }
}

public struct MirekSchema: Codable, Hashable, Sendable {
    public var mirekMinimum: Int
    public var mirekMaximum: Int
    public init(mirekMinimum: Int, mirekMaximum: Int) { self.mirekMinimum = mirekMinimum; self.mirekMaximum = mirekMaximum }
    public static let standard = MirekSchema(mirekMinimum: 153, mirekMaximum: 500)
}

public struct ColorTemperature: Codable, Hashable, Sendable {
    /// nil when the light is showing a colour rather than a shade of white.
    public var mirek: Int?
    public var mirekValid: Bool?
    public var mirekSchema: MirekSchema?
    public init(mirek: Int?, mirekValid: Bool? = nil, mirekSchema: MirekSchema? = nil) {
        self.mirek = mirek; self.mirekValid = mirekValid; self.mirekSchema = mirekSchema
    }
}

public struct Light: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var owner: ResourceRef?
    public var metadata: Metadata
    public var on: OnState
    public var dimming: Dimming?
    public var color: LightColor?
    public var colorTemperature: ColorTemperature?

    public init(id: String, owner: ResourceRef? = nil, metadata: Metadata, on: OnState, dimming: Dimming? = nil,
                color: LightColor? = nil, colorTemperature: ColorTemperature? = nil) {
        self.id = id; self.owner = owner; self.metadata = metadata; self.on = on
        self.dimming = dimming; self.color = color; self.colorTemperature = colorTemperature
    }

    public var name: String { metadata.name }
    public var supportsDimming: Bool { dimming != nil }
    public var supportsColor: Bool { color != nil }
    public var supportsWhiteTemperature: Bool { colorTemperature != nil }

    /// True when the light is showing a shade of white (set by temperature) rather than a colour.
    public var isInWhiteMode: Bool {
        guard let ct = colorTemperature, ct.mirek != nil else { return false }
        return ct.mirekValid ?? true
    }
}

/// A room (lights grouped by the devices in it) or a zone (lights picked directly).
public struct Area: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metadata: Metadata
    public var children: [ResourceRef]
    public var services: [ResourceRef]
    public init(id: String, metadata: Metadata, children: [ResourceRef], services: [ResourceRef]) {
        self.id = id; self.metadata = metadata; self.children = children; self.services = services
    }
}

/// The "whole room/zone" switch the bridge offers for each room and zone.
public struct GroupedLight: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var owner: ResourceRef?
    public var on: OnState?
    public var dimming: Dimming?
    public init(id: String, owner: ResourceRef? = nil, on: OnState? = nil, dimming: Dimming? = nil) {
        self.id = id; self.owner = owner; self.on = on; self.dimming = dimming
    }
}

public struct SceneStatus: Codable, Hashable, Sendable {
    /// "inactive", "static" or "dynamic_palette".
    public var active: String?
    public init(active: String?) { self.active = active }
}

public struct Scene: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metadata: Metadata
    public var group: ResourceRef
    public var status: SceneStatus?
    public init(id: String, metadata: Metadata, group: ResourceRef, status: SceneStatus? = nil) {
        self.id = id; self.metadata = metadata; self.group = group; self.status = status
    }
    public var name: String { metadata.name }
    public var isActive: Bool { (status?.active ?? "inactive") != "inactive" }
}

public struct Device: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var metadata: Metadata?
    public var services: [ResourceRef]
    public init(id: String, metadata: Metadata? = nil, services: [ResourceRef]) {
        self.id = id; self.metadata = metadata; self.services = services
    }
}

/// Everything the app needs from the bridge, read in one go.
public struct Snapshot: Sendable, Equatable {
    public var lights: [Light]
    public var rooms: [Area]
    public var zones: [Area]
    public var groupedLights: [GroupedLight]
    public var scenes: [Scene]
    public var devices: [Device]
    public init(lights: [Light] = [], rooms: [Area] = [], zones: [Area] = [], groupedLights: [GroupedLight] = [],
                scenes: [Scene] = [], devices: [Device] = []) {
        self.lights = lights; self.rooms = rooms; self.zones = zones
        self.groupedLights = groupedLights; self.scenes = scenes; self.devices = devices
    }
}

/// The paired bridge, as remembered between launches. The app key itself lives in the Keychain.
public struct SavedBridge: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var host: String
    /// SHA-256 of the bridge's own security certificate, remembered when pairing (see BridgeTrust).
    public var certificateHash: String?
    public init(id: String, name: String, host: String, certificateHash: String?) {
        self.id = id; self.name = name; self.host = host; self.certificateHash = certificateHash
    }
}

// MARK: - Decoding helpers

enum JSON {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .sortedKeys
        return e
    }
}

/// The bridge wraps every answer as {"errors": [...], "data": [...]}.
struct Envelope<T: Decodable>: Decodable {
    var data: [T]
    var errors: [APIError]

    struct APIError: Decodable { var description: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One odd resource (say, a new kind of light) must never hide all the others, so skip what can't be read.
        data = (try c.decodeIfPresent([Lenient<T>].self, forKey: .data) ?? []).compactMap(\.value)
        errors = try c.decodeIfPresent([APIError].self, forKey: .errors) ?? []
    }

    enum CodingKeys: String, CodingKey { case data, errors }
}

struct Lenient<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
