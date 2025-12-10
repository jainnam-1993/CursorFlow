#include <metal_stdlib>
using namespace metal;

struct TrailVertex {
    float2 position;
    float4 color;  // RGBA
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

struct Uniforms {
    float2 screenSize;
    float pointSize;
    float time;
};

// Vertex shader for trail points
vertex VertexOut trailVertex(
    const device TrailVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;

    // Convert from screen coordinates to normalized device coordinates (-1 to 1)
    float2 pos = vertices[vid].position;
    float2 ndc = (pos / uniforms.screenSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;  // Flip Y for Metal coordinate system

    out.position = float4(ndc, 0.0, 1.0);
    out.color = vertices[vid].color;
    out.pointSize = uniforms.pointSize;

    return out;
}

// Fragment shader for trail points - creates soft circular points
fragment float4 trailFragment(
    VertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // Create soft circular point
    float2 center = pointCoord - 0.5;
    float dist = length(center) * 2.0;

    // Soft edge falloff
    float alpha = 1.0 - smoothstep(0.5, 1.0, dist);

    // Apply vertex alpha
    alpha *= in.color.a;

    // Discard fully transparent pixels
    if (alpha < 0.01) {
        discard_fragment();
    }

    return float4(in.color.rgb, alpha);
}

// Alternative: Line-based trail rendering
struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex LineVertexOut trailLineVertex(
    const device TrailVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    LineVertexOut out;

    float2 pos = vertices[vid].position;
    float2 ndc = (pos / uniforms.screenSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    out.position = float4(ndc, 0.0, 1.0);
    out.color = vertices[vid].color;

    return out;
}

fragment float4 trailLineFragment(LineVertexOut in [[stage_in]]) {
    return in.color;
}
