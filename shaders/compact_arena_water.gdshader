shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.03, 0.22, 0.29, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.21, 0.57, 0.61, 1.0);
uniform float motion_clock = 0.0;
uniform int fluid_style = 0;
varying vec3 world_pos;

float fluid_hash(vec2 p) {
    vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float fluid_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(fluid_hash(cell), fluid_hash(cell + vec2(1.0, 0.0)), f.x), mix(fluid_hash(cell + vec2(0.0, 1.0)), fluid_hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}
// Uneven plates of cooling basalt, separated by molten seams.
vec2 crust(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float nearest = 8.0;
    float next_nearest = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 centre = offset + vec2(fluid_hash(cell + offset), fluid_hash(cell + offset + vec2(19.7, 6.2))) - f;
            float distance_squared = dot(centre, centre);
            if (distance_squared < nearest) {
                next_nearest = nearest;
                nearest = distance_squared;
            } else if (distance_squared < next_nearest) {
                next_nearest = distance_squared;
            }
        }
    }
    return vec2(sqrt(nearest), sqrt(next_nearest) - sqrt(nearest));
}
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = world_pos.xz;
    float a = sin(p.x * 0.72 + p.y * 0.43 + sin(p.y * 0.17) * 1.8 + motion_clock * 0.36);
    float b = sin(p.x * -0.38 + p.y * 0.81 + sin(p.x * 0.31) * 0.8 + motion_clock * 0.47);
    float broad = fluid_noise(p * 0.09 + motion_clock * 0.012);
    float caustic = pow(max(0.0, 1.0 - abs(a + b) * 0.5), 12.0);
    ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.18 + broad * 0.22) + vec3(0.017, 0.035, 0.028) * caustic;
    METALLIC = 0.14;
    ROUGHNESS = 0.29;
    NORMAL_MAP = vec3(0.5 + a * 0.055, 0.5 + b * 0.055, 1.0);
    NORMAL_MAP_DEPTH = 0.16;
    EMISSION = shallow_color.rgb * caustic * 0.007;
    if (fluid_style == 1) {
        vec2 q = p * 0.245 + vec2(motion_clock * 0.009, -motion_clock * 0.006);
        vec2 warp = vec2(fluid_noise(q * 0.61), fluid_noise(q * 0.61 + vec2(7.3, 2.1))) * 0.95;
        vec2 plates = crust(q + warp);
        float aa = max(fwidth(plates.y), 0.008);
        float melt = 1.0 - smoothstep(0.012 - aa, 0.055 + aa, plates.y);
        float hot_core = 1.0 - smoothstep(0.004 - aa, 0.018 + aa, plates.y);
        float slag = fluid_noise(q * 3.2);
        float eddies = fluid_noise(q * 0.43 + warp);
        // Broad pools interrupt the cell pattern; distant slag keeps the duel legible.
        float pool = smoothstep(0.76, 0.92, eddies);
        float heat = max(melt * (0.50 + eddies * 0.36), pool * 0.85);
        float distance_fade = 1.0 - smoothstep(23.0, 62.0, length(p));
        vec3 rock = mix(vec3(0.019, 0.024, 0.028), deep_color.rgb * 0.23, slag * 0.65);
        vec3 molten = mix(shallow_color.rgb * 0.55, vec3(1.0, 0.40, 0.065), hot_core * 0.60);
        ALBEDO = mix(rock * (0.75 + plates.x * 0.20), molten, heat * (0.22 + distance_fade * 0.20));
        EMISSION = molten * heat * (0.10 + distance_fade * 0.17);
        ROUGHNESS = mix(0.89, 0.48, heat);
        METALLIC = 0.06;
        NORMAL_MAP = vec3(0.5 + (slag - 0.5) * 0.12, 0.5 + (plates.x - 0.5) * 0.09, 1.0);
        NORMAL_MAP_DEPTH = 0.18;
    } else if (fluid_style == 2) {
        // Calm deep water with long, faint ripples under the acoustic shell.
        float ripple = pow(max(0.0, 1.0 - abs(sin(length(p * vec2(0.72, 1.0)) * 1.8 - motion_clock * 0.24))), 10.0);
        ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.09 + broad * 0.15) + vec3(0.006, 0.012, 0.016) * ripple;
        ROUGHNESS = 0.21 + broad * 0.035;
        METALLIC = 0.48;
        NORMAL_MAP_DEPTH = 0.045;
        EMISSION = vec3(0.0);
    }
}
