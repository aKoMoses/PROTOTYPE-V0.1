shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform bool ground_stamp = false;
varying vec4 instance_tint;

void vertex() {
	instance_tint = COLOR;
}

void fragment() {
	ALBEDO = instance_tint.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.16;
	float opacity = instance_tint.a;
	if (ground_stamp) {
		vec2 p = UV * 2.0 - 1.0;
		float irregular = sin(p.x * 23.0 + p.y * 11.0) * 0.055;
		float edge = 1.0 - smoothstep(0.65, 1.0, length(p * vec2(1.0, 0.86)) + irregular);
		float tread = mix(0.48, 1.0, smoothstep(0.3, 0.55, fract(UV.y * 7.0 + UV.x * 0.15)));
		opacity *= edge * tread;
	}
	ALPHA = opacity;
}
