import Foundation

/// A room or zone as the app shows it: a name, the lights in it, its whole-group switch and its scenes.
public struct LightGroup: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable { case room, zone }

    public var id: String
    public var name: String
    public var kind: Kind
    public var archetype: String?
    /// The bridge's "all lights in this group" switch. Used for on/off, brightness and colour of the whole group.
    public var groupedLightID: String?
    public var lightIDs: [String]
    public var sceneIDs: [String]

    public init(id: String, name: String, kind: Kind, archetype: String? = nil, groupedLightID: String?,
                lightIDs: [String], sceneIDs: [String]) {
        self.id = id; self.name = name; self.kind = kind; self.archetype = archetype
        self.groupedLightID = groupedLightID; self.lightIDs = lightIDs; self.sceneIDs = sceneIDs
    }
}

public enum Topology {
    /// Rooms hold devices (each device has one or more lights); zones hold lights directly. Both are handled
    /// either way round, in case the bridge ever mixes them.
    public static func build(_ s: Snapshot) -> (rooms: [LightGroup], zones: [LightGroup]) {
        let lightsByID = Dictionary(s.lights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let devicesByID = Dictionary(s.devices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byName: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }

        func group(_ area: Area, _ kind: LightGroup.Kind) -> LightGroup {
            var ids: [String] = []
            for child in area.children {
                switch child.rtype {
                case "light":
                    ids.append(child.rid)
                case "device":
                    let services = devicesByID[child.rid]?.services ?? []
                    ids += services.filter { $0.rtype == "light" }.map(\.rid)
                default:
                    break
                }
            }
            var seen = Set<String>()
            let lights = ids.filter { lightsByID[$0] != nil && seen.insert($0).inserted }
                .sorted { LightOrder.areInIncreasingOrder(lightsByID[$0]?.name ?? "", lightsByID[$1]?.name ?? "") }
            let scenes = s.scenes.filter { $0.group.rid == area.id }
                .sorted { byName($0.name, $1.name) }
                .map(\.id)
            return LightGroup(id: area.id, name: area.metadata.name, kind: kind, archetype: area.metadata.archetype,
                              groupedLightID: area.services.first { $0.rtype == "grouped_light" }?.rid,
                              lightIDs: lights, sceneIDs: scenes)
        }

        let rooms = s.rooms.map { group($0, .room) }.sorted { byName($0.name, $1.name) }
        let zones = s.zones.map { group($0, .zone) }.sorted { byName($0.name, $1.name) }
        return (rooms, zones)
    }
}
