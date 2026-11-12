// Building kit atlas (World art 0.17, performance: one material for every tiling kit texture of a building).
// art_source/scripts/make_building.py packs the kit textures into one atlas (assets/textures/kit_atlas.png,
// 16 x 16 cells of 64 px) and gives every vertex two UVs: UV = where it is in its texture (tiles, can run
// past 1), UV2 = the top-left corner of that texture's cell in 8 x 8 grid units (the atlas was 8 x 8 before it grew
// for the offices; u past 1 is the right half, v past 1 the bottom half, train station). The texture repeats inside its cell here.
// Lit like the imported materials (matte), times the baked sky light in the vertex colour.
shader_type spatial;

uniform sampler2D atlas : source_color, filter_nearest_mipmap, repeat_disable;
const vec2 GRID_TO_ATLAS = vec2(0.5, 0.5);
const float CELL_PX = 64.0;             // one atlas cell is 64 px square
const float ATLAS_PX = 1024.0;
// (0.34.12) Samples stay half a texel inside the cell: on the wrap the UV lands exactly on the cell's edge, and
// nearest filtering there picked the neighbouring cell's texel (bk_old showed bk_hazard's yellow stripes as a
// dotted line down the wall). The scale is a hair under 1, so the texture still tiles.
const vec2 INSIDE_SCALE = vec2((CELL_PX - 1.0) / ATLAS_PX, (CELL_PX - 1.0) / ATLAS_PX);
const vec2 INSIDE_OFFSET = vec2(0.5 / ATLAS_PX, 0.5 / ATLAS_PX);

void fragment() {
	vec2 inside = fract(UV) * INSIDE_SCALE + INSIDE_OFFSET;
	// Mip level from the unwrapped UV, so there's no seam where the texture wraps round inside its cell.
	vec4 texel = textureGrad(atlas, UV2 * GRID_TO_ATLAS + inside, dFdx(UV) * INSIDE_SCALE, dFdy(UV) * INSIDE_SCALE);
	ALBEDO = texel.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
