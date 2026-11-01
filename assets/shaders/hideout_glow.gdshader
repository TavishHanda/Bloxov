shader_type spatial;
// The hideout stove's fire through its vents (0.28.5, scripts/hideout_life.gd): a quick, uneven flicker. Looks only.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec3 colour = vec3(1.0, 0.42, 0.1);
uniform float strength = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float fire = 0.7 + 0.18 * sin(TIME * 13.0) * sin(TIME * 5.3 + 1.0) + 0.12 * hash(floor(TIME * 14.0));
	ALBEDO = colour * strength * fire;
}
