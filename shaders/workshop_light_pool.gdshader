shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 light_color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float strength = 0.10;
uniform float live_intensity = 1.0;
void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float pool = pow(max(0.0, 1.0 - radius), 2.4);
	ALBEDO = light_color.rgb * strength * live_intensity;
	ALPHA = pool;
}
