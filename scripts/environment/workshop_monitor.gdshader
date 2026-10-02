shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float clock = 0.0;
uniform float phase = 0.0;
uniform float working = 1.0;
uniform float power = 1.0;
uniform vec4 screen_tint : source_color = vec4(0.2, 0.8, 0.76, 1.0);

float line(float at, float width) {
	return 1.0 - smoothstep(width, width * 2.0, abs(at));
}
void fragment() {
	vec2 p = UV;
	float glitch = 1.0 - step(0.08, mod(clock + phase * 3.0, 13.7));
	p.x += sin(floor(p.y * 26.0) * 7.0 + clock * 12.0) * glitch * 0.014;
	float grid = max(line(fract(p.x * 8.0) - 0.5, 0.015), line(fract(p.y * 5.0) - 0.5, 0.015)) * 0.14;
	float trace = 0.52 + sin(p.x * 12.0 - clock * 1.7 + phase) * 0.13
		+ sin(p.x * 27.0 - clock * 0.9) * 0.045 * working;
	float chart = line(p.y - trace, 0.016) * step(0.08, p.x) * step(p.x, 0.92);
	float gauge = step(0.1, p.x) * step(p.x, 0.9) * step(0.80, p.y) * step(p.y, 0.89)
		* step(p.x, 0.25 + 0.62 * (0.5 + 0.5 * sin(clock * 0.35 + phase)));
	float diagram = line(length((p - vec2(0.78, 0.25)) * vec2(1.0, 1.2)) - 0.13, 0.009)
		+ line(p.x - 0.78, 0.007) * step(p.y, 0.25) * step(0.11, p.y);
	float scan = 0.97 + 0.03 * sin(p.y * 145.0);
	vec3 face = vec3(0.012, 0.025, 0.026) + screen_tint.rgb * (grid + chart * 0.72 + gauge * 0.7 + diagram * 0.26);
	ALBEDO = face * mix(0.10, 1.0, power) * scan;
	EMISSION = face * power * 0.55;
}
