import Foundation
import MetalKit
import QuartzCore

/// Drives one window's Metal canvas: owns the command queue, frame pacing,
/// timing and the active `GraphicsScene`.
final class Renderer: NSObject {
    /// Triple buffering: the CPU may encode up to this many frames ahead of the GPU.
    static let maxFramesInFlight = 3

    nonisolated struct SceneRequest: Equatable {
        var sceneID: String
        /// Bumped to force a reload of the same scene (⌘R).
        var generation: Int
    }

    let device: any MTLDevice
    private let stats: RenderStats
    private let commandQueue: any MTLCommandQueue
    private let frameSemaphore = DispatchSemaphore(value: Renderer.maxFramesInFlight)

    private var scene: (any GraphicsScene)?
    private var pendingRequest: SceneRequest?
    private var loadedRequest: SceneRequest?
    private var canvasSize: CanvasSize?

    private var sceneStartTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval?
    private var frameIndex: UInt64 = 0
    private var inFlightIndex = 0

    private var statsWindowStart: CFTimeInterval = 0
    private var statsFrameCount = 0

    init(stats: RenderStats) {
        let device = GPU.shared.device
        self.stats = stats
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create a Metal command queue.")
        }
        queue.label = "Graphist Window Queue"
        self.commandQueue = queue
        super.init()
    }

    func configure(_ view: CanvasMTKView) {
        view.device = device
        // Scenes output linear color; the sRGB drawable encodes it for display.
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = true
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = 120 // ProMotion; capped to the display's rate
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = self
    }

    /// Asks for a scene. Applied at the start of the next frame (never during a
    /// SwiftUI view update).
    func request(_ request: SceneRequest) {
        pendingRequest = request
    }

    private func loadSceneIfNeeded(view: MTKView) {
        guard let request = pendingRequest, request != loadedRequest else { return }
        loadedRequest = request
        scene = nil

        guard let entry = SceneCatalog.entry(id: request.sceneID) else {
            stats.errorMessage = "Unknown scene '\(request.sceneID)'."
            return
        }
        do {
            let shaders = try GPU.shared.shaderLibrary()
            let context = SceneContext(
                device: device,
                commandQueue: commandQueue,
                shaders: shaders,
                colorPixelFormat: view.colorPixelFormat,
                maxFramesInFlight: Self.maxFramesInFlight
            )
            let newScene = try entry.type.init(context: context)
            if let canvasSize { newScene.resize(to: canvasSize) }
            scene = newScene
            sceneStartTime = CACurrentMediaTime()
            lastFrameTime = nil
            frameIndex = 0
            stats.shaderSource = shaders.source.description
            stats.errorMessage = nil
        } catch {
            stats.errorMessage = "\(entry.title): \(error.localizedDescription)"
        }
    }

    private func currentSize(of view: MTKView) -> CanvasSize {
        let points = SIMD2(Float(view.bounds.width), Float(view.bounds.height))
        let pixels = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let scale = points.x > 0 ? pixels.x / points.x : 1
        return CanvasSize(points: points, pixels: pixels, scale: scale)
    }

    /// Built in a nonisolated context so the closure carries no main-actor
    /// isolation: Metal calls it on an internal thread.
    private nonisolated static func makeCompletionHandler(
        signaling semaphore: DispatchSemaphore
    ) -> MTLCommandBufferHandler {
        { _ in semaphore.signal() }
    }

    private func updateStats(now: CFTimeInterval) {
        statsFrameCount += 1
        let elapsed = now - statsWindowStart
        guard elapsed >= 0.5 else { return }
        stats.framesPerSecond = Double(statsFrameCount) / elapsed
        stats.frameTimeMilliseconds = elapsed * 1000 / Double(statsFrameCount)
        statsWindowStart = now
        statsFrameCount = 0
    }
}

extension Renderer: @preconcurrency MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Size changes are detected in draw(in:) so the scene always sees a
        // consistent points/pixels pair.
    }

    func draw(in view: MTKView) {
        loadSceneIfNeeded(view: view)

        let size = currentSize(of: view)
        guard size.pixels.x >= 1, size.pixels.y >= 1 else { return }
        if size != canvasSize {
            canvasSize = size
            scene?.resize(to: size)
            stats.resolution = "\(Int(size.pixels.x))×\(Int(size.pixels.y)) px @\(size.scale)x"
        }

        frameSemaphore.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameSemaphore.signal()
            return
        }
        commandBuffer.label = "Graphist Frame"
        commandBuffer.addCompletedHandler(Self.makeCompletionHandler(signaling: frameSemaphore))

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else {
            commandBuffer.commit() // still signals the semaphore
            return
        }

        let now = CACurrentMediaTime()
        let deltaTime: Float
        if let lastFrameTime {
            deltaTime = Float(min(max(now - lastFrameTime, 0), 1.0 / 15.0))
        } else {
            deltaTime = 1.0 / 60.0
        }
        lastFrameTime = now

        if let scene {
            let frame = FrameContext(
                commandBuffer: commandBuffer,
                drawablePass: pass,
                size: size,
                time: now - sceneStartTime,
                deltaTime: deltaTime,
                frameIndex: frameIndex,
                inFlightIndex: inFlightIndex,
                pointer: (view as? CanvasMTKView)?.pointer ?? PointerState()
            )
            scene.render(frame: frame)
        } else {
            // No scene (e.g. it failed to load): just clear to black.
            pass.colorAttachments[0].loadAction = .clear
            commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()

        frameIndex &+= 1
        inFlightIndex = (inFlightIndex + 1) % Self.maxFramesInFlight
        updateStats(now: now)
    }
}
