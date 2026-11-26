// A single full-screen fragment shader. Edit freely: run with `make dev`,
// change this file, then press ⌘R in the window to recompile.
#include "GraphistCommon.h"
using namespace graphist;

/// Must match ShaderPlaygroundScene.Uniforms.
struct PlaygroundUniforms {
    float2 viewSize;
    float2 pointer;
    float  time;
    float  _padding;
};

fragment float4 playground_fragment(FullscreenVertexOut in [[stage_in]],
                                    constant PlaygroundUniforms &u [[buffer(0)]]) {
    float aspect = u.viewSize.x / u.viewSize.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0);
    float t = u.time * 0.4;

    float v = sin(p.x * 6.0 + t)
            + sin(p.y * 7.0 - t * 1.3)
            + sin((p.x + p.y) * 5.0 + t * 0.7)
            + sin(length(p) * 9.0 - t * 2.0);
    float3 color = 0.5 + 0.5 * cos(v * 0.8 + float3(0.0, 2.1, 4.2) + t);

    // Soft spotlight around the mouse.
    float2 mouse = (u.pointer / u.viewSize - 0.5) * float2(aspect, 1.0);
    color *= 0.55 + 0.45 * exp(-length(p - mouse) * 4.0);

    return float4(srgbToLinear(color), 1.0);
}
