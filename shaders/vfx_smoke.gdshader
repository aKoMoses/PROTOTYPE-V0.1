shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D puff_texture : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(0.24, 0.25, 0.27, 0.3);
uniform float progress = 0.0;
uniform float spin = 0.0;

void vertex() {
	// Camera-facing quad, retaining its authored world size.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
	facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
	facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float angle = spin + progress * 0.22;
	p = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p;
	vec2 warp = vec2(sin(p.y * 13.0 + progress * 2.0), cos(p.x * 11.0 - progress * 1.7));
	vec2 sample_uv = p + vec2(0.5) + warp * 0.022 * progress;
	float envelope = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.26, 1.0, progress));
	ALBEDO = tint.rgb;
	ALPHA = texture(puff_texture, sample_uv).a * tint.a * envelope;
}
