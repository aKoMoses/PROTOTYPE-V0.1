shader_type spatial;
render_mode diffuse_burley, cull_disabled;
uniform bool leaf = false;
uniform bool stone = false;
uniform sampler2D concrete_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    if (leaf) {
        float bend = UV.y * UV.y;
        VERTEX.x += sin(TIME * 1.2 + world_position.x * 0.6 + world_position.z) * bend * 0.025;
    }
}
void fragment() {
    ALBEDO = COLOR.rgb;
    if (leaf) {
        float rib = 0.94 + 0.06 * sin(UV.y * 87.0);
        ALBEDO *= rib;
    }
    if (stone) {
        vec3 weights = pow(abs(world_normal),vec3(4.0));
        weights /= max(dot(weights,vec3(1.0)),0.001);
        vec3 p = world_position * 0.85;
        vec3 grain = texture(concrete_detail,p.zy).rgb * weights.x
            + texture(concrete_detail,p.xz).rgb * weights.y
            + texture(concrete_detail,p.xy).rgb * weights.z;
        ALBEDO *= clamp(grain / vec3(0.373,0.308,0.230),vec3(0.6),vec3(1.3));
    }
    ROUGHNESS = stone ? 0.97 : (leaf ? 0.91 : 0.78);
    SPECULAR = leaf ? 0.18 : 0.30;
    METALLIC = (leaf || stone) ? 0.0 : 0.18;
    AO = mix(0.65,1.0,smoothstep(0.0,0.20,world_position.y));
    AO_LIGHT_AFFECT = 0.20;
}
