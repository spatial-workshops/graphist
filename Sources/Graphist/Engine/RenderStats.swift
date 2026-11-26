import Foundation
import Observation

/// Per-window rendering information surfaced to SwiftUI. Updated a few times
/// per second (not every frame) to keep SwiftUI work negligible.
@Observable
final class RenderStats {
    var framesPerSecond: Double = 0
    var frameTimeMilliseconds: Double = 0
    var resolution: String = ""
    var shaderSource: String = ""
    var errorMessage: String?
}
