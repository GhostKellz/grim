#version 450

// Vertex shader for GPU-accelerated text rendering
// Uses instanced rendering with glyph atlas

layout(location = 0) in vec2 in_position;  // Quad vertex position (0,0 to 1,1)
layout(location = 1) in vec2 in_tex_coord; // Atlas texture coordinates
layout(location = 2) in vec4 in_color;     // Text color (RGBA)

// Instance data (per-glyph)
layout(location = 3) in vec2 in_glyph_pos;    // Screen position (pixels)
layout(location = 4) in vec2 in_glyph_size;   // Glyph size (pixels)
layout(location = 5) in vec4 in_glyph_uv;     // Atlas UV (x, y, width, height)

layout(location = 0) out vec2 frag_tex_coord;
layout(location = 1) out vec4 frag_color;

// Uniform buffer (projection matrix)
layout(binding = 0) uniform UniformBufferObject {
    mat4 projection;
    vec2 viewport_size;
    float time;
    float padding;
} ubo;

void main() {
    // Calculate glyph quad position
    vec2 quad_pos = in_position * in_glyph_size + in_glyph_pos;

    // Transform to normalized device coordinates (NDC)
    vec2 ndc = (quad_pos / ubo.viewport_size) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y axis (Vulkan uses top-left origin)

    gl_Position = vec4(ndc, 0.0, 1.0);

    // Calculate texture coordinates from atlas UV
    frag_tex_coord = in_glyph_uv.xy + in_position * in_glyph_uv.zw;

    // Pass color to fragment shader
    frag_color = in_color;
}
