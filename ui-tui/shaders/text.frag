#version 450

// Fragment shader for GPU-accelerated text rendering
// Samples from glyph atlas texture

layout(location = 0) in vec2 frag_tex_coord;
layout(location = 1) in vec4 frag_color;

layout(location = 0) out vec4 out_color;

// Glyph atlas sampler
layout(binding = 1) uniform sampler2D atlas_sampler;

void main() {
    // Sample alpha from atlas (grayscale glyph)
    float alpha = texture(atlas_sampler, frag_tex_coord).r;

    // Apply text color with alpha
    out_color = vec4(frag_color.rgb, frag_color.a * alpha);

    // Discard fully transparent pixels (optimization)
    if (out_color.a < 0.01) {
        discard;
    }
}
