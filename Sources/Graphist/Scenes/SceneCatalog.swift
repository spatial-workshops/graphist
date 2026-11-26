/// The scenes offered in each window's scene picker.
/// Add your own `GraphicsScene` type here; the first entry is the default for new windows.
enum SceneCatalog {
    static let all: [SceneEntry] = [
        SceneEntry(GoldenParticlesScene.self),
        SceneEntry(OrbitsScene.self),
        SceneEntry(ShaderPlaygroundScene.self),
    ]

    static var defaultID: String { all[0].id }

    static func entry(id: String) -> SceneEntry? {
        all.first { $0.id == id }
    }
}

struct SceneEntry {
    let id: String
    let title: String
    let type: any GraphicsScene.Type

    init(_ type: any GraphicsScene.Type) {
        self.id = String(describing: type)
        self.title = type.title
        self.type = type
    }
}
