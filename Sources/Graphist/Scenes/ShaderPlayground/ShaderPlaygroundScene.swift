import Foundation
import Metal
import simd

/// The smallest possible custom-shader scene: one full-screen fragment shader.
/// Copy this file + Shaders/ShaderPlayground/ShaderPlayground.metal as a starting
/// point for new effects.
final class ShaderPlaygroundScene: GraphicsScene {
    static let title = "Shader Playground"

    /// Must match `PlaygroundUniforms` in ShaderPlayground.metal.
    private nonisolated struct Uniforms {
        var viewSize: SIMD2<Float>
        var pointer: SIMD2<Float>
        var time: Float
        var padding: Float = 0
    }

    private let pipeline: any MTLRenderPipelineState

    init(context: SceneContext) throws {
        pipeline = try context.shaders.makeRenderPipeline(
            label: "Playground",
            vertex: "graphist_fullscreen_vertex",
            fragment: "playground_fragment",
            pixelFormat: context.colorPixelFormat
        )
    }

    func render(frame: FrameContext) {
        var uniforms = Uniforms(
            viewSize: frame.size.points,
            pointer: frame.pointer.location,
            time: Float(frame.time)
        )
        guard let encoder = frame.makeDrawableEncoder(loadAction: .dontCare) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
