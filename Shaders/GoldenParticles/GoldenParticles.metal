// Swirling golden particles. Driven by GoldenParticlesScene.swift.
#include "GraphistCommon.h"
using namespace graphist;

/// Must match GoldenParticlesScene.Particle (32 bytes).
struct GoldenParticle {
    float2 position;   // points
    float2 velocity;   // points / second
    float  age;        // seconds
    float  lifetime;   // seconds
    float  size;       // radius in points
    float  brightness; // 0...1
};

/// Must match GoldenParticlesScene.Uniforms (56 bytes).
struct GoldenUniforms {
    float2 viewSize;
    float2 pointer;
    float  time;
    float  deltaTime;
    float  pointerStrength;
    float  pointScale;      // pixels per point
    float  intensity;
    float  fadeAmount;
    float  exposure;
    uint   frameIndex;
    uint   particleCount;
    uint   reset;
};

// MARK: - Flow field

/// Smooth, time-varying scalar field. Its curl gives a divergence-free (swirly) flow.
static float flowPotential(float2 p, float t) {
    return sin(p.x * 1.7 + t) * cos(p.y * 1.3 - t * 0.7)
         + 0.5 * sin(p.y * 2.9 + t * 1.3 + p.x * 0.8) * cos(p.x * 3.1 - t)
         + 0.25 * sin(length(p) * 4.0 - t * 1.7);
}

static float2 curlNoise(float2 p, float t) {
    const float e = 0.01;
    float dx = flowPotential(p + float2(e, 0.0), t) - flowPotential(p - float2(e, 0.0), t);
    float dy = flowPotential(p + float2(0.0, e), t) - flowPotential(p - float2(0.0, e), t);
    return float2(dy, -dx) / (2.0 * e);
}

// MARK: - Simulation

kernel void golden_simulate(device GoldenParticle *particles [[buffer(0)]],
                            constant GoldenUniforms &u [[buffer(1)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= u.particleCount) { return; }
    GoldenParticle p = particles[id];

    float scale = min(u.viewSize.x, u.viewSize.y);
    float2 center = u.viewSize * 0.5;
    float dt = u.deltaTime;

    p.age += dt;
    if (u.reset != 0 || p.age >= p.lifetime) {
        uint seed = id * 9781u + u.frameIndex * 6271u + 1u;
        float angle = random01(seed) * 2.0 * M_PI_F;
        float radius = sqrt(random01(seed)) * 0.42 * scale;
        p.position = center + float2(cos(angle), sin(angle)) * radius;
        p.velocity = float2(0.0);
        p.lifetime = 3.0 + 6.0 * random01(seed);
        // On reset, stagger ages so particles don't all die at once.
        p.age = (u.reset != 0) ? random01(seed) * p.lifetime : 0.0;
        p.size = 0.5 + 1.5 * pow(random01(seed), 3.0); // mostly small, a few large
        p.brightness = 0.35 + 0.65 * random01(seed);
    }

    // Work in units of the canvas' short side so the motion is resolution independent.
    float2 q = (p.position - center) / scale;
    float r = max(length(q), 1e-4);
    float2 tangent = float2(-q.y, q.x) / r;

    float swirl = 0.55 * exp(-r * 2.5) + 0.08;                 // vortex, faster near the core
    float2 flow = curlNoise(q * 2.5, u.time * 0.12) * 0.06;    // organic eddies
    float2 pull = -(q / r) * smoothstep(0.30, 0.55, r) * 0.35; // keep the cloud on screen
    float2 target = (tangent * swirl + flow + pull) * scale;

    if (u.pointerStrength > 0.0) {
        float2 dp = (p.position - u.pointer) / scale;
        float pr = max(length(dp), 1e-3);
        float influence = exp(-pr * 6.0) * u.pointerStrength;
        float2 around = float2(dp.y, -dp.x) / pr;
        float2 toward = -dp / pr;
        target += (around * 1.2 + toward * 0.4) * influence * scale;
    }

    // Ease the velocity towards the field (gives the particles some inertia).
    p.velocity += (target - p.velocity) * (1.0 - exp(-dt * 2.5));
    p.position += p.velocity * dt;
    particles[id] = p;
}

// MARK: - Rendering into the accumulation texture

struct GoldenVertexOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float3 color;
};

vertex GoldenVertexOut golden_particle_vertex(const device GoldenParticle *particles [[buffer(0)]],
                                              constant GoldenUniforms &u [[buffer(1)]],
                                              uint vid [[vertex_id]]) {
    GoldenParticle p = particles[vid];

    float lifeT = saturate(p.age / max(p.lifetime, 1e-3));
    float fade = smoothstep(0.0, 0.15, lifeT) * (1.0 - smoothstep(0.6, 1.0, lifeT));

    // Faster / brighter particles run hotter: amber -> gold -> pale gold.
    float speed = length(p.velocity) / min(u.viewSize.x, u.viewSize.y);
    float heat = saturate(saturate(speed * 1.8) * 0.7 + p.brightness * 0.5 - 0.2);
    const float3 amber = float3(0.75, 0.30, 0.03);
    const float3 gold  = float3(1.00, 0.62, 0.12);
    const float3 pale  = float3(1.00, 0.86, 0.55);
    float3 color = heat < 0.5 ? mix(amber, gold, float3(heat * 2.0))
                               : mix(gold, pale, float3(heat * 2.0 - 1.0));

    // Sprites smaller than ~1.5px shimmer; draw them bigger but dimmer instead.
    float diameter = p.size * 2.0 * u.pointScale;
    float energy = 1.0;
    if (diameter < 1.5) {
        energy = (diameter * diameter) / 2.25;
        diameter = 1.5;
    }

    GoldenVertexOut out;
    out.position = float4(pointsToNDC(p.position, u.viewSize), 0.0, 1.0);
    out.pointSize = diameter * 2.0; // extra room for the soft halo
    out.color = color * (p.brightness * fade * energy * u.intensity);
    return out;
}

fragment float4 golden_particle_fragment(GoldenVertexOut in [[stage_in]],
                                         float2 pointCoord [[point_coord]]) {
    float d = length(pointCoord - 0.5) * 2.0; // 0 at center, 1 at sprite edge
    float glow = exp(-d * d * 5.0) * saturate(1.0 - d);
    return float4(in.color * glow, 0.0);       // additive
}

/// Blended as dst * (1 - alpha): fades the previous frames towards black (trails).
fragment float4 golden_fade_fragment(FullscreenVertexOut in [[stage_in]],
                                     constant GoldenUniforms &u [[buffer(0)]]) {
    return float4(0.0, 0.0, 0.0, u.fadeAmount);
}

// MARK: - Composite onto the drawable

fragment float4 golden_composite_fragment(FullscreenVertexOut in [[stage_in]],
                                          texture2d<float> accumulation [[texture(0)]],
                                          constant GoldenUniforms &u [[buffer(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float3 hdr = accumulation.sample(linearSampler, in.uv).rgb * u.exposure;
    float3 color = 1.0 - exp(-hdr); // simple exponential tone map; hot spots bloom to white
    return float4(color, 1.0);
}
