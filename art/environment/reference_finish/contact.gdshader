shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec2 footprint;
varying vec2 extent;

void vertex() {
    footprint = INSTANCE_CUSTOM.xy;
    extent = INSTANCE_CUSTOM.zw;
}

void fragment() {
    vec2 point = abs(UV - vec2(0.5)) * extent;
    vec2 outside = max(point - footprint * 0.5, vec2(0.0));
    float distance_to_base = length(outside);
    float occlusion = exp(-distance_to_base * distance_to_base * 18.0);
    ALBEDO = vec3(0.14, 0.105, 0.065);
    ALPHA = occlusion * 0.23;
}
