shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Chalk Line Shader (Street Sidewalk Chalk on Rough Asphalt)
uniform vec4 chalk_color : source_color = vec4(0.96, 0.96, 0.95, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.92;
uniform float dust_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.45;

// Pseudo-random hash for procedural chalk grain without heavy textures
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// World position mapping for consistent texture scale regardless of mesh size
	vec2 world_uv = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	
	// Multi-octave chalk grain
	float n1 = noise(world_uv * 12.0);
	float n2 = noise(world_uv * 36.0);
	float chalk_grain = mix(n1, n2, 0.4);
	
	// Roughness variation (chalk is dry and powdery)
	ROUGHNESS = mix(roughness, 1.0, chalk_grain * 0.3);
	SPECULAR = 0.15;
	
	// Subtle chalk thickness modulation: chalk is denser in the middle of strokes
	float density = 0.85 + (chalk_grain * 0.25 * dust_intensity);
	
	// Soft emission gives the white chalk visible brightness in twilight/afternoon shadows
	vec3 base_rgb = chalk_color.rgb * density;
	ALBEDO = base_rgb;
	EMISSION = chalk_color.rgb * 0.12;
}
