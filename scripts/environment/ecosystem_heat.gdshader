shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float clock = 0.0;
varying float strength;
varying float phase;
void vertex() {
	strength = INSTANCE_CUSTOM.y;
	phase = INSTANCE_CUSTOM.x;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = pow(max(0.0, 1.0 - dot(p, p)), 2.0);
	float wave = sin(UV.y * 21.0 - clock * 3.6 + phase + sin(UV.x * 9.0));
	vec2 offset = vec2(wave, cos(UV.x * 17.0 + clock * 1.8 + phase) * 0.35)
		* edge * strength * 0.0014;
	ALBEDO = texture(screen_texture, clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999))).rgb;
	ALPHA = edge * strength * 0.28;
}
