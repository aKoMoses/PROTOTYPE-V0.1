shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// This lives inside the actor's visibility root and composes with vision fades.
uniform float visibility_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float visibility_silhouette : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 point = (UV - vec2(0.5)) * vec2(2.0, 2.5);
	float radius = length(point);
	float contact = exp(-radius * radius * 4.8) * (1.0 - smoothstep(0.65, 1.0, radius));
	ALBEDO = vec3(0.035, 0.041, 0.052);
	ALPHA = contact * 0.30 * visibility_opacity * (1.0 - visibility_silhouette);
}
