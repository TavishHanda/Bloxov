// Bushes (World art 0.17, outdoor; scripts/bushes.gd): many small cut-out leaf cards per bush (no blending, cheap on
// phones), lit as if they were the outside of one round bush (the mesh's normals point out from its middle) and
// darker deep inside (vertex colour). They sway in the wind from the tips: COLOR.a is how far up the bush a corner is.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap;

uniform sampler2D leaves : source_color, filter_nearest_mipmap, repeat_disable;
uniform float sway = 0.05;
#include "res://assets/shaders/push.gdshaderinc"

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.4;
	float k = COLOR.a * COLOR.a;
	VERTEX.x += sin(t + world.x * 0.35 + world.z * 0.2) * sway * k;
	VERTEX.z += cos(t * 0.8 + world.z * 0.35) * sway * 0.7 * k;
	// (0.22.0, World reacts: parted round whoever walks through, the top most)
	VERTEX += push_offset(world, 1.1, TIME) * (0.35 + 0.65 * COLOR.a);
}

void fragment() {
	vec4 c = texture(leaves, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	// Godot flips the normal of a card seen from behind; undo it so every card keeps the bush's outward normal
	// (from behind, the flipped normal pointed into the bush and the leaves went black: owner 2026-10-18).
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	BACKLIGHT = vec3(0.25);
}
