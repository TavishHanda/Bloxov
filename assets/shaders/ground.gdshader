// The ground (World art 0.17, outdoor step 2): BoxMap's height grid and the outdoor kit's earth banks and crater rims.
// Pixel tiles (art_source/scripts/make_ground.py, 64 px for 2 m like the building kit) picked per pixel by world
// position: three grasses shading into each other across the map in big, slow gradients (owner 2026-10-18: "a
// gradient of the 3 grass textures"), bare earth on steep slopes, and what the generator painted into the
// splat map (tools/gen_old_bloxov.py: R worn earth, G mud, B scorched earth, A gravel). Edges between them are
// dithered pixel by pixel instead of blurred, so they stay crisp like the rest of the art.
shader_type spatial;

uniform sampler2D grass_a : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D grass_b : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D grass_c : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D earth : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D mud : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D scorch : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D gravel : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D dither : filter_nearest_mipmap, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(-175.0, -175.0);
uniform float map_size = 350.0;
uniform float tile = 2.0;            // metres per texture tile
uniform float patch_size = 140.0;    // metres per macro noise tile (the grass gradient)
uniform float cut_ab = 0.36;         // macro noise below this: grass_a; then grass_b up to cut_bc; then grass_c
uniform float cut_bc = 0.5;
uniform float blend = 0.22;          // how wide the dithered gradient between two grasses is
uniform float slope_earth = 0.36;    // 1 - normal.y where steep ground turns to bare earth
// The ground mesh's vertex colours shade hilltops lighter and slopes darker (BoxMap); relative to this colour.
uniform vec3 tint_base = vec3(0.47, 0.62, 0.36);
uniform float untinted = 0.93;       // the average of that shading, for meshes without it

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz / tile;
	float jitter = textureLod(dither, uv, 0.0).r - 0.5;
	// (far off, the per-pixel jitter would shimmer: fade it with the mip level the grass texture is drawn at)
	vec2 grad = fwidth(uv) * 64.0;
	float far = clamp(log2(max(max(grad.x, grad.y), 1.0)) / 3.0, 0.0, 1.0);
	jitter *= 1.0 - far;
	float m = texture(macro, world_pos.xz / patch_size).r;
	// (each pixel picks one grass; near a cut the pick is dithered, so one grass thins out into the next)
	float g = m + jitter * blend;
	vec3 c = g < cut_ab ? texture(grass_a, uv).rgb : g < cut_bc ? texture(grass_b, uv).rgb : texture(grass_c, uv).rgb;
	vec4 s = texture(splat, (world_pos.xz - map_origin) / map_size);
	float steep = smoothstep(slope_earth - 0.08, slope_earth + 0.08, 1.0 - world_normal.y);
	float j = jitter * 0.5;
	if (s.a + j > 0.5) c = texture(gravel, uv).rgb;
	if (s.g + j > 0.5) c = texture(mud, uv).rgb;
	if (max(s.r, steep) + j > 0.5) c = texture(earth, uv).rgb;
	if (s.b + j > 0.5) c = texture(scorch, uv).rgb;
	// (meshes without vertex colours, the earth banks, come in white: no shading from them)
	if (COLOR.r < 0.99 || COLOR.g < 0.99) {
		c *= clamp(COLOR.rgb / tint_base, vec3(0.7), vec3(1.25));
	} else {
		c *= untinted;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
