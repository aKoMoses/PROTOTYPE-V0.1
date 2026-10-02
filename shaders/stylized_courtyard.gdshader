shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D layout_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D concrete_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_layout = true;
uniform vec4 floor_tint : source_color = vec4(0.64, 0.61, 0.55, 1.0);
varying vec2 ground_position;

void vertex() {
    ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 tile = ground_position * 0.13;
    vec3 detail = texture(concrete_detail, tile).rgb;
    vec3 second = texture(concrete_detail, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * tile * 1.73 + vec2(0.31, 0.67)).rgb;
    vec3 variation = clamp(mix(detail, second, 0.38) / vec3(0.37, 0.34, 0.29), vec3(0.82), vec3(1.16));
    vec3 layout = use_layout ? texture(layout_albedo, UV).rgb : floor_tint.rgb;
    float steel = use_layout ? smoothstep(0.005, 0.045, layout.b - layout.r) : 0.0;
    // Leave the original repairs, safety paint and localized cover-foot dust
    // exactly where they were. Only the finish and value hierarchy change.
    ALBEDO = layout * mix(vec3(1.0), variation, 0.68 * (1.0 - steel * 0.65));
    float warmth = 0.5 + 0.5 * sin(ground_position.x * 0.095 + ground_position.y * 0.061);
    ALBEDO *= mix(vec3(0.96, 0.98, 1.015), vec3(1.025, 1.0, 0.96), warmth);
    if (use_layout) {
        NORMAL_MAP = texture(surface_normal, UV).rgb;
        NORMAL_MAP_DEPTH = 0.65;
    }
    ROUGHNESS = mix(0.94, 0.67, steel);
    METALLIC = steel * 0.25;
    SPECULAR = 0.18;
}
