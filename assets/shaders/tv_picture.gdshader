shader_type spatial;
// The hideout TV's picture (0.28.5, scripts/hideout_life.gd): blocky shapes of colour that change every second or
// so, a dark bar rolling down and scanlines, over the screen's blue glow. Looks only.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float scene = floor(TIME * 0.7);
	vec2 cell = floor(UV * vec2(6.0, 5.0));
	float sky = step(0.55 + 0.2 * hash(vec2(scene, 3.0)), UV.y);                  // a horizon in each picture
	vec3 top = vec3(0.35 + 0.3 * hash(vec2(scene, 1.0)), 0.5 + 0.3 * hash(vec2(scene, 2.0)), 0.85);
	vec3 low = vec3(0.25 + 0.35 * hash(vec2(scene, 4.0)), 0.3 + 0.35 * hash(vec2(scene, 5.0)), 0.15 + 0.25 * hash(vec2(scene, 6.0)));
	vec3 picture = mix(low, top, sky) * (0.8 + 0.3 * hash(cell + scene));
	float bar = 0.8 + 0.2 * smoothstep(0.0, 0.12, abs(fract(UV.y * 0.7 + TIME * 0.2) - 0.5));
	float lines = 0.88 + 0.12 * step(0.5, fract(UV.y * 70.0));
	ALBEDO = picture * bar * lines * (0.95 + 0.05 * hash(vec2(floor(TIME * 24.0), 0.0)));
	ALPHA = 0.85;
}
