import Foundation
import Metal
import simd

/// Example of drawing with the high-level `ShapeRenderer` API — no custom shaders
/// needed. Rings of orbiting dots, rotating squares and a sweeping arm.
final class OrbitsScene: GraphicsScene {
    static let title = "Orbits (Shapes API)"

    private let shapes: ShapeRenderer
    private let background = RGBA(hex: 0x07080D)

    init(context: SceneContext) throws {
        shapes = try ShapeRenderer(context: context)
    }

    func render(frame: FrameContext) {
        let t = Float(frame.time)
        let size = frame.size.points
        let center = size * 0.5
        let unit = min(size.x, size.y)

        // Frame
        shapes.rect(
            center: center,
            size: size - 40,
            cornerRadius: 24,
            color: RGBA(hex: 0x262C40),
            strokeWidth: 1.5
        )

        // Rings of dots
        let ringCount = 7
        for ring in 0..<ringCount {
            let radius = unit * (0.08 + 0.055 * Float(ring))
            let dotCount = 5 + ring * 4
            let direction: Float = ring.isMultiple(of: 2) ? 1 : -1
            let speed = direction * (0.6 / Float(ring + 1) + 0.1)
            let hue = 0.55 + Float(ring) * 0.06

            shapes.circle(
                center: center,
                radius: radius,
                color: RGBA(hue: hue, saturation: 0.5, brightness: 0.4, alpha: 0.5),
                strokeWidth: 1
            )
            let dotColor = RGBA(hue: hue, saturation: 0.7, brightness: 1)
            for i in 0..<dotCount {
                let phase = Float(i) / Float(dotCount) * (2 * Float.pi)
                let angle = phase + t * speed
                let position = center + SIMD2(cos(angle), sin(angle)) * radius
                let pulse = 0.5 + 0.5 * sin(t * 2 + Float(i) + Float(ring))
                shapes.circle(center: position, radius: 2.5 + 2.5 * pulse, color: dotColor)
            }
        }

        // Rotating squares in the middle
        for k in 0..<3 {
            let side = unit * 0.06 + Float(k) * 12
            shapes.rect(
                center: center,
                size: SIMD2(repeating: side),
                rotation: t * (0.7 + Float(k) * 0.3),
                cornerRadius: 4,
                color: RGBA.gold.withAlpha(0.9 - Float(k) * 0.25),
                strokeWidth: 2
            )
        }

        // Sweeping arm
        let armAngle = t * 0.5
        let armEnd = center + SIMD2(cos(armAngle), sin(armAngle)) * unit * 0.45
        shapes.line(from: center, to: armEnd, width: 2, color: RGBA.gold.withAlpha(0.8))
        shapes.circle(center: armEnd, radius: 6, color: .gold)

        // Pointer
        if frame.pointer.isInside {
            let p = frame.pointer.location
            shapes.line(from: center, to: p, width: 1, color: RGBA.white.withAlpha(0.25))
            shapes.circle(
                center: p,
                radius: frame.pointer.isPressed ? 28 : 18,
                color: RGBA.white.withAlpha(0.9),
                strokeWidth: 2
            )
        }

        guard let encoder = frame.makeDrawableEncoder(clearColor: background) else { return }
        shapes.draw(in: encoder, frame: frame)
        encoder.endEncoding()
    }
}
