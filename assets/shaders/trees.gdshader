// Trees (World art 0.17, outdoor step 7; scripts/trees.gd): bark and leaves from one cut-out sheet
// (art_source/scripts/make_trees.py; no blending, cheap on phones). Leaves are lit as the outside of their canopy
// (trees.gd gives them normals pointing out from its middle) and darker deep inside (vertex colour). The canopy sways
// in the wind from the top: COLOR.a is how much a corner moves (0 for the trunk).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform sampler2D sheet : source_color, filter_nearest_mipmap, repeat_disable;
uniform float sway = 0.08;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.1;
	float k = COLOR.a;
	VERTEX.x += sin(t + world.x * 0.21 + world.z * 0.13) * sway * k;
	VERTEX.z += cos(t * 0.8 + world.z * 0.21) * sway * 0.7 * k;
}

void fragment() {
	vec4 c = texture(sheet, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	// (Godot flips a card's normal seen from behind; keep the canopy's outward normal, as the bushes do)
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	BACKLIGHT = vec3(0.2);
}
