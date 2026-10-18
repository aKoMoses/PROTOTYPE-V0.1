shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 stone_color : source_color = vec4(0.85, 0.81, 0.70, 1.0);
uniform bool basin = false;
uniform bool wall = false;
uniform float clock = 0.0;
uniform float water_level = -0.06;
uniform sampler2D surface_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 world;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1)), f.x), f.y);
}
vec2 random2(vec2 p) {
    return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3)))) * 43758.5453);
}
float water_caustic(vec2 p) {
    vec2 warped = p * 1.7 + vec2(noise(p * 0.8 + clock * 0.13), noise(p.yx * 0.7 - clock * 0.11)) * 1.6;
    vec2 cell = floor(warped), local = fract(warped);
    float first = 8.0, second = 8.0;
    for (int y=-1; y<=1; y++) {
        for (int x=-1; x<=1; x++) {
            vec2 offset = vec2(float(x),float(y));
            float distance_to_point = length(offset + random2(cell + offset) * 0.88 + 0.06 - local);
            if (distance_to_point < first) { second=first; first=distance_to_point; }
            else { second=min(second,distance_to_point); }
        }
    }
    float gap = second-first;
    return (1.0-smoothstep(0.009,0.045+fwidth(gap),gap)) * (0.5+noise(p*1.2)*0.5);
}
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
    vec2 p = world.xz;
    if (wall) { p = abs(world_normal.x) > 0.5 ? world.zy : world.xy; }
    vec2 tile_size = wall ? vec2(2.5, 0.65) : vec2(2.55, 2.1);
    vec2 grid = p / tile_size;
    vec2 edge = min(fract(grid), 1.0 - fract(grid)) * tile_size;
    float d = min(edge.x, edge.y);
    float aa = max(fwidth(d), 0.001);
    float seam = 1.0 - smoothstep(0.009, 0.009 + aa, d);
    float bevel = 1.0 - smoothstep(0.014, 0.047, d);
    float cloud = noise(p * 0.7) * 0.65 + noise(p * 2.4) * 0.35;
    float vein = pow(1.0 - abs(sin(p.x * 1.5 + p.y * 1.8 + noise(p * 0.48) * 6.0)), 10.0);
    vec3 col = stone_color.rgb * (0.94 + cloud * 0.09 + hash(floor(grid)) * 0.04);
    vec3 mineral = texture(surface_atlas, vec2(0.01) + fract(p * 0.18) * 0.48).rgb;
    col = mix(col, basin ? mineral * stone_color.rgb * 1.4 : mineral, basin ? 0.16 : 0.57);
    col = mix(col, col * vec3(0.75, 0.76, 0.70), vein * 0.19);
    col = mix(col, col * 0.57, seam * (basin ? 0.10 : 0.57) + bevel * 0.08);
    if (basin && water_level > 0.02) {
        float caustic = water_caustic(p);
        float side_light = smoothstep(3.0,12.0,abs(p.x));
        col += vec3(0.11,0.27,0.23) * caustic * mix(0.05,0.22,side_light);
        EMISSION = vec3(0.11,0.24,0.20) * caustic * mix(0.012,0.04,side_light);
    }
    ALBEDO = col;
    ROUGHNESS = basin ? 0.43 : 0.58 + cloud * 0.11;
    METALLIC = 0.0;
    SPECULAR = 0.32;
}
