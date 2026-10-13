// Building kit atlas (World art 0.17, performance: one material for every tiling kit texture of a building).
// art_source/scripts/make_building.py packs the kit textures into one atlas (assets/textures/kit_atlas.png,
// an 8 x 8 grid of 64 px cells) and gives every vertex two UVs: UV = where it is in its texture (tiles, can run
// past 1), UV2 = the top-left corner of that texture's cell. The texture repeats inside its cell here.
// Lit like the imported materials (matte), times the baked sky light in the vertex colour.
shader_type spatial;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
const float CELL = 0.125;

void fragment() {
	vec2 inside = fract(UV) * CELL;
	// Mip level from the unwrapped UV, so there's no seam where the texture wraps round inside its cell.
	vec4 texel = textureGrad(atlas, UV2 + inside, dFdx(UV) * CELL, dFdy(UV) * CELL);
	ALBEDO = texel.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
