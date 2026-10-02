shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.26, 0.8, 1.0, 0.7);
uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - vec2(1.0);
	float r = length(p);
	float radius = 0.08 + (1.0 - pow(1.0 - progress, 2.0)) * 0.82;
	float wave = 1.0 - smoothstep(0.018, 0.058, abs(r - radius));
	float echo = (1.0 - smoothstep(0.012, 0.040, abs(r - radius * 0.67))) * 0.3;
	vec2 lattice = vec2(1.0, 1.73205);
	vec2 h = p * 9.0;
	vec2 a = mod(h, lattice) - lattice * 0.5;
	vec2 b = mod(h - lattice * 0.5, lattice) - lattice * 0.5;
	vec2 cell = abs(dot(a, a) < dot(b, b) ? a : b);
	float hex = max(cell.x, cell.x * 0.5 + cell.y * 0.866025);
	float grid = smoothstep(0.44, 0.49, hex) * (1.0 - smoothstep(radius, radius + 0.09, r));
	float fade = 1.0 - smoothstep(0.20, 1.0, progress);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 0.6;
	ALPHA = clamp((wave + echo + grid * 0.12) * fade * tint.a, 0.0, 0.8);
}
