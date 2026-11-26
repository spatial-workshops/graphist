import AppKit
import MetalKit
import SwiftUI

/// SwiftUI wrapper around a Metal-backed view. Each instance (one per window)
/// gets its own `Renderer`, command queue and scene.
struct MetalCanvas: NSViewRepresentable {
    var sceneID: String
    var generation: Int
    var stats: RenderStats

    func makeCoordinator() -> Renderer {
        Renderer(stats: stats)
    }

    func makeNSView(context: Context) -> CanvasMTKView {
        let view = CanvasMTKView(frame: .zero, device: context.coordinator.device)
        context.coordinator.configure(view)
        context.coordinator.request(.init(sceneID: sceneID, generation: generation))
        return view
    }

    func updateNSView(_ nsView: CanvasMTKView, context: Context) {
        context.coordinator.request(.init(sceneID: sceneID, generation: generation))
    }

    static func dismantleNSView(_ nsView: CanvasMTKView, coordinator: Renderer) {
        nsView.isPaused = true
        nsView.delegate = nil
    }
}

/// MTKView subclass that tracks the mouse for scenes (see `FrameContext.pointer`).
/// Add keyboard handling here too if your scenes need it.
final class CanvasMTKView: MTKView {
    private(set) var pointer = PointerState()
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointer.isInside = true; updateLocation(event) }
    override func mouseExited(with event: NSEvent) { pointer.isInside = false }
    override func mouseMoved(with event: NSEvent) { updateLocation(event) }
    override func mouseDragged(with event: NSEvent) { updateLocation(event) }
    override func mouseDown(with event: NSEvent) { pointer.isPressed = true; updateLocation(event) }
    override func mouseUp(with event: NSEvent) { pointer.isPressed = false; updateLocation(event) }

    private func updateLocation(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? p.y : bounds.height - p.y
        pointer.location = SIMD2(Float(p.x), Float(y))
        pointer.isInside = bounds.contains(p)
    }
}
