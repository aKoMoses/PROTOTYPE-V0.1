shader_type spatial;
render_mode specular_schlick_ggx;

uniform vec4 stone_color : source_color = vec4(0.7, 0.65, 0.5, 1.0);
uniform vec4 joint_color : source_color = vec4(0.15, 0.17, 0.17, 1.0);
uniform vec4 metal_color : source_color = vec4(0.55, 0.4, 0.2, 1.0);
uniform int style = 0;
uniform float surface_roughness = 0.83;
uniform float surface_metallic = 0.0;
varying vec3 world_pos;
varying vec3 mesh_pos;

float hash(vec2 p) {
    vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float smooth_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), f.x), f.y);
}
// Inlays are measured in metres and filtered at the actual camera pixel size.
// Unfiltered high frequency random pixels sparkle as the duel camera moves.
float stroke(float distance_to_line, float half_width) {
    float aa = max(fwidth(distance_to_line) * 0.75, 0.001);
    return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(distance_to_line));
}
float band(float r, float inner_radius, float outer_radius) {
    float aa = max(fwidth(r), 0.001);
    return smoothstep(inner_radius - aa, inner_radius + aa, r) * (1.0 - smoothstep(outer_radius - aa, outer_radius + aa, r));
}
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    mesh_pos = VERTEX;
}
void fragment() {
    // Steel ring engraving turns with the exact physical angle from runtime.
    vec2 p = style == 3 ? mesh_pos.xz : world_pos.xz;
    float r = length(p);
    float angle = atan(p.y, p.x);
    float mineral = smooth_noise(p * 0.85);
    float fine = smooth_noise(p * 7.0);
    vec3 col = stone_color.rgb * (0.93 + mineral * 0.10 + fine * 0.025);
    float metal = 0.0;
    float roughness = surface_roughness;
    float relief = 0.0;
    if (style == 0 || style == 1 || style == 2) {
        vec2 tile_size = style == 1 ? vec2(1.65) : vec2(2.5, 1.5);
        vec2 tiles = p / tile_size;
        if (style == 0) {
            tiles.x += mod(floor(tiles.y), 2.0) * 0.5;
        }
        vec2 edge = (0.5 - abs(fract(tiles) - 0.5)) * tile_size;
        float seam_distance = min(edge.x, edge.y);
        float joints = stroke(seam_distance, style == 1 ? 0.012 : 0.009);
        float bevel = 1.0 - smoothstep(0.015, 0.07, seam_distance);
        col *= 0.95 + hash(floor(tiles)) * 0.10;
        col = mix(col, joint_color.rgb, joints * 0.43);
        col *= 1.0 - bevel * 0.035;
        relief = (1.0 - bevel) * 0.009;
    }
    if (style == 0) {
        // Carved wind rose with alternating facets and concentric brass scales.
        float sector = abs(fract(angle / 6.2831853 * 8.0 + 0.5) - 0.5) * 2.0;
        float rose_edge = 1.6 + pow(1.0 - sector, 2.3) * 4.6;
        float rose = band(r, 1.6, rose_edge);
        float half_petals = step(0.0, sin(angle * 8.0));
        col = mix(col, stone_color.rgb * mix(vec3(0.58, 0.62, 0.61), vec3(1.08, 1.02, 0.85), half_petals), rose * 0.62);
        float contours = stroke(r - rose_edge, 0.022) * band(r, 1.6, 6.25);
        float rings = max(stroke(r - 6.7, 0.022), stroke(r - 6.91, 0.012));
        float rays = stroke(sin(angle * 16.0) * r / 16.0, 0.018) * band(r, 6.72, 7.08);
        metal = max(max(contours, rings), max(rays, stroke(r - 1.52, 0.024)));
        col *= 1.0 - smoothstep(8.3, 11.5, r) * (0.045 + mineral * 0.03);
        roughness = 0.79;
    } else if (style == 1) {
        // Teal mosaic border, mineral terrazzo and a quiet botanical medallion.
        float fleck = smoothstep(0.86, 0.96, smooth_noise(p * 11.0));
        col = mix(col, vec3(0.40, 0.60, 0.54), fleck * 0.23);
        float perimeter = max(abs(p.x), abs(p.y));
        float border = band(perimeter, 8.65, 9.20);
        float diamond = abs(fract((p.x + p.y) * 1.8) - 0.5) + abs(fract((p.x - p.y) * 1.8) - 0.5);
        col = mix(col, mix(vec3(0.15, 0.34, 0.32), vec3(0.48, 0.65, 0.56), smoothstep(0.43, 0.57, diamond)), border * 0.65);
        float petal_edge = 2.35 + cos(angle * 4.0) * 0.68;
        col = mix(col, stone_color.rgb * vec3(0.80, 0.97, 0.90), band(r, 0.55, petal_edge) * 0.44);
        metal = max(stroke(r - petal_edge, 0.013), max(stroke(perimeter - 8.60, 0.018), stroke(perimeter - 9.23, 0.017)));
        roughness = 0.55 + fine * 0.06;
    } else if (style == 2) {
        // Enamel dial with alternating chapter panels, seconds and nested rings.
        float sector = floor((angle + 3.14159265) / 6.2831853 * 24.0);
        float enamel = band(r, 4.85, 8.15);
        col = mix(col, stone_color.rgb * mix(vec3(0.57, 0.65, 0.84), vec3(1.03, 0.95, 1.02), mod(sector, 2.0)), enamel * 0.65);
        float rings = max(max(stroke(r - 4.86, 0.020), stroke(r - 6.5, 0.019)), max(stroke(r - 8.12, 0.025), stroke(r - 8.3, 0.015)));
        float rays = stroke(sin(angle * 12.0) * r / 12.0, 0.020) * band(r, 6.2, 8.12);
        float ticks = stroke(sin(angle * 60.0) * r / 60.0, 0.018) * band(r, 7.76, 8.10);
        float small_dial = max(stroke(r - 1.08, 0.020), stroke(r - 1.22, 0.011));
        metal = max(max(rings, rays), max(ticks, small_dial));
        roughness = mix(0.74, 0.52, enamel);
    } else if (style == 3) {
        float sector = floor((angle + 3.14159265) / 6.2831853 * 32.0);
        float radial_joint = stroke(sin(angle * 16.0) * r / 16.0, 0.017) * band(r, 1.03, 7.60);
        float ring_joint = max(stroke(r - 4.0, 0.035), stroke(r - 7.6, 0.033));
        float brushing = sin(r * 90.0) * (1.0 - smoothstep(0.02, 0.08, fwidth(r))) * 0.012;
        col = stone_color.rgb * (0.89 + mineral * 0.15 + brushing + mod(sector, 2.0) * 0.06);
        float groove = max(radial_joint, ring_joint);
        col = mix(col, joint_color.rgb * 0.48, groove * 0.88);
        float rivet_track = max(stroke(r - 3.76, 0.009), stroke(r - 7.32, 0.009));
        float indices = stroke(sin(angle * 16.0) * r / 16.0, 0.046) * band(r, 7.02, 7.30);
        col = mix(col, metal_color.rgb, max(rivet_track, indices) * 0.38);
        metal = 0.58;
        roughness = 0.53 + mineral * 0.13;
        relief = -groove * 0.012;
    } else if (style == 4) {
        // Nacre marquetry: twelve petals and a blue ceramic sound rose.
        float radial = length(p * vec2(0.82, 1.0));
        float sector = floor((angle + 3.14159265) / 6.2831853 * 12.0);
        float pearl = sin(angle * 12.0 + radial * 0.72) * 0.5 + 0.5;
        vec3 cool = stone_color.rgb * vec3(0.78, 0.96, 1.03);
        vec3 rose = stone_color.rgb * vec3(1.04, 0.87, 0.94);
        col = mix(cool, rose, pearl * 0.52 + mod(sector, 2.0) * 0.18) * (0.94 + mineral * 0.07);
        float petals = stroke(sin(angle * 6.0) * r / 6.0, 0.013) * band(radial, 2.28, 7.25);
        float outline = max(stroke(radial - 2.25, 0.025), max(stroke(radial - 6.95, 0.018), stroke(radial - 7.22, 0.012)));
        float rose_edge = 1.44 + cos(angle * 6.0) * 0.38;
        col = mix(col, stone_color.rgb * vec3(0.35, 0.61, 0.76), band(radial, 0.34, rose_edge) * 0.72);
        metal = max(max(petals, outline), max(stroke(radial - rose_edge, 0.017), stroke(radial - 0.34, 0.023)));
        roughness = 0.45 + fine * 0.08;
    } else if (style == 8) {
        vec2 natural = p + world_pos.y * vec2(0.63, -0.31);
        float variation = smooth_noise(natural * 0.85);
        float strata = sin(world_pos.y * 11.0 + smooth_noise(p * 0.4) * 4.0) * 0.5 + 0.5;
        float vein = pow(1.0 - abs(smooth_noise(natural * 0.8 + vec2(strata * 0.35)) * 2.0 - 1.0), 14.0);
        col = stone_color.rgb * (0.90 + variation * 0.13 + fine * 0.025 + strata * 0.035);
        col = mix(col, stone_color.rgb * vec3(0.76, 0.82, 0.81), vein * 0.10);
    } else {
        vec2 patina_uv = p * 0.5 + world_pos.y * vec2(0.52, 0.72);
        float variation = smooth_noise(patina_uv * 1.8);
        float wear = smoothstep(0.55, 0.80, smooth_noise(patina_uv * 5.0));
        float along = world_pos.x + world_pos.y;
        float brushing = sin(along * 170.0) * (1.0 - smoothstep(0.012, 0.04, fwidth(along))) * 0.012;
        col = stone_color.rgb * (0.86 + variation * 0.18 + brushing);
        col = mix(col, stone_color.rgb * vec3(0.50, 0.67, 0.65), wear * 0.15);
        roughness += wear * 0.06;
    }
    ALBEDO = style == 3 || style >= 8 ? col : mix(col, metal_color.rgb, metal * 0.82);
    METALLIC = style >= 8 ? surface_metallic : metal * 0.82;
    ROUGHNESS = style >= 8 || style == 3 ? roughness : mix(roughness, 0.34, metal);
    // Derivative bump follows the real tile bevels with no new floor geometry.
    vec3 dpdx = dFdx(VERTEX);
    vec3 dpdy = dFdy(VERTEX);
    vec3 cross_y = cross(dpdy, NORMAL);
    vec3 cross_x = cross(NORMAL, dpdx);
    float determinant = dot(dpdx, cross_y);
    vec3 gradient = sign(determinant) * (dFdx(relief) * cross_y + dFdy(relief) * cross_x);
    NORMAL = normalize(abs(determinant) * NORMAL - gradient + NORMAL * 0.0000001);
}
