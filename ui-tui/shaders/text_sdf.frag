#version 450

// SDF (Signed Distance Field) fragment shader for ultra-sharp text
// Provides crisp text at any zoom level with subpixel rendering

layout(location = 0) in vec2 frag_tex_coord;
layout(location = 1) in vec4 frag_color;

layout(location = 0) out vec4 out_color;

// SDF atlas sampler (signed distance field)
layout(binding = 1) uniform sampler2D sdf_atlas;

// Uniform buffer for SDF parameters
layout(binding = 2) uniform SDFParams {
    float distance_range;   // Distance range in pixels (default: 4.0)
    float edge_softness;    // Edge smoothing (0.0 = sharp, 1.0 = soft)
    float outline_width;    // Outline width (0.0 = no outline)
    vec4 outline_color;     // Outline color
    float shadow_offset_x;  // Shadow offset X
    float shadow_offset_y;  // Shadow offset Y
    float shadow_softness;  // Shadow blur
    vec4 shadow_color;      // Shadow color
    vec3 subpixel_offset;   // RGB subpixel offsets for LCD rendering
    float padding;
} sdf_params;

// Median of 3 values (for multi-channel SDF)
float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

// Sample SDF distance
float sampleSDF(vec2 uv) {
    // For multi-channel SDF (better quality)
    vec3 sample = texture(sdf_atlas, uv).rgb;
    return median(sample.r, sample.g, sample.b);
}

// Convert distance to alpha with anti-aliasing
float distanceToAlpha(float distance) {
    // Scale distance to pixel units
    float pixel_dist = distance * sdf_params.distance_range;

    // Apply smoothing for anti-aliasing
    float alpha = smoothstep(-sdf_params.edge_softness, sdf_params.edge_softness, pixel_dist);

    return alpha;
}

// Subpixel rendering for LCD displays
vec4 subpixelRender(vec2 uv) {
    // Sample SDF at RGB subpixel offsets
    vec2 pixel_size = 1.0 / textureSize(sdf_atlas, 0);

    float r = sampleSDF(uv + vec2(sdf_params.subpixel_offset.r * pixel_size.x, 0.0));
    float g = sampleSDF(uv + vec2(sdf_params.subpixel_offset.g * pixel_size.x, 0.0));
    float b = sampleSDF(uv + vec2(sdf_params.subpixel_offset.b * pixel_size.x, 0.0));

    // Convert distances to alpha
    vec3 alpha_rgb = vec3(
        distanceToAlpha(r - 0.5),
        distanceToAlpha(g - 0.5),
        distanceToAlpha(b - 0.5)
    );

    // Apply color with subpixel alpha
    return vec4(frag_color.rgb * alpha_rgb, (alpha_rgb.r + alpha_rgb.g + alpha_rgb.b) / 3.0);
}

void main() {
    // Sample SDF distance
    float distance = sampleSDF(frag_tex_coord) - 0.5;

    // Shadow rendering (if enabled)
    vec4 shadow = vec4(0.0);
    if (sdf_params.shadow_softness > 0.0) {
        vec2 shadow_uv = frag_tex_coord + vec2(sdf_params.shadow_offset_x, sdf_params.shadow_offset_y) / textureSize(sdf_atlas, 0);
        float shadow_dist = sampleSDF(shadow_uv) - 0.5;
        float shadow_alpha = smoothstep(-sdf_params.shadow_softness, sdf_params.shadow_softness, shadow_dist);
        shadow = sdf_params.shadow_color * shadow_alpha;
    }

    // Outline rendering (if enabled)
    vec4 outline = vec4(0.0);
    if (sdf_params.outline_width > 0.0) {
        float outline_dist = abs(distance) - sdf_params.outline_width;
        float outline_alpha = 1.0 - smoothstep(-sdf_params.edge_softness, sdf_params.edge_softness, outline_dist);
        outline = sdf_params.outline_color * outline_alpha;
    }

    // Main glyph rendering
    vec4 glyph;
    if (sdf_params.subpixel_offset.r != 0.0) {
        // Subpixel rendering for LCD
        glyph = subpixelRender(frag_tex_coord);
    } else {
        // Standard rendering
        float alpha = distanceToAlpha(distance);
        glyph = vec4(frag_color.rgb, frag_color.a * alpha);
    }

    // Composite: shadow + outline + glyph
    out_color = shadow;
    out_color = mix(out_color, outline, outline.a);
    out_color = mix(out_color, glyph, glyph.a);

    // Discard fully transparent pixels
    if (out_color.a < 0.01) {
        discard;
    }
}
