import Foundation
import Metal
import simd

// MARK: - The scene protocol

/// A self-contained piece of 2D graphics rendered into a window's Metal canvas.
///
/// To add new graphics:
///   1. Create a type conforming to `GraphicsScene` (see `Scenes/` for examples).
///   2. Put any shaders it needs in `Shaders/<YourScene>/` (any `.metal` file there is
///      compiled automatically; function names must be unique across all shaders).
///   3. Register the type in `SceneCatalog.all`.
///
/// Each window owns its own scene instance, so scenes may keep whatever mutable state
/// they like. All methods are called on the main thread.
protocol GraphicsScene: AnyObject {
    /// Name shown in the window's scene picker.
    static var title: String { get }

    /// Create pipelines, buffers, etc. Throwing shows the error in the window.
    init(context: SceneContext) throws

    /// Called before the first frame and whenever the canvas size changes.
    /// Re-create size-dependent resources (offscreen textures, ...) here.
    func resize(to size: CanvasSize)

    /// Encode one frame. The scene MUST render into the drawable, normally via
    /// `frame.makeDrawableEncoder()`. It may encode any number of compute or
    /// offscreen passes on `frame.commandBuffer` first.
    func render(frame: FrameContext)
}

extension GraphicsScene {
    func resize(to size: CanvasSize) {}
}

nonisolated enum SceneError: LocalizedError {
    case resourceCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .resourceCreationFailed(let what): "Could not create \(what)."
        }
    }
}

// MARK: - Context types

/// Everything a scene needs to set itself up.
struct SceneContext {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let shaders: ShaderLibrary
    /// Pixel format of the window's drawable.
    let colorPixelFormat: MTLPixelFormat
    /// Number of frames the CPU may run ahead of the GPU. Per-frame CPU-written
    /// buffers need this many copies (see `ShapeRenderer` for an example).
    let maxFramesInFlight: Int
}

/// Canvas dimensions. Coordinates used throughout Graphist are in *points*
/// with the origin at the top-left and y pointing down (like SwiftUI).
nonisolated struct CanvasSize: Equatable {
    /// Size in points.
    var points: SIMD2<Float>
    /// Size of the drawable in pixels.
    var pixels: SIMD2<Float>
    /// Pixels per point (2 on Retina displays).
    var scale: Float
}

/// Mouse state for the canvas, in points (top-left origin).
nonisolated struct PointerState: Equatable {
    var location: SIMD2<Float> = .zero
    var isInside = false
    var isPressed = false
}

/// Per-frame information handed to `GraphicsScene.render(frame:)`.
struct FrameContext {
    let commandBuffer: any MTLCommandBuffer
    /// Render pass targeting this frame's drawable.
    let drawablePass: MTLRenderPassDescriptor
    let size: CanvasSize
    /// Seconds since the scene was created.
    let time: Double
    /// Seconds since the previous frame (clamped to avoid huge jumps after stalls).
    let deltaTime: Float
    /// Monotonic frame counter (resets when the scene is (re)loaded).
    let frameIndex: UInt64
    /// Index in `0..<maxFramesInFlight` identifying which copy of per-frame
    /// CPU-written resources is safe to overwrite this frame.
    let inFlightIndex: Int
    let pointer: PointerState

    /// Creates a render encoder targeting the window's drawable.
    /// - Parameters:
    ///   - loadAction: `.clear` (default) fills with `clearColor`; use `.dontCare` when
    ///     the pass overwrites every pixel and `.load` for a second pass onto the drawable.
    func makeDrawableEncoder(
        loadAction: MTLLoadAction = .clear,
        clearColor: RGBA = .black,
        label: String = "Drawable Pass"
    ) -> (any MTLRenderCommandEncoder)? {
        let attachment = drawablePass.colorAttachments[0]!
        attachment.loadAction = loadAction
        attachment.clearColor = clearColor.clearColor
        attachment.storeAction = .store
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: drawablePass)
        encoder?.label = label
        return encoder
    }
}
