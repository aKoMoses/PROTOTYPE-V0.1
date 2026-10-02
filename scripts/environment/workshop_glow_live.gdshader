shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://scripts/environment/workshop_circuit.gdshaderinc"
uniform vec4 tube_color : source_color = vec4(0.1, 0.8, 0.9, 1.0);

void vertex() {
	live_power = circuit_power(UV2);
}
void fragment() {
	float facing = max(0.0, dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tube_color.rgb * 0.65 * live_power;
	ALPHA = pow(facing, 2.0) * 0.18 * min(live_power, 1.0);
}
