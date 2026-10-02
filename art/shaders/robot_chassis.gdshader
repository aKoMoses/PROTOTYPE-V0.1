shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform vec4 panel_color : source_color;
uniform vec4 accent_color : source_color;
uniform vec4 fabric_color : source_color;
uniform vec4 pack_color : source_color;
uniform float source_roughness = 0.9;
uniform float source_metallic = 0.0;
uniform float panel_roughness = 0.6;
uniform float panel_metallic = 0.15;
uniform float visibility_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float visibility_silhouette : hint_range(0.0, 1.0) = 0.0;
// 0: painted armour, 1: existing cloth, 2: backpack canvas.
uniform int part_role = 0;

vec3 to_srgb(vec3 linear_color) {
	return mix(linear_color * 12.92, 1.055 * pow(max(linear_color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), linear_color));
}

void fragment() {
	vec3 source = texture(base_texture, UV).rgb * source_tint.rgb;
	vec3 rgb = to_srgb(source);
	float value = max(max(rgb.r, rgb.g), rgb.b);
	float saturation = (value - min(min(rgb.r, rgb.g), rgb.b)) / max(value, 0.001);
	float brightness = max(max(source.r, source.g), source.b);
	// Cyan lenses and the reactor keep their authored colour and finish.
	float cyan = step(rgb.r * 1.2, min(rgb.g, rgb.b)) * step(0.18, rgb.g);
	float neutral = (1.0 - smoothstep(0.20, 0.43, saturation)) * smoothstep(0.28, 0.57, value);
	float orange = smoothstep(1.12, 1.38, rgb.r / max(rgb.g, 0.001)) * smoothstep(1.16, 1.55, rgb.g / max(rgb.b, 0.001)) * smoothstep(0.36, 0.48, rgb.g / max(rgb.r, 0.001));
	float red = smoothstep(1.5, 2.2, rgb.r / max(max(rgb.g, rgb.b), 0.001)) * smoothstep(0.16, 0.38, value);
	vec3 colour = source;
	float metal_mask = 0.0;
	if (part_role == 0) {
		float panel_mask = neutral * (1.0 - cyan);
		float accent_mask = orange * (1.0 - cyan);
		colour = mix(colour, panel_color.rgb * clamp(brightness / 0.72, 0.0, 1.4), panel_mask);
		colour = mix(colour, accent_color.rgb * clamp(brightness / 0.55, 0.0, 1.4), accent_mask);
		// The torso texture also contains the front of the neck scarf.
		float cloth_mask = red * (1.0 - orange) * (1.0 - cyan);
		colour = mix(colour, fabric_color.rgb * clamp(brightness / 0.40, 0.0, 1.4), cloth_mask);
		metal_mask = max(panel_mask, accent_mask);
	} else if (part_role == 1) {
		// Authored fabric contains desaturated red in its folds and weathering.
		float cloth_mask = smoothstep(1.05, 1.45, rgb.r / max(max(rgb.g, rgb.b), 0.001)) * smoothstep(0.04, 0.16, saturation);
		colour = mix(colour, fabric_color.rgb * clamp(brightness / 0.40, 0.0, 1.4), cloth_mask * (1.0 - cyan));
	} else {
		// Keep the canvas grain, seams and dark backpack straps.
		float canvas = smoothstep(0.25, 0.55, value) * (1.0 - cyan);
		colour = mix(colour, pack_color.rgb * clamp(brightness / 0.52, 0.0, 1.4), canvas);
	}
	ALBEDO = mix(colour, vec3(0.32, 0.39, 0.48), visibility_silhouette * 0.88);
	ALPHA = visibility_opacity;
	ROUGHNESS = part_role == 0 ? mix(source_roughness, panel_roughness, metal_mask) : source_roughness;
	METALLIC = part_role == 0 ? mix(source_metallic, panel_metallic, metal_mask) : source_metallic;
	RIM = part_role == 0 ? 0.22 : 0.0;
	RIM_TINT = 0.25;
	EMISSION = source * cyan * 0.18 * (1.0 - visibility_silhouette);
}
