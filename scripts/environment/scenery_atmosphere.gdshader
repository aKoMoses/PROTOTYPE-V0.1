shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform int kind = 0; // warm lamp shaft, suspended dust, passing bird shadow
uniform float clock = 0.0;
varying vec4 tint;
varying vec4 state;
void vertex() {
	tint = COLOR;
	state = INSTANCE_CUSTOM;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float alpha = 0.0;
	if (kind == 0) {
		float width = mix(0.92, 0.12, UV.y);
		float side = 1.0 - smoothstep(width * 0.45, width, abs(p.x));
		alpha = side * sin(UV.y * 3.14159) * tint.a;
	} else if (kind == 1) {
		alpha = pow(max(0.0, 1.0 - length(p)), 2.0) * tint.a;
	} else {
		float body = 1.0 - smoothstep(0.65, 1.0, length(p * vec2(9.0, 2.8)));
		float wing_y = abs(p.x) * (0.22 + sin(clock * 4.7 + state.x) * 0.32);
		float width = max(0.012, (1.0 - abs(p.x)) * 0.18);
		float wings = (1.0 - smoothstep(width, width + 0.035, abs(p.y - wing_y)))
			* (1.0 - smoothstep(0.82, 0.99, abs(p.x)));
		alpha = max(body, wings) * tint.a;
	}
	ALBEDO = tint.rgb;
	ALPHA = alpha;
}
