shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform int kind = 0; // falling dust, insects, brief reflected light
uniform float clock = 0.0;
varying vec4 tint;
varying vec4 state;
void vertex() {
	tint = COLOR;
	state = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float mask = 0.0;
	if (kind == 0) {
		mask = pow(max(0.0, 1.0 - length(p)), 1.8);
	} else if (kind == 1) {
		float body = 1.0 - smoothstep(0.45, 0.95, length(p * vec2(5.0, 2.1)));
		float flap = 0.16 + abs(sin(clock * 42.0 + state.x)) * 0.55;
		float wings = (1.0 - smoothstep(0.12, 0.35, abs(p.y - abs(p.x) * flap)))
			* (1.0 - smoothstep(0.45, 0.90, abs(p.x)));
		mask = max(body, wings * 0.62);
	} else {
		float sweep = state.y / 0.42;
		float stripe = abs(UV.x + UV.y * 0.32 - mix(-0.30, 1.62, sweep));
		float edge = smoothstep(0.0, 0.12, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
		mask = (1.0 - smoothstep(0.018, 0.11, stripe)) * edge * sin(clamp(sweep, 0.0, 1.0) * 3.141593);
	}
	ALBEDO = tint.rgb;
	ALPHA = mask * tint.a;
}
