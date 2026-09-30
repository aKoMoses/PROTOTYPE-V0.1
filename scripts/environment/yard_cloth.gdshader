shader_type spatial;
render_mode cull_disabled;

uniform sampler2D canvas_texture : source_color, filter_linear_mipmap;
uniform vec4 canvas_tint : source_color = vec4(0.68, 0.23, 0.17, 1.0);
uniform vec2 wind_direction = vec2(0.94, -0.34);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.65;
uniform float motion_scale : hint_range(0.0, 1.0) = 1.0;
uniform float phase = 0.0;
uniform bool four_corner_pin = false;

void vertex() {
	// Banner UV.y=0 is sewn to the fixed header. Canopy boundaries are fixed
	// to all four uprights. Flutter never moves an attachment point.
	float free_weight = four_corner_pin
		? sin(UV.x * 3.141593) * sin(UV.y * 3.141593)
		: smoothstep(0.0, 0.35, UV.y) * UV.y;
	float gust = sin(TIME * 1.7 + phase + UV.x * 4.0) * 0.65
		+ sin(TIME * 2.6 + phase * 1.7 + UV.y * 6.0) * 0.35;
	vec3 local_wind = (inverse(MODEL_MATRIX) * vec4(wind_direction.x, 0.0, wind_direction.y, 0.0)).xyz;
	VERTEX += local_wind * (0.065 + gust * 0.105) * free_weight * wind_strength * motion_scale;
	if (four_corner_pin) {
		VERTEX.y += gust * 0.055 * free_weight * wind_strength * motion_scale;
	}
}

void fragment() {
	vec3 weave = texture(canvas_texture, UV).rgb;
	ALBEDO = weave * canvas_tint.rgb;
	ROUGHNESS = 0.96;
}
