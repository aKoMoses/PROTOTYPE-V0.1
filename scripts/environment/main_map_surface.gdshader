shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 at;
varying vec3 world_normal;
void vertex() {
	at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	float grain = texture(detail, at.zy * 0.55).r * weights.x
		+ texture(detail, at.xz * 0.55).r * weights.y
		+ texture(detail, at.xy * 0.55).r * weights.z;
	float patina = texture(detail, at.xy * 0.15 + at.zy * 0.13).r;
	ALBEDO = COLOR.rgb * clamp(0.89 + grain * 0.38, 0.89, 1.10);
	ALBEDO *= 1.0 - (1.0 - smoothstep(0.03, 0.55, at.y)) * patina * 0.35;
	METALLIC = COLOR.a * 0.62;
	ROUGHNESS = mix(0.91, 0.48, COLOR.a);
	SPECULAR = 0.30;
}
