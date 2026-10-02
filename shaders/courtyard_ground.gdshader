shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D layout_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D concrete_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.68;
varying vec2 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec3 layout = texture(layout_albedo, UV).rgb;
	vec2 tile = ground_position * 0.16;
	vec3 detail = texture(concrete_detail, tile).rgb;
	// A second scale suppresses obvious repeated crack patterns.
	vec3 second = texture(concrete_detail, mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * tile * 1.73 + vec2(0.31, 0.67)).rgb;
	vec3 variation = clamp(mix(detail, second, 0.24) / vec3(0.37, 0.34, 0.29), vec3(0.62), vec3(1.36));
	float steel = smoothstep(0.005, 0.045, layout.b - layout.r);
	ALBEDO = layout * mix(vec3(1.0), variation, detail_strength * (1.0 - steel * 0.7));
	NORMAL_MAP = texture(surface_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.55;
	ROUGHNESS = mix(0.96, 0.77, steel);
	METALLIC = steel * 0.22;
	SPECULAR = 0.18;
}
