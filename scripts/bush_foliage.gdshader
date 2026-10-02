shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Each clump is one opaque mesh: no alpha sorting or per-blade draw calls.
uniform vec3 local_actor_position = vec3(0.0);
uniform float local_actor_influence = 0.0;
uniform float wind_phase = 0.0;
uniform vec2 wind_direction = vec2(0.94, -0.34);
uniform float wind_strength = 0.65;

void vertex() {
	float tip = UV.y * UV.y;
	vec3 world_base = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.25 + world_base.x * 0.8 + world_base.z * 0.57 + wind_phase);
	float flutter = sin(TIME * 2.1 + world_base.z * 2.4 + wind_phase) * 0.018;
	vec2 breeze = normalize(wind_direction + vec2(0.0001)) * (gust * 0.060 + flutter) * wind_strength;
	VERTEX.xz += breeze * tip;
	vec2 away = VERTEX.xz - local_actor_position.xz;
	float distance_to_actor = length(away);
	float response = (1.0 - smoothstep(0.18, 0.95, distance_to_actor)) * local_actor_influence;
	VERTEX.xz += away / max(distance_to_actor, 0.08) * response * tip * 0.30;
	VERTEX.y -= response * tip * 0.12;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(0.97, 0.84, UV.y);
	SPECULAR = 0.16;
	// A little wrapped leaf light keeps the dark roots readable from above.
	EMISSION = COLOR.rgb * UV.y * 0.035;
}
