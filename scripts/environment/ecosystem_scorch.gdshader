shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
varying vec4 state;
void vertex() {
	state = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float angle = atan(p.y, p.x);
	float radius = length(p) * (1.0 + sin(angle * 7.0 + state.x) * 0.07);
	float soot = (1.0 - smoothstep(0.50, 0.95, radius)) * state.z;
	float hot = exp(-state.y * 3.4) * (1.0 - smoothstep(0.13, 0.48, radius));
	ALBEDO = mix(vec3(0.11, 0.10, 0.075), vec3(0.92, 0.29, 0.045), hot);
	EMISSION = vec3(1.0, 0.22, 0.025) * hot * 0.42;
	ALPHA = soot * 0.58;
}
