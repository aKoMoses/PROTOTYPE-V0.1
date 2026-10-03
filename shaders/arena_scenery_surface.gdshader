shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 source_tint : source_color = vec4(0.7, 0.65, 0.5, 1.0);
uniform int surface_kind = 0; // stone, metal, enamel, ceramic
uniform float surface_roughness = 0.8;
uniform float surface_metallic = 0.0;
uniform float weathering = 0.7;
uniform float water_stains = 0.0;
uniform sampler2D surface_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength = 0.0;
uniform float texture_strength = 0.0;
uniform float texture_scale = 0.24;
varying vec3 local_pos;
varying vec3 local_normal;
varying float world_height;
varying vec3 view_tangent;
varying vec3 view_bitangent;

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise2(vec2 p) {
    vec2 c = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(c), hash21(c + vec2(1, 0)), f.x), mix(hash21(c + vec2(0, 1)), hash21(c + vec2(1)), f.x), f.y);
}
void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
    world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
    vec3 n = abs(NORMAL);
    vec3 tangent = n.x > max(n.y, n.z) ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 bitangent = n.y > max(n.x, n.z) ? vec3(0, 0, 1) : vec3(0, 1, 0);
    view_tangent = normalize((MODELVIEW_MATRIX * vec4(tangent, 0.0)).xyz);
    view_bitangent = normalize((MODELVIEW_MATRIX * vec4(bitangent, 0.0)).xyz);
}
void fragment() {
    vec3 n = abs(local_normal);
    vec2 p = n.y > max(n.x, n.z) ? local_pos.xz : (n.x > n.z ? local_pos.zy : local_pos.xy);
    float broad = noise2(p * 0.78 + vec2(3.7, 1.9));
    float grain = noise2(p * 13.0);
    float patina = smoothstep(0.4, 0.78, noise2(p * 2.7)) * weathering;
    vec3 col = source_tint.rgb * (0.86 + broad * 0.2 + grain * 0.025);
    float relief = (grain - 0.5) * 0.0015;
    float roughness = surface_roughness;
    vec3 sampled = texture(surface_texture, p * texture_scale).rgb;
    vec3 average = surface_kind == 1 ? vec3(0.185, 0.221, 0.261) : surface_kind == 2 ? vec3(0.53, 0.49, 0.38) : vec3(0.373, 0.308, 0.230);
    vec3 texture_variation = clamp(sampled / average, vec3(0.43), vec3(1.50));
    col *= mix(vec3(1.0), texture_variation, texture_strength);
    float texture_height = dot(texture_variation, vec3(0.2126, 0.7152, 0.0722));
    relief += (texture_height - 1.0) * 0.008 * texture_strength;
    roughness += (1.0 - texture_height) * 0.13 * texture_strength;
    if (surface_kind == 1) {
        float scratch = pow(noise2(vec2(p.x * 21.0, p.y * 1.8)), 8.0);
        col = mix(col, source_tint.rgb * vec3(0.56, 0.76, 0.74), patina * 0.42);
        // Brushing should follow the metal tint; an additive white scratch
        // overwhelms dark iron at the actual gameplay camera distance.
        col += source_tint.rgb * scratch * 0.12 * (1.0 - patina);
        relief += scratch * 0.0008;
        roughness += patina * 0.22;
    } else if (surface_kind == 2) {
        float chipped = smoothstep(0.26, 0.50, 1.0 - texture_height) * weathering;
        col = mix(col, vec3(0.12, 0.14, 0.14), chipped * 0.62);
        roughness += chipped * 0.3;
        relief -= chipped * 0.002;
    } else if (surface_kind == 3) {
        vec2 tile = p / vec2(0.52, 0.28);
        vec2 edge = (0.5 - abs(fract(tile) - 0.5)) * vec2(0.52, 0.28);
        float seam = min(edge.x, edge.y);
        float aa = max(fwidth(seam), 0.001);
        float joint = 1.0 - smoothstep(0.004 - aa, 0.004 + aa, seam);
        col *= 0.91 + hash21(floor(tile)) * 0.18;
        col = mix(col, source_tint.rgb * 0.34, joint * 0.7);
        relief -= joint * 0.003;
        roughness = 0.41 + patina * 0.18;
    } else {
        col = mix(col, source_tint.rgb * vec3(0.76, 0.74, 0.70), patina * 0.16);
    }
    float wet_band = (1.0 - smoothstep(0.65, 1.25, world_height)) * water_stains;
    float deposit = wet_band * smoothstep(0.22, 0.74, noise2(p * vec2(4.2, 1.6)));
    col = mix(col, vec3(0.12, 0.24, 0.19), deposit * 0.46);
    roughness = mix(roughness, 0.37, deposit * 0.6);
    ALBEDO = col;
    METALLIC = surface_metallic * (1.0 - deposit * 0.4);
    ROUGHNESS = clamp(roughness, 0.24, 0.96);
    SPECULAR = 0.32;
    AO = 1.0 - deposit * 0.20;
    vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
    vec3 cy = cross(dy, NORMAL), cx = cross(NORMAL, dx);
    float determinant = dot(dx, cy);
    NORMAL = normalize(abs(determinant) * NORMAL - sign(determinant) * (dFdx(relief) * cy + dFdy(relief) * cx) + NORMAL * 0.0000001);
    vec2 relief_normal = texture(surface_normal, p * texture_scale).xy * 2.0 - 1.0;
    NORMAL = normalize(NORMAL + (view_tangent * relief_normal.x + view_bitangent * relief_normal.y) * normal_strength);
}
