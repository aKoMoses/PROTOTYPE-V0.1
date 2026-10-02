shader_type spatial;
render_mode diffuse_burley;
#include "res://scripts/environment/workshop_circuit.gdshaderinc"
uniform vec4 tube_color : source_color = vec4(0.1, 0.8, 0.9, 1.0);
uniform float emission_strength = 1.15;

void vertex() {
	live_power = circuit_power(UV2);
}
void fragment() {
	// Switched-off glass retains a dark physical tube, rather than disappearing.
	ALBEDO = mix(vec3(0.055, 0.065, 0.067), tube_color.rgb, min(live_power, 1.0));
	EMISSION = tube_color.rgb * emission_strength * live_power;
	ROUGHNESS = 0.65;
	METALLIC = 0.10;
}
