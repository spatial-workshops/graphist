// Shared helpers for all Graphist shaders. Include with: #include "GraphistCommon.h"
//
// Conventions
//  * Positions are in points, origin top-left, y down (matches the Swift side).
//  * Shaders output LINEAR color; the drawable is sRGB and encodes on write.
//  * Shader function names must be unique across all .metal files (they are
//    linked into one library). Use `static` for file-private helper functions.

#ifndef GRAPHIST_COMMON_H
#define GRAPHIST_COMMON_H

#include <metal_stdlib>
using namespace metal;

namespace graphist {

/// Converts a position in points (top-left origin, y down) to normalized device coordinates.
inline float2 pointsToNDC(float2 p, float2 viewSize) {
    return float2(p.x / viewSize.x * 2.0 - 1.0, 1.0 - p.y / viewSize.y * 2.0);
}

/// Rotates `p` by `angle` radians (clockwise on screen, since y points down).
inline float2 rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

/// PCG integer hash.
inline uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

/// Uniform random float in [0, 1). Advances `seed`.
inline float random01(thread uint &seed) {
    seed = pcgHash(seed);
    return float(seed >> 8) * (1.0 / 16777216.0);
}

inline float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92, c <= float3(0.04045));
}

/// Output of `graphist_fullscreen_vertex` (see Fullscreen.metal).
/// `uv` is (0,0) at the top-left and (1,1) at the bottom-right.
struct FullscreenVertexOut {
    float4 position [[position]];
    float2 uv;
};

} // namespace graphist

#endif // GRAPHIST_COMMON_H
