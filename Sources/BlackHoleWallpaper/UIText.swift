import Foundation

/// Texts of the glTF import. Computed, so they follow a language change.
enum UIText {
    // glTF import
    static var pickModel: String { L("3D-Modell wählen: OBJ, USDZ, USD, PLY, STL, glTF oder GLB") }
    static var gltfUnreadable: String { L("Die glTF-Datei lässt sich nicht lesen.") }
    static func gltfBadJSON(_ why: String) -> String { L("Die glTF-Datei ist kein gültiges JSON: %@", why) }
    static func gltfVersion(_ v: String) -> String { L("glTF %@ wird nicht unterstützt, nur Version 2.", v) }
    static func gltfExtension(_ names: [String]) -> String {
        let list = names.joined(separator: ", ")
        return names.count == 1
            ? L("Das Modell braucht die Erweiterung %@. Die kann die App nicht lesen. Exportiere es ohne Kompression, etwa ohne Draco.", list)
            : L("Das Modell braucht die Erweiterungen %@. Die kann die App nicht lesen. Exportiere es ohne Kompression, etwa ohne Draco.", list)
    }
    static func gltfMissingBuffer(_ name: String) -> String { L("Die Datei %@ fehlt, sie gehört zum Modell.", name) }
    static var gltfBrokenData: String { L("Die Daten im Modell passen nicht zusammen (Accessor außerhalb des Puffers).") }
    static var gltfNoTriangles: String { L("Im Modell sind keine Dreiecke.") }
}
