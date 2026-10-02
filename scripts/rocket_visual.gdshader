shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 hot_color : source_color = vec4(1.0, 0.83, 0.43, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.19, 0.025, 1.0);
uniform float phase = 0.0;

void vertex() {
	float tip = 1.0 - UV.y;
	float flutter = sin(TIME * 51.0 + phase + UV.y * 19.0) * 0.07;
	VERTEX.xz *= 1.0 + flutter * tip;
}

void fragment() {
	float tip = 1.0 - UV.y;
	float stripes = 0.78 + 0.22 * sin(UV.x * 37.7 + TIME * 27.0 + phase + tip * 14.0);
	vec3 heat = mix(hot_color.rgb, tail_color.rgb, smoothstep(0.18, 0.95, tip));
	ALBEDO = heat;
	EMISSION = heat * 0.45;
	ALPHA = (1.0 - smoothstep(0.62, 1.0, tip)) * stripes * hot_color.a;
}
