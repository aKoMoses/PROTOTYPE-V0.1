shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D layout_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D concrete_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_layout = true;
uniform bool world_layout = false;
uniform vec2 layout_origin = vec2(-30.0);
uniform vec2 layout_span = vec2(60.0);
uniform vec4 zone_tint : source_color = vec4(1.0);
uniform vec4 floor_tint : source_color = vec4(0.64, 0.61, 0.55, 1.0);
uniform float combat_clarity : hint_range(0.0, 1.0) = 0.0;
varying vec2 ground_position;

void vertex() {
    ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 tile = ground_position * 0.13;
    vec3 detail = texture(concrete_detail, tile).rgb;
    vec3 second = texture(concrete_detail, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * tile * 1.73 + vec2(0.31, 0.67)).rgb;
    vec3 variation = clamp(mix(detail, second, 0.22) / vec3(0.373, 0.308, 0.230), vec3(0.64), vec3(1.38));
    vec2 layout_uv = world_layout ? (ground_position - layout_origin) / layout_span : UV;
    vec3 layout = (use_layout ? texture(layout_albedo, layout_uv).rgb : floor_tint.rgb) * zone_tint.rgb;
    float steel = use_layout ? smoothstep(0.005, 0.045, layout.b - layout.r) : 0.0;
    // Leave the original repairs, safety paint and localized cover-foot dust
    // exactly where they were. Only the finish and value hierarchy change.
    ALBEDO = layout * mix(vec3(1.0), variation, 0.92 * (1.0 - combat_clarity * 0.5) * (1.0 - steel * 0.65));
    float warmth = 0.5 + 0.5 * sin(ground_position.x * 0.095 + ground_position.y * 0.061);
    ALBEDO *= mix(vec3(0.96, 0.98, 1.015), vec3(1.025, 1.0, 0.96), warmth);
    if (use_layout) {
        NORMAL_MAP = texture(surface_normal, layout_uv).rgb;
        NORMAL_MAP_DEPTH = 0.65 * (1.0 - combat_clarity * 0.3);
    }
    ROUGHNESS = mix(0.94, 0.67, steel);
    METALLIC = steel * 0.25;
    SPECULAR = 0.18;
}
