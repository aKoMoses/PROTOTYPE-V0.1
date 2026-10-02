shader_type spatial;
render_mode diffuse_burley;

// Real diffuse/specular lighting and filtered triplanar relief. Parameters
// match the painted pass so its authored colours and UV scales are retained.
uniform vec4 source_tint : source_color = vec4(1.0);
uniform sampler2D color_texture : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform sampler2D relief_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_texture = false;
uniform bool normalized_texture = false;
uniform bool has_relief = false;
uniform bool vertex_tint = false;
uniform bool world_projection = false;
uniform vec3 texture_scale = vec3(1.0);
uniform vec3 texture_offset = vec3(0.0);
uniform float texture_strength = 0.90;
uniform float texture_gain = 1.0;
uniform vec4 pigment_color : source_color = vec4(1.0);
uniform float pigment_strength = 0.0;
uniform float relief_strength = 0.35;
uniform float surface_roughness = 0.72;
uniform float surface_metallic = 0.12;
uniform float sculpt_strength = 0.13;
uniform float weathering_strength = 0.0;
uniform float steel_finish = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

float grain_hash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float weather_noise(vec3 p) {
    vec3 cell = floor(p);
    vec3 q = fract(p);
    q = q * q * (3.0 - 2.0 * q);
    return mix(mix(mix(grain_hash(cell), grain_hash(cell + vec3(1,0,0)), q.x),
                   mix(grain_hash(cell + vec3(0,1,0)), grain_hash(cell + vec3(1,1,0)), q.x), q.y),
               mix(mix(grain_hash(cell + vec3(0,0,1)), grain_hash(cell + vec3(1,0,1)), q.x),
                   mix(grain_hash(cell + vec3(0,1,1)), grain_hash(cell + vec3(1,1,1)), q.x), q.y), q.z);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    vec3 sampled = vec3(1.0);
    vec3 weights = pow(abs(world_normal), vec3(4.0));
    weights /= max(dot(weights, vec3(1.0)), 0.0001);
    vec3 p = world_position * texture_scale + texture_offset;
    vec2 uv = UV * texture_scale.xy + texture_offset.xy;
    if (has_texture) {
        sampled = world_projection
            ? texture(color_texture, p.zy).rgb * weights.x
              + texture(color_texture, p.xz).rgb * weights.y
              + texture(color_texture, p.xy).rgb * weights.z
            : texture(color_texture, uv).rgb;
        if (normalized_texture) {
            sampled = mix(vec3(1.0), clamp(sampled / vec3(0.53, 0.49, 0.38), vec3(0.82), vec3(1.16)), 0.55);
        } else {
            sampled = mix(vec3(0.42), sampled, texture_strength);
            sampled = mix(sampled, pigment_color.rgb, pigment_strength);
        }
    }
    ALBEDO = source_tint.rgb * sampled * texture_gain;
    if (vertex_tint) { ALBEDO *= COLOR.rgb; }
    // Broad stains and millimetre chips break repeated texture grain. They
    // stay on scenery surfaces and do not depend on any actor or visibility.
    float patina = weather_noise(world_position * 1.45);
    float grit = weather_noise(world_position * 18.0 + vec3(8.1));
    float chip = smoothstep(0.57, 0.78, patina) * smoothstep(0.57, 0.74, grit) * weathering_strength;
    vec3 exposed = mix(vec3(0.10, 0.115, 0.12), vec3(0.105, 0.065, 0.038), steel_finish);
    ALBEDO = mix(ALBEDO, exposed, chip * 0.72);
    float lower_grime = (1.0 - smoothstep(0.06, 0.5, world_position.y)) * (0.4 + patina * 0.6);
    ALBEDO *= 1.0 - weathering_strength * (lower_grime * 0.20 + patina * 0.10);
    float dust = smoothstep(0.35, 0.8, patina) * max(world_normal.y, 0.0) * steel_finish * 0.14;
    ALBEDO = mix(ALBEDO, vec3(0.35, 0.28, 0.19), dust);
    // Paint chips catch light with their actual normals, rather than adding
    // a painted bright strip to every upward-facing polygon.
    if (has_relief && world_projection) {
        vec2 nx = texture(relief_texture, p.zy).xy * 2.0 - 1.0;
        vec2 ny = texture(relief_texture, p.xz).xy * 2.0 - 1.0;
        vec2 nz = texture(relief_texture, p.xy).xy * 2.0 - 1.0;
        vec3 perturbation = vec3(0.0, nx.y, nx.x) * weights.x
            + vec3(ny.x, 0.0, ny.y) * weights.y
            + vec3(nz.x, nz.y, 0.0) * weights.z;
        perturbation -= world_normal * dot(world_normal, perturbation);
        vec3 normal_world = normalize(world_normal + perturbation * relief_strength);
        NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
    } else if (has_relief) {
        NORMAL_MAP = texture(relief_texture, uv).rgb;
        NORMAL_MAP_DEPTH = relief_strength;
    }
    float wear = dot(sampled, vec3(0.2126, 0.7152, 0.0722));
    ROUGHNESS = clamp(surface_roughness + (0.38 - wear) * 0.12 + chip * 0.17 + dust, 0.38, 0.98);
    METALLIC = surface_metallic * (1.0 - dust * 2.0);
    SPECULAR = 0.38;
    AO = mix(0.82, 1.0, smoothstep(0.02, 0.42, world_position.y));
    AO_LIGHT_AFFECT = 0.18;
}
