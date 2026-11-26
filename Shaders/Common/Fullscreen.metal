#include "GraphistCommon.h"
using namespace graphist;

/// Draw with `drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)` to
/// cover the whole render target with a single triangle. Pair with any fragment
/// function taking `FullscreenVertexOut [[stage_in]]`.
vertex FullscreenVertexOut graphist_fullscreen_vertex(uint vid [[vertex_id]]) {
    // (-1,-1), (3,-1), (-1,3)
    float2 position = float2(float((vid << 1) & 2u), float(vid & 2u)) * 2.0 - 1.0;
    FullscreenVertexOut out;
    out.position = float4(position, 0.0, 1.0);
    out.uv = float2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
    return out;
}
