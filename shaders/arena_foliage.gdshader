shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec4 leaf_color : source_color = vec4(0.18, 0.36, 0.21, 1.0);

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
void fragment() {
    // UV follows each leaf from root to tip, across both folded halves.
    float across = abs(UV.x - 0.5) * 2.0;
    float edge = smoothstep(0.70, 1.0, across);
    float rib = 1.0 - smoothstep(0.012, 0.04 + fwidth(UV.x), abs(UV.x - 0.5));
    float branch_phase = fract(UV.y * 9.0 - across * 1.7);
    float veins = (1.0 - smoothstep(0.025, 0.065 + fwidth(branch_phase), min(branch_phase, 1.0 - branch_phase))) * (1.0 - edge);
    float mottle = hash21(floor(UV * vec2(22.0, 32.0)));
    vec3 col = leaf_color.rgb * (0.86 + mottle * 0.21 - edge * 0.13);
    col = mix(col, leaf_color.rgb * vec3(1.30, 1.18, 0.78), rib * 0.48 + veins * 0.13);
    ALBEDO = col;
    ROUGHNESS = 0.73 + edge * 0.12;
    SPECULAR = 0.22;
    AO = 0.94;
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
