// Bushes (World art 0.17, outdoor; scripts/bushes.gd): many small cut-out leaf cards per bush (no blending, cheap on
// phones), lit as if they were the outside of one round bush (the mesh's normals point out from its middle) and
// darker deep inside (vertex colour). They sway in the wind from the tips: COLOR.a is how far up the bush a corner is.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaves : source_color, filter_nearest_mipmap, repeat_disable;
uniform float sway = 0.05;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.4;
	float k = COLOR.a * COLOR.a;
	VERTEX.x += sin(t + world.x * 0.35 + world.z * 0.2) * sway * k;
	VERTEX.z += cos(t * 0.8 + world.z * 0.35) * sway * 0.7 * k;
}

void fragment() {
	vec4 c = texture(leaves, UV);
	ALBEDO = c.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
