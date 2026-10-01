shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec2 field_size = vec2(4.0, 2.4);
uniform float strength = 1.0;
uniform vec2 impact_uv = vec2(0.5);
uniform float impact_age = 10.0;

void fragment() {
	vec2 p = UV * field_size / 0.30;
	// Staggered hexagonal cells keep the energy readable at the game camera.
	vec2 lattice = vec2(1.0, 1.73205);
	vec2 a = mod(p, lattice) - lattice * 0.5;
	vec2 b = mod(p - lattice * 0.5, lattice) - lattice * 0.5;
	vec2 cell = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(cell);
	float hex = max(q.x, q.x * 0.5 + q.y * 0.866025);
	float grid = smoothstep(0.46, 0.5, hex);
	float edge = 1.0 - smoothstep(0.0, 0.075, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	float sweep = pow(0.5 + 0.5 * sin(UV.y * 18.0 - TIME * 4.0), 16.0);
	float distance_to_hit = length((UV - impact_uv) * field_size);
	float ring = (1.0 - smoothstep(0.035, 0.11, abs(distance_to_hit - impact_age * 4.8))) * max(0.0, 1.0 - impact_age * 2.4);
	float core = exp(-distance_to_hit * 8.0) * max(0.0, 1.0 - impact_age * 4.0);
	vec3 cyan = vec3(0.12, 0.78, 0.92);
	ALBEDO = mix(cyan, vec3(0.74, 1.0, 1.0), edge * 0.55 + ring * 0.8);
	EMISSION = ALBEDO * (0.5 + ring * 2.0 + core * 3.0);
	ALPHA = clamp((0.055 + grid * 0.21 + edge * 0.33 + sweep * 0.09 + ring * 0.6 + core * 0.6) * strength, 0.0, 0.92);
}
