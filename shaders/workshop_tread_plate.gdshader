shader_type spatial;
render_mode diffuse_burley;
varying vec2 plate_uv;
varying vec2 ground_position;
float grain(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() {
	plate_uv = VERTEX.xz / vec2(3.2,2.1) + vec2(0.5);
	ground_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
}
void fragment() {
	vec2 grid = plate_uv * vec2(15.0,10.0);
	vec2 cell = floor(grid);
	vec2 p = fract(grid)-vec2(0.5);
	float sign = mod(cell.x+cell.y,2.0)<1.0 ? 1.0 : -1.0;
	vec2 rotated = vec2(p.x+p.y*sign,p.y-p.x*sign)*0.7071;
	float bar = (1.0-smoothstep(0.05,0.095,abs(rotated.y))) * (1.0-smoothstep(0.22,0.30,abs(rotated.x)));
	float bevel = (1.0-smoothstep(0.085,0.14,abs(rotated.y))) * (1.0-smoothstep(0.23,0.33,abs(rotated.x)));
	float edge = min(min(plate_uv.x,1.0-plate_uv.x),min(plate_uv.y,1.0-plate_uv.y));
	float rim = 1.0-smoothstep(0.012,0.035,edge);
	float bolts = 1.0-smoothstep(0.010,0.016,length(abs(plate_uv-0.5)-vec2(0.46,0.44)));
	float wear = grain(floor(ground_position*42.0));
	vec3 steel = mix(vec3(0.24,0.29,0.29),vec3(0.37,0.40,0.37),wear*0.38);
	steel = mix(steel,vec3(0.14,0.17,0.17),bevel*0.35);
	steel = mix(steel,vec3(0.52,0.53,0.45),bar*0.72);
	steel = mix(steel,vec3(0.16,0.19,0.18),rim*0.65);
	ALBEDO = mix(steel,vec3(0.63,0.51,0.30),bolts);
	ROUGHNESS = mix(0.74,0.55,bar);
	METALLIC = 0.40;
	SPECULAR = 0.30;
}
