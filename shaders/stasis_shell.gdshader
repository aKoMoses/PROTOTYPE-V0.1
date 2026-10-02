shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform float strength = 1.0;
uniform float clock = 0.0;
uniform float release = 0.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.8);
	vec2 p = UV * vec2(28.0, 16.0);
	vec2 lattice = vec2(1.0, 1.73205);
	vec2 a = mod(p, lattice) - lattice * 0.5;
	vec2 b = mod(p - lattice * 0.5, lattice) - lattice * 0.5;
	vec2 cell = abs(dot(a, a) < dot(b, b) ? a : b);
	float hex = max(cell.x, cell.x * 0.5 + cell.y * 0.866025);
	float grid = smoothstep(0.455, 0.485, hex);
	float scan_height = 0.12 + fract(clock * 0.48) * 0.76;
	float scan = exp(-pow((UV.y - scan_height) * 65.0, 2.0));
	float poles = smoothstep(0.02, 0.15, UV.y) * (1.0 - smoothstep(0.85, 0.98, UV.y));
	float dissolve = 1.0 - smoothstep(1.0 - release - 0.06, 1.0 - release, UV.y);
	vec3 violet = vec3(0.43, 0.22, 0.95);
	vec3 ice = vec3(0.53, 0.85, 1.0);
	ALBEDO = mix(violet, ice, clamp(rim * 0.55 + scan * 0.65, 0.0, 1.0));
	EMISSION = ALBEDO * (0.35 + rim * 0.7 + scan * 0.5);
	ALPHA = clamp((0.018 + rim * 0.72 + grid * (0.04 + rim * 0.09) + scan * 0.17) * poles * strength * dissolve, 0.0, 0.8);
}
