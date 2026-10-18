// The creek's water (World art 0.17, outdoor step 6): BoxMap's water ribbon, UV.x across it (metres from the middle
// line), UV.y along it (metres downstream) and UV2.x how deep the water is there (BoxMap measures it down to the
// ground at each of its points, so the shader needs no depth texture and stays cheap on phones). One small texture
// (art_source/scripts/make_water.py) scrolls downstream in two layers for the ripples and the foam. Deep in the middle, clear in the shallows, the sky's colour at a glancing angle, foam along the
// banks and round the rocks in `rocks`.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D ripples_px : filter_nearest_mipmap, repeat_enable;
uniform sampler2D ripples_smooth : filter_linear_mipmap, repeat_enable;
uniform float pixel = 1.0;            // 1: pixel ripples like the ground tiles; 0: smooth
uniform vec3 deep : source_color = vec3(0.08, 0.22, 0.27);
uniform vec3 shallow : source_color = vec3(0.30, 0.46, 0.40);
uniform vec3 sky : source_color = vec3(0.62, 0.74, 0.86);
uniform vec3 foam_colour : source_color = vec3(0.86, 0.89, 0.88);
uniform float alpha_edge = 0.25;      // how see-through the shallows are (0 clear) ...
uniform float alpha_deep = 0.88;      // ... and the middle
uniform float sky_mix = 0.55;         // how much sky a glancing look picks up
uniform float flow = 0.7;             // metres per second downstream
uniform float tile = 2.0;             // metres per texture tile
uniform float ripple = 0.6;           // ripple strength
uniform float foam = 1.0;             // foam amount (0 none)
uniform float flecks = 1.0;           // drifting flecks (0 none)
uniform float full_depth = 0.5;       // this deep or more: the deep colour
uniform float foam_band = 0.14;       // foam where the water is shallower than this
// (x, z, radius, 0) of rocks standing in the water: foam rings round them
uniform vec4 rocks[16];
uniform int rock_count = 0;

varying vec3 world;
varying float depth;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = UV2.x;
}

vec4 rip(vec2 uv) {
	return pixel > 0.5 ? texture(ripples_px, uv) : texture(ripples_smooth, uv);
}

void fragment() {
	vec2 st = UV;
	if (pixel > 0.5) {
		float ppm = 64.0 / tile;   // (the texture's pixels a metre: 32, like the ground)
		st = (floor(st * ppm) + 0.5) / ppm;
	}
	float t = TIME * flow;
	vec4 a = rip(vec2(st.x, st.y - t) / tile);
	vec4 b = rip(vec2(st.x * 0.8 + 0.37, st.y * 0.7 - t * 0.6) / (tile * 1.6));
	vec2 slope = (a.rg + b.rg - 1.0) * ripple;
	float deepness = clamp(depth / full_depth, 0.0, 1.0);
	vec3 n = normalize(NORMAL + (VIEW_MATRIX * vec4(slope.x, 0.0, slope.y, 0.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 4.0);
	vec3 c = mix(shallow, deep, deepness);
	c = mix(c, sky, fresnel * sky_mix);
	// foam: along the waterline and round rocks, cut out of the blotchy noise so it breaks up and drifts
	// (under the bank, depth < 0, it fades out: the ground hides it there anyway)
	float edge = (1.0 - smoothstep(0.0, foam_band, depth)) * smoothstep(-0.1, 0.0, depth);
	vec2 p = world.xz;
	for (int i = 0; i < rock_count; i++) {
		vec2 d = p - rocks[i].xy;
		float ring = length(d) - rocks[i].z;
		edge = max(edge, 1.0 - smoothstep(0.0, 0.5, ring));
	}
	float blot = (a.b + b.b) * 0.5;
	float f = step(1.0 - edge * 0.75 * foam, blot);
	f = max(f, step(1.0 - 0.18 * flecks, a.a * b.b * 1.4));
	ALBEDO = mix(c, foam_colour, f);
	ALPHA = max(mix(alpha_edge, alpha_deep, deepness) + fresnel * 0.3, f * 0.9);
	NORMAL = mix(n, NORMAL, f);
	ROUGHNESS = mix(0.06, 0.85, f);
	SPECULAR = 0.6;
}
