// Curtains and washing (0.22.0, World reacts; scripts/cloth.gd): a sheet hung by its top edge, swaying a little and
// pushed aside by whoever walks through it, the bottom most (COLOR.a: 0 at the top edge, 1 at the bottom).
// Lit like the building kit (matte, times the baked lamp light in COLOR.rgb). Looks only.
shader_type spatial;
render_mode cull_disabled;

#include "res://assets/shaders/push.gdshaderinc"

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = COLOR.a;
	VERTEX.xz += vec2(sin(TIME * 0.9 + world.x * 0.7 + world.z * 0.4), cos(TIME * 0.7 + world.z * 0.6)) * 0.02 * k;
	VERTEX += push_offset(world, 0.9, TIME) * k * 1.3;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
