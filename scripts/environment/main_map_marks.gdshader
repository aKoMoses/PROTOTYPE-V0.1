shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform sampler2D concrete_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wear = 0.24;
varying vec3 at;
void vertex() {
	at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float grain = texture(concrete_detail, at.xz * 0.82 + at.xy * 0.31).r;
	float broken = smoothstep(wear - 0.035, wear + 0.035, grain);
	if (broken < 0.12) { discard; }
	ALBEDO = COLOR.rgb * mix(0.72, 1.0, broken);
	ROUGHNESS = 0.96;
	SPECULAR = 0.13;
}
