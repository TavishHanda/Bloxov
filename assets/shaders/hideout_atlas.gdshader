// kit_atlas.gdshader for the hideout, with the bunks' lights switch (hideout_dark.gdshaderinc).
shader_type spatial;

#include "res://assets/shaders/hideout_dark.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
const vec2 CELL = vec2(1.0 / 16.0, 1.0 / 16.0);
const vec2 GRID_TO_ATLAS = vec2(0.5, 0.5);

void fragment() {
	vec2 inside = fract(UV) * CELL;
	vec4 texel = textureGrad(atlas, UV2 * GRID_TO_ATLAS + inside, dFdx(UV) * CELL, dFdy(UV) * CELL);
	ALBEDO = texel.rgb * COLOR.rgb * bunks_light();
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
