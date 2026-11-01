// Curtains and washing (0.22.0, World reacts; scripts/cloth.gd): a sheet hung by its top edge, swaying a little and
// pushed aside by whoever walks through it, the bottom most (COLOR.a: 0 at the top edge, 1 at the bottom).
// 0.28.8 (owner: "it should move out of the way when u walk into it", "they are still one flat color"): it parts to
// both sides round you instead of only bulging, and has a woven fabric with folds, a hem and grime at the bottom
// (UV: metres across and down the sheet). Lit like the building kit (matte, times the baked lamp light in COLOR.rgb).
// Looks only.
shader_type spatial;
render_mode cull_disabled;

#include "res://assets/shaders/push.gdshaderinc"

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = COLOR.a;
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	VERTEX.xz += vec2(sin(TIME * 0.9 + world.x * 0.7 + world.z * 0.4), cos(TIME * 0.7 + world.z * 0.6)) * 0.02 * k;
	VERTEX += push_offset(world, 0.9, TIME) * k * 0.8;
	// Parting: each side slides away from whoever is in it, most where they are and at the bottom.
	for (int i = 0; i < 4; i++) {
		vec4 p = pushers[i];
		if (p.w <= 0.0 || world.y < p.y - 0.4 || world.y > p.y + 2.1) {
			continue;
		}
		vec3 d = world - p.xyz;
		float across = dot(d.xz, side.xz);
		float face = abs(dot(d.xz, NORMAL.xz));
		float near = clamp(1.0 - face / 0.8, 0.0, 1.0) * clamp(1.0 - abs(across) / 1.1, 0.0, 1.0);
		float way = across >= 0.0 ? 1.0 : -1.0;
		VERTEX += side * way * near * (0.25 + 0.75 * k) * 0.55 * min(p.w, 1.0);
	}
}

void fragment() {
	vec2 px = floor(UV * 32.0);
	float weave = 0.9 + 0.1 * hash(px) + 0.05 * step(0.5, fract((px.x + px.y) * 0.5));
	float folds = 0.8 + 0.2 * sin(UV.x * 25.0 + sin(UV.y * 3.0) * 0.6);
	float hem = COLOR.a > 0.95 ? 0.75 : 1.0;
	float top = (COLOR.a < 0.04 && fract(UV.x / 0.15) < 0.25) ? 0.5 : 1.0;    // the rings on the rail
	float grime = 1.0 - 0.22 * smoothstep(0.65, 1.0, COLOR.a) * (0.6 + 0.4 * hash(floor(UV * 8.0)));
	ALBEDO = COLOR.rgb * weave * folds * hem * top * grime;
	ROUGHNESS = 1.0;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
