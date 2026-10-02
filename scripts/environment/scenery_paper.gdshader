shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform float clock = 0.0;
varying vec4 tint;
varying float phase;
void vertex() {
	tint = COLOR;
	phase = INSTANCE_CUSTOM.x;
	float corner = smoothstep(0.35, 1.0, UV.x) * smoothstep(0.05, 0.95, UV.y);
	VERTEX.y += corner * (0.018 + INSTANCE_CUSTOM.y * 0.07)
		* (0.6 + 0.4 * sin(clock * 3.1 + phase + UV.x * 2.7));
}
void fragment() {
	float crease = 1.0 - smoothstep(0.015, 0.075, abs(UV.x + UV.y * 0.30 - 0.63));
	float edge = smoothstep(0.02, 0.12, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	float ink = step(0.20, UV.x) * step(UV.x, 0.78) * step(0.30, UV.y) * step(UV.y, 0.68)
		* step(0.62, fract(UV.y * 18.0 + sin(UV.x * 5.0 + phase) * 0.16));
	ALBEDO = tint.rgb * (0.70 + edge * 0.23 - crease * 0.09 - ink * 0.22);
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
