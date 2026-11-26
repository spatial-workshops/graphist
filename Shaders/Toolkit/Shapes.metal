// Instanced SDF shapes used by ShapeRenderer.swift.
#include "GraphistCommon.h"
using namespace graphist;

/// Must match ShapeRenderer.Instance (48 bytes).
struct ShapeInstance {
    float2 center;
    float2 halfSize;
    float4 color;        // linear, straight alpha
    float  rotation;
    float  cornerRadius;
    float  strokeWidth;  // 0 = filled
    float  _padding;
};

/// Must match ShapeRenderer.Uniforms.
struct ShapeUniforms {
    float2 viewSize;
    float  pixelsPerPoint;
    float  _padding;
};

struct ShapeVertexOut {
    float4 position [[position]];
    float2 local;                         // position relative to the shape's center, unrotated
    float2 halfSize      [[flat]];
    float4 color         [[flat]];
    float  cornerRadius  [[flat]];
    float  strokeWidth   [[flat]];
};

vertex ShapeVertexOut shape_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   const device ShapeInstance *instances [[buffer(0)]],
                                   constant ShapeUniforms &u [[buffer(1)]]) {
    ShapeInstance s = instances[iid];
    float2 corner = float2(float(vid & 1u), float((vid >> 1) & 1u)) * 2.0 - 1.0;
    // Expand the quad slightly so the anti-aliased edge isn't clipped.
    float margin = 1.5 / u.pixelsPerPoint;
    float2 local = corner * (s.halfSize + margin);
    float2 world = s.center + rotate2D(local, s.rotation);

    ShapeVertexOut out;
    out.position = float4(pointsToNDC(world, u.viewSize), 0.0, 1.0);
    out.local = local;
    out.halfSize = s.halfSize;
    out.color = s.color;
    out.cornerRadius = s.cornerRadius;
    out.strokeWidth = s.strokeWidth;
    return out;
}

fragment float4 shape_fragment(ShapeVertexOut in [[stage_in]],
                               constant ShapeUniforms &u [[buffer(0)]]) {
    // Signed distance to a rounded box, in points.
    float r = min(in.cornerRadius, min(in.halfSize.x, in.halfSize.y));
    float2 q = abs(in.local) - in.halfSize + r;
    float d = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
    if (in.strokeWidth > 0.0) {
        // Stroke sits inside the shape's outline.
        d = abs(d + in.strokeWidth * 0.5) - in.strokeWidth * 0.5;
    }
    float coverage = saturate(0.5 - d * u.pixelsPerPoint);
    float alpha = in.color.a * coverage;
    return float4(in.color.rgb * alpha, alpha); // premultiplied
}
