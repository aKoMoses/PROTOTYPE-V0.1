shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec2 wind_direction = vec2(0.94, -0.34);
uniform float wind_strength = 0.45;
uniform float scenery_clock = 0.0;
uniform float scenery_gust = 0.0;
void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float flutter = sin(scenery_clock * 1.25 + at.x * 0.8 + at.z * 0.57) * 0.008;
	VERTEX.xz += normalize(wind_direction) * (flutter * wind_strength + scenery_gust * 0.016) * UV.y * UV.y;
}
void fragment() {
	ALBEDO = COLOR.rgb * (0.94 + UV.y * 0.08);
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
	EMISSION = COLOR.rgb * UV.y * 0.015;
}
