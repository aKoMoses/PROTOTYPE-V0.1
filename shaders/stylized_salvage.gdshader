shader_type spatial;
render_mode diffuse_burley;

// Broad painted values and deliberately quiet grain. The scene lights still
// own illumination and shadows; no screen-space outline or glowing edges.
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
uniform vec4 pigment_color : source_color = vec4(1.0);
uniform float pigment_strength = 0.0;
uniform float relief_strength = 0.35;
uniform float surface_roughness = 0.72;
uniform float surface_metallic = 0.12;
uniform float sculpt_strength = 0.13;
varying vec3 paint_position;
varying vec3 paint_normal;
varying vec3 world_position;
varying vec3 world_normal;

float cloud(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec4 h = fract(sin(vec4(dot(cell, vec2(127.1, 311.7)),
        dot(cell + vec2(1.0, 0.0), vec2(127.1, 311.7)),
        dot(cell + vec2(0.0, 1.0), vec2(127.1, 311.7)),
        dot(cell + vec2(1.0), vec2(127.1, 311.7)))) * 43758.5453);
    return mix(mix(h.x, h.y, f.x), mix(h.z, h.w, f.x), f.y);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    paint_position = world_projection ? world_position : VERTEX;
    paint_normal = world_projection ? world_normal : NORMAL;
}

void fragment() {
    vec3 sampled = vec3(1.0);
    vec3 relief = vec3(0.5, 0.5, 1.0);
    if (has_texture) {
        if (world_projection) {
            vec3 weights = pow(abs(paint_normal), vec3(4.0));
            weights /= max(dot(weights, vec3(1.0)), 0.0001);
            vec3 p = paint_position * texture_scale + texture_offset;
            sampled = texture(color_texture, p.zy).rgb * weights.x
                + texture(color_texture, p.xz).rgb * weights.y
                + texture(color_texture, p.xy).rgb * weights.z;
        } else {
            vec2 uv = UV * texture_scale.xy + texture_offset.xy;
            sampled = texture(color_texture, uv).rgb;
            if (has_relief) { relief = texture(relief_texture, uv).rgb; }
        }
        if (normalized_texture) {
            // Add quiet paint grain to previously flat colored surfaces without
            // changing the training lanes' authored identification colors.
            sampled = mix(vec3(1.0), clamp(sampled / vec3(0.53, 0.49, 0.38),
                vec3(0.78), vec3(1.20)), 0.55);
        } else {
            float value = dot(sampled, vec3(0.2126, 0.7152, 0.0722));
            // Retain authored paint/rust colors while reducing fine contrast.
            sampled = mix(vec3(value), sampled, 0.85);
            sampled = mix(vec3(0.42), sampled, texture_strength);
            sampled = mix(sampled, pigment_color.rgb, pigment_strength);
        }
    }
    vec3 base = source_tint.rgb * sampled;
    if (vertex_tint) { base *= COLOR.rgb; }
    float brush = cloud(world_position.xz * 0.70 + world_position.y * vec2(0.21, 0.37));
    base *= 0.93 + brush * 0.14;
    float up_face = smoothstep(-0.15, 0.85, world_normal.y);
    vec3 planes = mix(vec3(0.80, 0.87, 0.97), vec3(1.16, 1.10, 1.02), up_face);
    ALBEDO = base * mix(vec3(1.0), planes, sculpt_strength / 0.25);
    ROUGHNESS = surface_roughness;
    METALLIC = surface_metallic;
    SPECULAR = 0.27;
    if (has_relief && !world_projection) {
        NORMAL_MAP = relief;
        NORMAL_MAP_DEPTH = relief_strength;
    }
    if (has_relief && world_projection) {
        // World-projected baked meshes have no UV tangent basis. A surface
        // gradient from the actual paint gives restrained relief in view space.
        float height = dot(sampled, vec3(0.2126, 0.7152, 0.0722));
        vec3 dx = dFdx(VERTEX);
        vec3 dy = dFdy(VERTEX);
        vec3 rx = cross(dy, NORMAL);
        vec3 ry = cross(NORMAL, dx);
        float determinant = dot(dx, rx);
        vec3 gradient = sign(determinant) * (dFdx(height) * rx + dFdy(height) * ry);
        NORMAL = normalize(abs(determinant) * NORMAL - gradient * relief_strength * 0.065);
    }
    // A tangent basis is absent on the baked world-projected salvage meshes.
    // Their real bevel normals supply the readable relief instead.
}

void light() {
    // Two continuous value masses, like painted planes. All attenuation and
    // moving cast shadows come from the real scene lights.
    float facing = dot(NORMAL, LIGHT);
    float paint_light = 0.30 * smoothstep(-0.16, 0.22, facing)
        + 0.70 * smoothstep(0.20, 0.92, facing);
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * paint_light / PI;
    float highlight = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0),
        mix(64.0, 12.0, surface_roughness));
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * highlight
        * (0.045 + surface_metallic * 0.09);
}
