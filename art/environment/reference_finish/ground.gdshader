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
uniform float combat_clarity = 0.0;
varying vec2 ground_position;

vec2 crack_seed(vec2 cell) {
    return fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
}

vec2 angular_warp(vec2 p) {
    vec2 cell = floor(p), local = fract(p);
    return mix(mix(crack_seed(cell), crack_seed(cell + vec2(1,0)), local.x),
               mix(crack_seed(cell + vec2(0,1)), crack_seed(cell + vec2(1,1)), local.x), local.y) - vec2(0.5);
}

vec2 fracture(vec2 position) {
    vec2 p = position * 0.30;
    p += angular_warp(position * 0.85) * 0.065;
    p += angular_warp(position * 4.5) * 0.018;
    vec2 cell = floor(p);
    vec2 local = fract(p);
    float first = 8.0;
    float second = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 seed = offset + crack_seed(cell + offset) * 0.76 + vec2(0.12);
            float distance_to_seed = length(seed - local);
            if (distance_to_seed < first) {
                second = first;
                first = distance_to_seed;
            } else { second = min(second, distance_to_seed); }
        }
    }
    float gap = second - first;
    float width = max(fwidth(gap), 0.003);
    float broken = mix(0.38, 1.0, smoothstep(-0.35, 0.35, sin(position.x * 0.73 + sin(position.y * 0.81))));
    float fissure = (1.0 - smoothstep(0.002, 0.006 + width, gap)) * broken;
    float shoulder = (1.0 - smoothstep(0.018, 0.030 + width, gap)) * broken;
    return vec2(fissure, shoulder);
}

void vertex() {
    ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 tile = ground_position * 0.13;
    vec3 detail = texture(concrete_detail, tile).rgb;
    vec3 second = texture(concrete_detail, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * tile * 1.73 + vec2(0.31, 0.67)).rgb;
    vec3 variation = clamp(mix(detail, second, 0.22) / vec3(0.373, 0.308, 0.230), vec3(0.76), vec3(1.28));
    vec2 layout_uv = world_layout ? (ground_position - layout_origin) / layout_span : UV;
    vec3 layout = (use_layout ? texture(layout_albedo, layout_uv).rgb : floor_tint.rgb) * zone_tint.rgb;
    float steel = use_layout ? smoothstep(0.005, 0.045, layout.b - layout.r) : 0.0;
    vec2 damage = fracture(ground_position) * (1.0 - steel);
    float crack = damage.x;
    ALBEDO = layout * mix(vec3(1.0), variation, 0.68 * (1.0 - steel * 0.65));
    // Pale aggregate on the chipped shoulder, a darker crevice inside. The
    // footprint is antialiased independently of the atlas resolution.
    ALBEDO *= 1.0 + (damage.y - crack) * 0.14 - crack * 0.52;
    if (use_layout) {
        vec3 normal_detail = texture(surface_normal, layout_uv).rgb;
        float height = -damage.y * 0.007 - crack * 0.012;
        vec2 dx = dFdx(ground_position), dy = dFdy(ground_position);
        float determinant = dx.x * dy.y - dx.y * dy.x;
        if (abs(determinant) > 0.000001) {
            vec2 slope = vec2(dFdx(height)*dy.y - dFdy(height)*dx.y,
                              dx.x*dFdy(height) - dy.x*dFdx(height)) / determinant;
            normal_detail.xy -= clamp(slope, vec2(-0.5), vec2(0.5)) * 0.5;
        }
        NORMAL_MAP = normal_detail;
        NORMAL_MAP_DEPTH = 0.82;
    }
    AO = 1.0 - crack * 0.26;
    AO_LIGHT_AFFECT = 0.12;
    ROUGHNESS = mix(0.92, 0.58, steel);
    METALLIC = steel * 0.30;
    SPECULAR = 0.24;
}
