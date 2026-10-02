shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 neon_color : source_color = vec4(0.1,0.8,0.9,1.0);
void fragment() {
	float facing = max(0.0, dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = neon_color.rgb * 0.65;
	ALPHA = pow(facing, 2.0) * 0.18;
}
