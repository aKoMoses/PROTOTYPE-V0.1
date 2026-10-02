shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec2 world_position;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz; }
void fragment() {
	float edge = length((UV-vec2(0.5))*vec2(2.0,2.0));
	float grain = noise(world_position*5.4);
	float stain = 1.0 - smoothstep(0.32,0.98,edge + noise(world_position*2.7)*0.30);
	if (stain < 0.015) { discard; }
	ALBEDO = vec3(0.15,0.14,0.13);
	ALPHA = stain * mix(0.12,0.35,grain);
}
