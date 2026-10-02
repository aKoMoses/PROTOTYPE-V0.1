// Each vertex carries its authored circuit and letter in UV2. No world search
// or noise-driven rapid flashing is done in the fragment stage.
uniform vec4 circuit_values[128];
uniform float ambient_time = 0.0;
varying float live_power;

float circuit_power(vec2 tag) {
	vec4 state = circuit_values[clamp(int(tag.x + 0.5), 0, 127)];
	float power = state.x;
	if (tag.y >= 0.0 && abs(floor(tag.y) - state.y) < 0.4) {
		power *= state.z;
	} else if (tag.y < -1.5) {
		// Status LEDs breathe or show a short machine-work pulse.
		float beat = sin(ambient_time * 1.6 + tag.x * 0.73);
		power *= 0.55 + 0.45 * beat * beat;
	}
	return clamp(power + state.w, 0.0, 1.6);
}
