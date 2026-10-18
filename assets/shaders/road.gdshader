// Roads (World art 0.17, outdoor step 3): BoxMap's road ribbons (scripts/box_map.gd `road_material`). Asphalt (or
// concrete slabs) tiled by world position, darker patched squares here and there, and lane lines painted from the
// ribbon's UVs (x across from the middle line, y along the road, in metres; UV2.x = width), worn off pixel by pixel,
// left out inside junctions (COLOR.r); edge lines
// also at car parks' ways in (COLOR.g). Snapped to the art's 32 px per metre so the lines stay pixel-crisp.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D surface : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D patched : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D wear : filter_nearest_mipmap, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float tile = 4.0;                 // metres per surface tile
uniform float patch_cut = 0.74;           // macro noise above this: a patch
uniform vec3 centre_colour : source_color = vec3(0.85, 0.83, 0.76);
uniform vec3 edge_colour : source_color = vec3(0.85, 0.83, 0.76);
uniform int centre_mode = 1;              // 0 none, 1 dashed, 2 double solid
uniform bool edges = true;
uniform float line_w = 0.12;
uniform float dash = 3.0;
uniform float gap = 6.0;
uniform float edge_in = 0.35;             // the edge lines this far in from the side
uniform float worn = 0.3;                 // how much of the paint is gone
uniform float slab = 0.0;                 // concrete slabs this long (0: asphalt, no joints)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile;
	vec3 c = texture(surface, uv).rgb;
	if (texture(macro, world_pos.xz / 37.0).r > patch_cut) {
		c = texture(patched, uv).rgb;
	}
	if (COLOR.r < 0.5) {
		float u = floor(UV.x * 32.0) / 32.0;
		float v = floor(UV.y * 32.0) / 32.0;
		float w = UV2.x;
		float half_w = line_w * 0.5;
		float paint = 0.0;
		vec3 lc = centre_colour;
		if (centre_mode == 1 && abs(u) < half_w && mod(v + 500.0, dash + gap) < dash) paint = 1.0;
		if (centre_mode == 2 && abs(abs(u) - 0.13) < half_w) paint = 1.0;
		if (edges && w > 5.0 && COLOR.g < 0.3 && abs(abs(u) - (w * 0.5 - edge_in)) < half_w) {
			paint = 1.0;
			lc = edge_colour;
		}
		if (paint > 0.0 && texture(wear, world_pos.xz * 0.5).r > worn) {
			c = lc * (0.9 + 0.1 * texture(wear, world_pos.xz * 1.7).r);
		}
		if (slab > 0.0) {   // slab joints: across every `slab` metres and down the middle
			float jv = mod(v + 500.0, slab);
			if (jv < 0.04 || abs(u) < 0.03) c *= 0.6;
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
