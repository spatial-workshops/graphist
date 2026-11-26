import Foundation
import Metal
import simd

/// Swirling golden particles on black — the default scene for new windows.
///
/// Each frame:
///   1. A compute kernel advances every particle through a swirling flow field
///      (a central vortex + curl noise + a soft pull that keeps them on screen).
///   2. Into an HDR (rgba16Float) accumulation texture, the previous contents are
///      faded towards black and the particles are drawn additively as soft points.
///      The fade is what produces the light trails.
///   3. The accumulation texture is tone-mapped onto the window's drawable.
///
/// Click and drag to stir the particles. Shaders: Shaders/GoldenParticles/.
final class GoldenParticlesScene: GraphicsScene {
    static let title = "Golden Particles"

    // MARK: Tunables
    static let particleCount = 150_000
    /// Higher = shorter trails.
    static let trailFadeRate: Float = 4.5
    /// Brightness contributed by one particle (at 60 fps; scaled for other rates).
    static let intensity: Float = 0.035
    static let exposure: Float = 1.8
    /// Influence of the mouse when hovering (pressing = 1).
    static let hoverStrength: Float = 0.25

    /// Must match `GoldenParticle` in GoldenParticles.metal (32 bytes).
    private nonisolated struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var age: Float
        var lifetime: Float
        var size: Float
        var brightness: Float
    }

    /// Must match `GoldenUniforms` in GoldenParticles.metal.
    private nonisolated struct Uniforms {
        var viewSize: SIMD2<Float>
        var pointer: SIMD2<Float>
        var time: Float
        var deltaTime: Float
        var pointerStrength: Float
        var pointScale: Float
        var intensity: Float
        var fadeAmount: Float
        var exposure: Float
        var frameIndex: UInt32
        var particleCount: UInt32
        var reset: UInt32
    }

    private let device: any MTLDevice
    private let particles: any MTLBuffer
    private let simulatePipeline: any MTLComputePipelineState
    private let fadePipeline: any MTLRenderPipelineState
    private let particlePipeline: any MTLRenderPipelineState
    private let compositePipeline: any MTLRenderPipelineState
    private var accumulation: (any MTLTexture)?
    private var accumulationNeedsClear = true
    private var needsReset = true

    init(context: SceneContext) throws {
        assert(MemoryLayout<Particle>.stride == 32)
        assert(MemoryLayout<Uniforms>.stride == 56)
        let device = context.device
        self.device = device

        // GPU-only memory: particles are initialised and updated by the compute kernel.
        let length = MemoryLayout<Particle>.stride * Self.particleCount
        guard let buffer = device.makeBuffer(length: length, options: .storageModePrivate) else {
            throw SceneError.resourceCreationFailed("particle buffer")
        }
        buffer.label = "Golden Particles"
        particles = buffer

        let shaders = context.shaders
        simulatePipeline = try shaders.makeComputePipeline("golden_simulate")

        // Multiplies the existing image by (1 - fadeAmount): dst = dst * (1 - srcAlpha).
        fadePipeline = try shaders.makeRenderPipeline(
            label: "Golden Fade",
            vertex: "graphist_fullscreen_vertex",
            fragment: "golden_fade_fragment",
            pixelFormat: .rgba16Float
        ) { descriptor in
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .zero
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .zero
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        particlePipeline = try shaders.makeRenderPipeline(
            label: "Golden Particles",
            vertex: "golden_particle_vertex",
            fragment: "golden_particle_fragment",
            pixelFormat: .rgba16Float,
            blend: .additive
        ) { descriptor in
            descriptor.inputPrimitiveTopology = .point
        }

        compositePipeline = try shaders.makeRenderPipeline(
            label: "Golden Composite",
            vertex: "graphist_fullscreen_vertex",
            fragment: "golden_composite_fragment",
            pixelFormat: context.colorPixelFormat
        )
    }

    func resize(to size: CanvasSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(Int(size.pixels.x), 1),
            height: max(Int(size.pixels.y), 1),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        accumulation = device.makeTexture(descriptor: descriptor)
        accumulation?.label = "Golden Accumulation"
        accumulationNeedsClear = true
    }

    func render(frame: FrameContext) {
        guard let accumulation else {
            frame.makeDrawableEncoder()?.endEncoding()
            return
        }
        let commandBuffer = frame.commandBuffer
        let dt = frame.deltaTime

        let pointerStrength: Float = frame.pointer.isPressed ? 1 : (frame.pointer.isInside ? Self.hoverStrength : 0)
        var uniforms = Uniforms(
            viewSize: frame.size.points,
            pointer: frame.pointer.location,
            time: Float(frame.time),
            deltaTime: dt,
            pointerStrength: pointerStrength,
            pointScale: frame.size.scale,
            intensity: Self.intensity * dt * 60, // frame-rate independent brightness
            fadeAmount: 1 - exp(-dt * Self.trailFadeRate),
            exposure: Self.exposure,
            frameIndex: UInt32(truncatingIfNeeded: frame.frameIndex),
            particleCount: UInt32(Self.particleCount),
            reset: needsReset ? 1 : 0
        )
        needsReset = false
        let uniformsLength = MemoryLayout<Uniforms>.stride

        // 1. Simulate.
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.label = "Golden Simulate"
            compute.setComputePipelineState(simulatePipeline)
            compute.setBuffer(particles, offset: 0, index: 0)
            compute.setBytes(&uniforms, length: uniformsLength, index: 1)
            let width = min(simulatePipeline.threadExecutionWidth * 4, simulatePipeline.maxTotalThreadsPerThreadgroup)
            compute.dispatchThreads(
                MTLSize(width: Self.particleCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
            )
            compute.endEncoding()
        }

        // 2. Fade previous frame and add particles into the accumulation texture.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = accumulation
        pass.colorAttachments[0].loadAction = accumulationNeedsClear ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        accumulationNeedsClear = false
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.label = "Golden Accumulate"
            encoder.setRenderPipelineState(fadePipeline)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            encoder.setRenderPipelineState(particlePipeline)
            encoder.setVertexBuffer(particles, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: uniformsLength, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Self.particleCount)
            encoder.endEncoding()
        }

        // 3. Tone-map onto the drawable (overwrites every pixel, so no clear needed).
        if let encoder = frame.makeDrawableEncoder(loadAction: .dontCare, label: "Golden Composite") {
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentTexture(accumulation, index: 0)
            encoder.setFragmentBytes(&uniforms, length: uniformsLength, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
    }
}
