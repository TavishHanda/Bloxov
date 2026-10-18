// Grass tufts (World art 0.17, outdoor step 2; scripts/grass_tufts.gd): two crossed pixel-art quads per tuft, cut out
// (no blending, cheap on phones), swaying a little in the wind, and sinking into the ground towards fade_end so they
// don't pop out of sight. INSTANCE_CUSTOM.r picks the sprite: 0 plain blades, 1 blades with wildflowers.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D sprites : source_color, filter_nearest_mipmap, repeat_disable;
uniform float fade_start = 26.0;
uniform float fade_end = 36.0;
uniform float sway = 0.04;
// The ground's average shading (ground.gdshader's `untinted`), so tufts sit in it rather than glow.
uniform float shade = 0.8;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(world, CAMERA_POSITION_WORLD);
	float keep = 1.0 - smoothstep(fade_start, fade_end, d);
	float top = UV.y < 0.5 ? 1.0 : 0.0;
	VERTEX.y *= keep;
	VERTEX.xz += top * sway * vec2(sin(TIME * 1.7 + world.x * 0.6), cos(TIME * 1.3 + world.z * 0.5)) * keep;
	UV.x = UV.x * 0.5 + INSTANCE_CUSTOM.r * 0.5;
}

void fragment() {
	vec4 c = texture(sprites, UV);
	ALBEDO = c.rgb * shade;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// (lit like the ground under it, not like an upright card; both sides alike)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
