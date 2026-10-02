shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
uniform float clock = 0.0;
varying vec4 tint;
varying vec4 state;
void vertex() {
	tint = COLOR;
	state = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float edge = 1.0 - smoothstep(0.65, 0.97, radius + sin(p.x * 13.0 + state.x) * 0.05 + sin(p.y * 9.0) * 0.04);
	float angle = max(0.0, dot(normalize(NORMAL), normalize(VIEW)));
	float film = (p.x * 0.8 + p.y * 0.5 + sin(p.y * 5.0 + state.x) * 0.12 + angle * 0.9) * 9.0;
	vec3 sheen = vec3(0.24, 0.29, 0.28) + cos(vec3(0.0, 2.1, 4.2) + film) * 0.06;
	float age = clock - state.y;
	float ring = (1.0 - smoothstep(0.014, 0.055, abs(radius - age * 0.65)))
		* (1.0 - smoothstep(0.75, 1.5, age)) * step(0.0, age) * state.z;
	ALBEDO = mix(tint.rgb, sheen, 0.34 + (1.0 - angle) * 0.26) + ring * 0.035;
	METALLIC = 0.66;
	ROUGHNESS = clamp(0.21 + ring * 0.13, 0.0, 1.0);
	SPECULAR = 0.60;
	ALPHA = edge * tint.a;
}
