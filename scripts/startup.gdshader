shader_type canvas_item;
render_mode unshaded;

uniform float clock = 0.0;
varying vec4 modulation;

void vertex() {
	modulation = COLOR;
}

void fragment() {
	// Only the existing cyan reactor and visor breathe; the illustration stays sharp.
	vec4 art = texture(TEXTURE, UV);
	float cyan = smoothstep(0.10, 0.38, min(art.g, art.b) - art.r);
	float pulse = 0.06 + 0.14 * (0.5 + 0.5 * sin(clock * 2.3));
	art.rgb += vec3(0.02, 0.22, 0.26) * cyan * pulse;
	COLOR = art * modulation;
}
