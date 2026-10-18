// Car parks (World art 0.17, outdoor step 3; owner: "we gotta make all the parking lots"): BoxMap's `lot_material`
// boxes. The roads' asphalt and patches, with white parking bays painted along both long sides (5 m deep, 2.6 m
// wide) from the box's own UVs (x across from its middle, y along, in metres; UV2 = width, length), worn like the
// road lines. Narrow boxes (the ways in) get no bays.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D surface : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D patched : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D wear : filter_nearest_mipmap, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform float tile = 4.0;
uniform float patch_cut = 0.74;
uniform vec3 paint : source_color = vec3(0.86, 0.85, 0.8);
uniform float line_w = 0.12;
uniform float bay = 2.6;
uniform float depth = 5.0;
uniform float worn = 0.3;

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
	// bays face the long sides: `across` runs over the short side
	bool long_y = UV2.y >= UV2.x;
	float across = floor((long_y ? UV.x : UV.y) * 32.0) / 32.0;
	float along = floor((long_y ? UV.y : UV.x) * 32.0) / 32.0;
	float half_c = (long_y ? UV2.x : UV2.y) * 0.5;
	float half_a = (long_y ? UV2.y : UV2.x) * 0.5;
	if (half_c > 6.0) {
		float edge = half_c - abs(across);           // metres in from the long side
		float a = along + half_a - 1.0;              // from 1 m in at the end
		bool line = edge > 0.4 && edge < depth && a > 0.0 && a < half_a * 2.0 - 2.0 && mod(a, bay) < line_w;
		if (line && texture(wear, world_pos.xz * 0.5).r > worn) {
			c = paint * (0.9 + 0.1 * texture(wear, world_pos.xz * 1.7).r);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
