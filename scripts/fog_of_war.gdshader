shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D cover_from : filter_linear_mipmap, repeat_disable;
uniform sampler2D cover_target : filter_linear_mipmap, repeat_disable;
uniform vec3 observer_position = vec3(0.0);
uniform float vision_radius = 22.0;
uniform float vision_fade_width = 8.0;
uniform float mask_world_size = 108.0;
uniform float filter_lod = 1.5;
uniform float edge_irregularity = 0.16;
uniform float fog_darkness : hint_range(0.0, 1.0) = 0.66;
uniform vec4 fog_color : source_color = vec4(0.018, 0.025, 0.036, 1.0);
uniform float profile_blend : hint_range(0.0, 1.0) = 1.0;

float hash_value(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float world_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash_value(cell), hash_value(cell + vec2(1.0, 0.0)), fraction.x),
		mix(hash_value(cell + vec2(0.0, 1.0)), hash_value(cell + vec2(1.0, 1.0)), fraction.x), fraction.y);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	if (depth <= 0.000001) {
		discard;
	}
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec2 world_point = world.xz / world.w;
	float distance_to_observer = length(world_point - observer_position.xz);
	float full_radius = max(0.0, vision_radius - vision_fade_width);
	float radial_visibility = 1.0 - smoothstep(full_radius, max(full_radius + 0.001, vision_radius), distance_to_observer);
	if (distance_to_observer >= vision_radius) {
		radial_visibility = 0.0;
	}
	if (vision_fade_width <= 0.0) {
		radial_visibility = 1.0 - step(vision_radius, distance_to_observer);
	}
	// Very small world-anchored variations break the ruler-straight shoulders.
	// No TIME or screen UV enters the noise: it cannot swim with the camera.
	vec2 variation = vec2(world_noise(world_point * 0.43), world_noise(world_point * 0.43 + vec2(13.1, 7.7))) - vec2(0.5);
	vec2 mask_uv = (world_point + variation * edge_irregularity) / mask_world_size + vec2(0.5);
	float cover_visibility = 0.0;
	if (all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThanEqual(mask_uv, vec2(1.0)))) {
		float old_visibility = textureLod(cover_from, mask_uv, filter_lod).r;
		float new_visibility = textureLod(cover_target, mask_uv, filter_lod).r;
		cover_visibility = smoothstep(0.12, 0.88, mix(old_visibility, new_visibility, profile_blend));
	}
	float visibility = radial_visibility * cover_visibility;
	ALBEDO = fog_color.rgb;
	ALPHA = fog_darkness * (1.0 - visibility);
}
