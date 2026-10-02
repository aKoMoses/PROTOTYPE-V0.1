shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float progress = 0.0;
uniform float opacity = 0.0;
uniform float phase = 0.0;
uniform int effect_kind = 0; // steam, ripple, projected pendant shadow
uniform vec4 tint : source_color = vec4(0.75, 0.78, 0.74, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float alpha = 0.0;
	if (effect_kind == 0) {
		float curl = sin(p.x * 10.0 + progress * 9.0 + phase) * sin(p.y * 8.0 - progress * 6.0);
		alpha = pow(max(0.0, 1.0 - radius + curl * 0.09), 2.0) * opacity;
	} else if (effect_kind == 1) {
		float ring = 1.0 - smoothstep(0.02, 0.07, abs(radius - (0.12 + progress * 0.78)));
		alpha = ring * opacity * (1.0 - progress);
	} else {
		alpha = pow(max(0.0, 1.0 - length(p * vec2(0.7, 1.0))), 3.0) * opacity;
	}
	ALBEDO = tint.rgb;
	ALPHA = alpha;
}
