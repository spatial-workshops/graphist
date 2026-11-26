import Foundation
import Metal
import simd

/// Immediate-mode, GPU-instanced 2D shapes: circles, rectangles (optionally
/// rounded/rotated), and lines, filled or stroked, anti-aliased with signed
/// distance fields. Tens of thousands of shapes per frame are cheap because each
/// is a single 48-byte instance and everything is one draw call.
///
/// Usage, every frame:
///
///     shapes.circle(center: p, radius: 10, color: .gold)
///     shapes.line(from: a, to: b, width: 2, color: .white)
///     if let encoder = frame.makeDrawableEncoder() {
///         shapes.draw(in: encoder, frame: frame)   // flushes the queued shapes
///         encoder.endEncoding()
///     }
///
/// Coordinates are in points, origin top-left, y down. `draw` may be called
/// several times per frame (e.g. to interleave with other drawing).
final class ShapeRenderer {
    /// Must match `ShapeInstance` in Shaders/Toolkit/Shapes.metal.
    nonisolated struct Instance {
        var center: SIMD2<Float>
        var halfSize: SIMD2<Float>
        var color: SIMD4<Float>     // linear, straight alpha
        var rotation: Float         // radians, clockwise on screen
        var cornerRadius: Float
        var strokeWidth: Float      // 0 = filled
        var padding: Float = 0
    }

    /// Must match `ShapeUniforms` in Shapes.metal.
    private nonisolated struct Uniforms {
        var viewSize: SIMD2<Float>
        var pixelsPerPoint: Float
        var padding: Float = 0
    }

    private let device: any MTLDevice
    private let pipeline: any MTLRenderPipelineState
    private var instances: [Instance] = []
    private var buffers: [(any MTLBuffer)?]
    private var currentFrame: UInt64 = .max
    private var writeOffset = 0

    /// Number of shapes queued since the last `draw`.
    var pendingCount: Int { instances.count }

    init(context: SceneContext, pixelFormat: MTLPixelFormat? = nil, initialCapacity: Int = 1024) throws {
        assert(MemoryLayout<Instance>.stride == 48, "Instance layout must match Shapes.metal")
        device = context.device
        pipeline = try context.shaders.makeRenderPipeline(
            label: "Shapes",
            vertex: "shape_vertex",
            fragment: "shape_fragment",
            pixelFormat: pixelFormat ?? context.colorPixelFormat,
            blend: .premultipliedAlpha
        )
        buffers = Array(repeating: nil, count: context.maxFramesInFlight)
        instances.reserveCapacity(initialCapacity)
    }

    // MARK: Building shapes

    func add(_ instance: Instance) {
        instances.append(instance)
    }

    func circle(center: SIMD2<Float>, radius: Float, color: RGBA, strokeWidth: Float = 0) {
        add(Instance(
            center: center,
            halfSize: SIMD2(repeating: radius),
            color: color.linear,
            rotation: 0,
            cornerRadius: radius,
            strokeWidth: strokeWidth
        ))
    }

    func rect(
        center: SIMD2<Float>,
        size: SIMD2<Float>,
        rotation: Float = 0,
        cornerRadius: Float = 0,
        color: RGBA,
        strokeWidth: Float = 0
    ) {
        add(Instance(
            center: center,
            halfSize: size * 0.5,
            color: color.linear,
            rotation: rotation,
            cornerRadius: cornerRadius,
            strokeWidth: strokeWidth
        ))
    }

    func rect(origin: SIMD2<Float>, size: SIMD2<Float>, cornerRadius: Float = 0, color: RGBA, strokeWidth: Float = 0) {
        rect(center: origin + size * 0.5, size: size, cornerRadius: cornerRadius, color: color, strokeWidth: strokeWidth)
    }

    /// A line segment with round caps.
    func line(from start: SIMD2<Float>, to end: SIMD2<Float>, width: Float, color: RGBA) {
        let delta = end - start
        let length = simd_length(delta)
        add(Instance(
            center: (start + end) * 0.5,
            halfSize: SIMD2(length * 0.5 + width * 0.5, width * 0.5),
            color: color.linear,
            rotation: atan2(delta.y, delta.x),
            cornerRadius: width * 0.5,
            strokeWidth: 0
        ))
    }

    // MARK: Drawing

    /// Encodes all queued shapes into `encoder` and clears the queue.
    func draw(in encoder: any MTLRenderCommandEncoder, frame: FrameContext) {
        guard !instances.isEmpty else { return }
        if frame.frameIndex != currentFrame {
            currentFrame = frame.frameIndex
            writeOffset = 0
        }

        let slot = frame.inFlightIndex % buffers.count
        let byteCount = instances.count * MemoryLayout<Instance>.stride
        if buffers[slot] == nil || buffers[slot]!.length - writeOffset < byteCount {
            // Grow. Earlier draws this frame keep the old buffer alive (encoders retain it).
            let previous = buffers[slot]?.length ?? 0
            let length = max(64 * 1024, byteCount * 2, previous * 2)
            buffers[slot] = device.makeBuffer(length: length, options: [.storageModeShared, .cpuCacheModeWriteCombined])
            buffers[slot]?.label = "Shape Instances"
            writeOffset = 0
        }
        guard let buffer = buffers[slot] else { return }

        instances.withUnsafeBytes { bytes in
            (buffer.contents() + writeOffset).copyMemory(from: bytes.baseAddress!, byteCount: byteCount)
        }

        var uniforms = Uniforms(viewSize: frame.size.points, pixelsPerPoint: frame.size.scale)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: writeOffset, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)

        writeOffset += (byteCount + 255) & ~255
        instances.removeAll(keepingCapacity: true)
    }
}
