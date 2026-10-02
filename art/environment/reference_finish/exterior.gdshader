shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D concrete_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 ground_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 c = floor(p), q = fract(p);
    q = q * q * (3.0 - 2.0 * q);
    return mix(mix(hash(c), hash(c + vec2(1,0)), q.x),
               mix(hash(c + vec2(0,1)), hash(c + vec2(1,1)), q.x), q.y);
}

void vertex() { ground_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz; }
void fragment() {
    vec2 p = ground_position;
    vec3 grain = texture(concrete_detail, p * 0.17).rgb;
    vec3 variation = clamp(grain / vec3(0.373, 0.308, 0.230), vec3(0.75), vec3(1.22));
    float crust = noise(p * 0.58) * 0.6 + noise(p * 1.8) * 0.4;
    float wash = noise(p * 0.12);
    vec3 sand = mix(vec3(0.52,0.355,0.19), vec3(0.68,0.49,0.28), wash);
    vec3 stone = mix(vec3(0.42,0.33,0.24), vec3(0.60,0.49,0.35), crust);
    ALBEDO = mix(sand, stone, smoothstep(0.48,0.7,crust) * 0.65) * variation;
    // Small erosion channels are irregular and shallow, not a flat yellow mat.
    float channel = 1.0 - smoothstep(0.012,0.065,abs(crust - 0.49));
    ALBEDO *= 1.0 - channel * 0.13;
    NORMAL = normalize(NORMAL + vec3(dFdx(crust), dFdy(crust), 0.0) * 0.45);
    ROUGHNESS = 0.96;
    SPECULAR = 0.18;
}
