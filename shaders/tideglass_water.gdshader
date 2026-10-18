shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform float clock = 0.0;
uniform sampler2D planar_reflection : source_color, filter_linear, repeat_disable;
uniform bool use_planar_reflection = false;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform vec4 deep_color : source_color = vec4(0.035, 0.29, 0.34, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.09, 0.48, 0.47, 1.0);
varying vec3 world;

float wave(vec2 p, float time) {
    return sin(p.x * 2.6 + p.y * 1.9 - time * 1.1) * 0.035
         + sin(p.x * -1.9 + p.y * 3.7 - time * 0.73) * 0.022
         + sin(p.x * 0.8 + p.y * 0.6 - time * 0.4) * 0.025;
}

void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world.xz;
    float w = wave(p, clock);
    // No tangent/UV stream on the basin: use an explicit view-space normal.
    float dx = (wave(p + vec2(0.025,0), clock) - w) / 0.025;
    float dz = (wave(p + vec2(0,0.025), clock) - w) / 0.025;
    vec3 ripple_normal = normalize(vec3(-dx, 1.0, -dz));
    NORMAL = normalize((VIEW_MATRIX * vec4(ripple_normal, 0.0)).xyz);
    float swell = sin(p.x * 0.4 + p.y * 0.55 - clock * 0.4) * 0.5 + 0.5;
    vec3 tint = mix(deep_color.rgb, shallow_color.rgb, swell * 0.38);
    vec2 bend = vec2(dx, dz) * 0.014;
    vec3 through_water = texture(screen_texture, clamp(SCREEN_UV + bend, vec2(0.001), vec2(0.999))).rgb;
    ALBEDO = tint * 0.42;
    EMISSION = through_water * vec3(0.52, 0.76, 0.76) * 0.56;
    if (use_planar_reflection) {
        vec2 uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + vec2(dx, dz) * 0.038;
        vec4 reflected = texture(planar_reflection, clamp(uv, vec2(0.002), vec2(0.998)));
        float strength = 0.24;
        EMISSION += reflected.rgb * strength;
    }
    ROUGHNESS = 0.23;
    METALLIC = 0.12;
    SPECULAR = 0.24;
    // Turquoise absorption keeps the sunlit floor and reflected sky from
    // washing the water into pale green at this elevated combat camera.
    ALBEDO *= vec3(0.18, 0.60, 0.82);
    EMISSION *= vec3(0.18, 0.60, 0.82);
    ALPHA = 0.94;
}
