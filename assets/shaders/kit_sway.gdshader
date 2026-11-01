// What sways in the wind (0.28.0, owner: give the world some life; tools/building_import.gd): power lines, tent canvas
// and camo nets in the outdoor chunks, drawn from the kit atlas like kit_atlas.gdshader. The vertex colour isn't light
// here: r is how far a corner sways with the slow wind (a wire's middle, a net's loose edge; 0 where it's tied), g how
// much it ripples quickly (canvas, net). Looks only: what they collide with doesn't move.
shader_type spatial;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
const vec2 CELL = vec2(1.0 / 16.0, 1.0 / 16.0);
const vec2 GRID_TO_ATLAS = vec2(0.5, 0.5);
const vec3 WIND = vec3(0.64, 0.0, 0.77);

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float gust = 0.7 + 0.3 * sin(t * 0.29 + world.x * 0.01);
	// the slow sway: the whole span together (it changes slowly along the map, not along a wire)
	float slow = sin(t * 1.15 + world.x * 0.04 + world.z * 0.03) * 0.6 + 0.4;
	vec3 sway = (WIND * slow + vec3(0.0, -0.25 * slow, 0.0)) * 0.3 * COLOR.r * gust;
	// the ripple: quick little waves running through the cloth
	float r = sin(t * 4.3 - dot(world.xz, vec2(2.1, 1.6))) + 0.5 * sin(t * 6.7 - dot(world.xz, vec2(-1.3, 2.7)));
	vec3 ripple = (NORMAL * 0.8 + WIND * 0.3) * r * 0.06 * COLOR.g * gust;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * sway) + ripple;
}

void fragment() {
	vec2 inside = fract(UV) * CELL;
	vec4 texel = textureGrad(atlas, UV2 * GRID_TO_ATLAS + inside, dFdx(UV) * CELL, dFdy(UV) * CELL);
	ALBEDO = texel.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
