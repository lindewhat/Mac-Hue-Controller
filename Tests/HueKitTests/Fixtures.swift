import Foundation

/// Answers shaped like a real Hue Bridge's (API v2), trimmed to the fields that matter.
enum Fixtures {
    static let lights = #"""
    {"errors":[],"data":[
      {"id":"l-sofa","type":"light","owner":{"rid":"d-sofa","rtype":"device"},
       "metadata":{"name":"Sofa lamp","archetype":"sultan_bulb"},
       "on":{"on":true},"dimming":{"brightness":62.5,"min_dim_level":0.2},
       "color_temperature":{"mirek":366,"mirek_valid":true,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":500}},
       "color":{"xy":{"x":0.4573,"y":0.41},"gamut":{"red":{"x":0.6915,"y":0.3083},"green":{"x":0.17,"y":0.7},"blue":{"x":0.1532,"y":0.0475}},"gamut_type":"C"}},
      {"id":"l-ceiling","type":"light","owner":{"rid":"d-ceiling","rtype":"device"},
       "metadata":{"name":"Ceiling","archetype":"ceiling_round"},
       "on":{"on":false},"dimming":{"brightness":100.0},
       "color_temperature":{"mirek":null,"mirek_valid":false,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":454}}},
      {"id":"l-plug","type":"light","owner":{"rid":"d-plug","rtype":"device"},
       "metadata":{"name":"Christmas tree","archetype":"plug"},
       "on":{"on":true}},
      {"id":"l-strip","type":"light","owner":{"rid":"d-strip","rtype":"device"},
       "metadata":{"name":"Desk strip","archetype":"hue_lightstrip"},
       "on":{"on":true},"dimming":{"brightness":30.0},
       "color":{"xy":{"x":0.2,"y":0.1},"gamut_type":"C"}},
      {"id":"broken","type":"light","on":"this is not how the bridge talks"}
    ]}
    """#

    static let devices = #"""
    {"errors":[],"data":[
      {"id":"d-sofa","type":"device","metadata":{"name":"Sofa lamp"},"services":[{"rid":"l-sofa","rtype":"light"},{"rid":"zz","rtype":"zigbee_connectivity"}]},
      {"id":"d-ceiling","type":"device","metadata":{"name":"Ceiling"},"services":[{"rid":"l-ceiling","rtype":"light"}]},
      {"id":"d-plug","type":"device","metadata":{"name":"Christmas tree"},"services":[{"rid":"l-plug","rtype":"light"}]},
      {"id":"d-strip","type":"device","metadata":{"name":"Desk strip"},"services":[{"rid":"l-strip","rtype":"light"}]},
      {"id":"d-switch","type":"device","metadata":{"name":"Dimmer switch"},"services":[{"rid":"b1","rtype":"button"}]}
    ]}
    """#

    static let rooms = #"""
    {"errors":[],"data":[
      {"id":"r-living","type":"room","metadata":{"name":"Living room","archetype":"living_room"},
       "children":[{"rid":"d-sofa","rtype":"device"},{"rid":"d-ceiling","rtype":"device"},{"rid":"d-plug","rtype":"device"},{"rid":"d-switch","rtype":"device"}],
       "services":[{"rid":"g-living","rtype":"grouped_light"}]},
      {"id":"r-office","type":"room","metadata":{"name":"Office","archetype":"office"},
       "children":[{"rid":"d-strip","rtype":"device"}],
       "services":[{"rid":"g-office","rtype":"grouped_light"}]}
    ]}
    """#

    static let zones = #"""
    {"errors":[],"data":[
      {"id":"z-cosy","type":"zone","metadata":{"name":"Cosy corner","archetype":"reading"},
       "children":[{"rid":"l-strip","rtype":"light"},{"rid":"l-sofa","rtype":"light"},{"rid":"l-gone","rtype":"light"}],
       "services":[{"rid":"g-cosy","rtype":"grouped_light"}]}
    ]}
    """#

    static let scenes = #"""
    {"errors":[],"data":[
      {"id":"s-relax","type":"scene","metadata":{"name":"Relax"},"group":{"rid":"r-living","rtype":"room"},"status":{"active":"static"}},
      {"id":"s-bright","type":"scene","metadata":{"name":"Bright"},"group":{"rid":"r-living","rtype":"room"},"status":{"active":"inactive"}},
      {"id":"s-focus","type":"scene","metadata":{"name":"Concentrate"},"group":{"rid":"r-office","rtype":"room"}}
    ]}
    """#

    static let groupedLights = #"""
    {"errors":[],"data":[
      {"id":"g-living","type":"grouped_light","owner":{"rid":"r-living","rtype":"room"},"on":{"on":true},"dimming":{"brightness":62.5}},
      {"id":"g-office","type":"grouped_light","owner":{"rid":"r-office","rtype":"room"},"on":{"on":true}},
      {"id":"g-cosy","type":"grouped_light","owner":{"rid":"z-cosy","rtype":"zone"},"on":{"on":true}}
    ]}
    """#

    /// A real-looking piece of the live event stream, as the bytes arrive.
    static let stream = """
    : hi

    id: 1700000000:0
    data: [{"creationtime":"2026-11-22T18:00:00Z","data":[{"id":"l-sofa","id_v1":"/lights/1","on":{"on":false},"owner":{"rid":"d-sofa","rtype":"device"},"type":"light"}],"id":"e1","type":"update"}]

    id: 1700000001:0
    data: [{"creationtime":"2026-11-22T18:00:01Z","data":[{"id":"l-sofa","dimming":{"brightness":20.0},"type":"light"},{"id":"l-sofa","color_temperature":{"mirek":null,"mirek_valid":false},"color":{"xy":{"x":0.6,"y":0.3}},"type":"light"}],"id":"e2","type":"update"}]


    """
}
