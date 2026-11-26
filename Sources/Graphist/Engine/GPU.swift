import Metal

/// Process-wide GPU objects shared by every window.
final class GPU {
    static let shared = GPU()

    let device: any MTLDevice
    private var cachedLibrary: ShaderLibrary?

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this Mac.")
        }
        self.device = device
    }

    /// The compiled shaders. When shaders are loaded from a live source directory
    /// (development), they are recompiled on every call so that reloading a scene
    /// (⌘R) picks up shader edits without restarting the app.
    func shaderLibrary() throws -> ShaderLibrary {
        if let cachedLibrary { return cachedLibrary }
        guard let source = ShaderLibrary.locateSource() else {
            throw ShaderLibraryError.noShadersFound
        }
        let library = try ShaderLibrary(device: device, source: source)
        if !source.isLive { cachedLibrary = library }
        return library
    }
}
