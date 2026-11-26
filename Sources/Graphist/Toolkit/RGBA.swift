import Foundation
import Metal
import simd

/// A color with sRGB components in 0...1 (the values you'd pick in a color picker).
/// Converted to linear for the GPU via `linear`, since Graphist renders into an
/// sRGB drawable and blends in linear space.
nonisolated struct RGBA: Hashable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `RGBA(hex: 0xFFC845)`
    init(hex: UInt32, alpha: Float = 1) {
        self.init(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255,
            alpha
        )
    }

    /// Hue, saturation and brightness in 0...1 (hue wraps).
    init(hue: Float, saturation: Float, brightness: Float, alpha: Float = 1) {
        let h = (hue - hue.rounded(.down)) * 6
        let sector = Int(h) % 6
        let f = h - Float(Int(h))
        let v = brightness
        let p = v * (1 - saturation)
        let q = v * (1 - saturation * f)
        let t = v * (1 - saturation * (1 - f))
        switch sector {
        case 0: self.init(v, t, p, alpha)
        case 1: self.init(q, v, p, alpha)
        case 2: self.init(p, v, t, alpha)
        case 3: self.init(p, q, v, alpha)
        case 4: self.init(t, p, v, alpha)
        default: self.init(v, p, q, alpha)
        }
    }

    func withAlpha(_ alpha: Float) -> RGBA {
        RGBA(red, green, blue, alpha)
    }

    /// Linear-light components (straight alpha) for shaders.
    var linear: SIMD4<Float> {
        SIMD4(Self.toLinear(red), Self.toLinear(green), Self.toLinear(blue), alpha)
    }

    var clearColor: MTLClearColor {
        let c = linear
        return MTLClearColor(red: Double(c.x), green: Double(c.y), blue: Double(c.z), alpha: Double(c.w))
    }

    private static func toLinear(_ c: Float) -> Float {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static let black = RGBA(0, 0, 0)
    static let white = RGBA(1, 1, 1)
    static let clear = RGBA(0, 0, 0, 0)
    static let gold = RGBA(hex: 0xFFC845)
}
