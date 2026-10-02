shader_type spatial;
render_mode cull_disabled;

uniform sampler2D canvas_texture : source_color, filter_linear_mipmap;
uniform vec4 canvas_tint : source_color = vec4(0.68, 0.23, 0.17, 1.0);
uniform vec2 wind_direction = vec2(0.94, -0.34);
uniform float wind_strength : hint_range(0.0, 1.0) = 0.65;
uniform float motion_scale : hint_range(0.0, 1.0) = 1.0;
uniform float phase = 0.0;
uniform bool four_corner_pin = false;
uniform bool gear_banner = false;
uniform float fabric_aspect = 2.0;
uniform vec3 organic_impulse_origin = vec3(0.0);
uniform vec2 organic_impulse_direction = vec2(0.0);
uniform float organic_impulse_strength = 0.0;
uniform float organic_impulse_age = 0.0;

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
	// Pressure waves tug the free fabric; sewn headers and corner pins stay put.
	float response = sin(organic_impulse_age * 12.0 + UV.x * 2.0)
		* exp(-organic_impulse_age * 3.0) * organic_impulse_strength;
	vec3 push = (inverse(MODEL_MATRIX) * vec4(organic_impulse_direction.x, 0.25, organic_impulse_direction.y, 0.0)).xyz;
	VERTEX += push * response * free_weight * 0.28 * motion_scale;
}

void fragment() {
	vec3 weave = texture(canvas_texture, UV).rgb;
	// Separate the painted insignia from the fabric pigment: multiplying the
	// cream gear by red canvas made it disappear in the old banner.
	float crease = sin(UV.x * 28.0 + sin(UV.y * 4.0) * 2.0) * 0.11;
	float edge_dust = smoothstep(0.70, 1.0, UV.y) * 0.14;
	ALBEDO = mix(vec3(0.78), weave, 0.25) * canvas_tint.rgb * (1.0 + crease + edge_dust);
	if (gear_banner) {
		vec2 p = (UV - vec2(0.5, 0.52)) * vec2(fabric_aspect, 1.0);
		float radius = length(p);
		float angle = atan(p.y, p.x);
		float edge = 0.215 + 0.037 * smoothstep(-0.18, 0.18, cos(angle * 12.0));
		float gear = (1.0 - smoothstep(edge - 0.007, edge + 0.007, radius))
			* smoothstep(0.12, 0.13, radius);
		float rubbed = smoothstep(0.05, 0.22, fract(sin(dot(floor(UV * 320.0), vec2(12.9898, 78.233))) * 43758.5453));
		ALBEDO = mix(ALBEDO, vec3(0.63, 0.55, 0.40), gear * rubbed * 0.88);
	}
	ROUGHNESS = 0.96;
}
