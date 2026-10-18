// The waterfall by the creek (World art 0.17, outdoor step 6): the falling sheet of water in front of the secret
// room's doorway, and (splash = 1) the churned water where it lands. Streaks and foam from the creek's ripple texture
// (art_source/scripts/make_water.py) pulled fast downward, in 32 px a metre like the ground. No collision anywhere:
// you walk through it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D ripples : filter_nearest_mipmap, repeat_enable;
uniform vec2 size = vec2(2.6, 6.0);          // the quad's size in metres (UV 0-1 across it)
uniform float splash = 0.0;                  // 0: the falling sheet; 1: the splash at its foot
uniform vec3 water : source_color = vec3(0.30, 0.50, 0.55);
uniform vec3 foam : source_color = vec3(0.88, 0.92, 0.93);
uniform vec2 land = vec2(0.5, 0.3);         // where the sheet lands on the splash (UV)
uniform float speed = 2.4;                   // metres a second it falls (the splash churns at a third of it)

void fragment() {
	vec2 m = floor(UV * size * 32.0) / 32.0 + 1.0 / 64.0;   // (metres, snapped to the pixel grid)
	if (splash < 0.5) {
		// (stretched tall: streaks running down)
		vec4 a = texture(ripples, vec2(m.x * 0.9, m.y * 0.04 - TIME * speed * 0.04));
		vec4 b = texture(ripples, vec2(m.x * 1.4 + 0.3, m.y * 0.07 - TIME * speed * 0.07));
		float streak = a.b * 0.6 + b.b * 0.4;
		float white = step(0.62 - 0.35 * smoothstep(0.65, 1.0, UV.y), streak);   // (more foam low down)
		ALBEDO = mix(water, foam, max(white, 0.25));
		// (a ragged top edge where it pours off the lip, thin at the sides)
		float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(1.0, 0.88, UV.x);
		ALPHA = clamp((0.72 + 0.28 * white) * mix(0.5, 1.0, edge) * step(0.04 * a.a, UV.y), 0.0, 1.0);
		ROUGHNESS = 0.35;
	} else {
		vec2 d = (UV - land) * size;   // (from where the sheet lands, by the cliff)
		float r = length(d);
		vec4 a = texture(ripples, m * 0.35 + vec2(0.0, TIME * speed * 0.1));
		vec4 b = texture(ripples, m * 0.5 - vec2(TIME * speed * 0.08, 0.0));
		float churn = a.b * 0.5 + b.b * 0.5;
		float near = 1.0 - smoothstep(0.3, 1.1, r);
		float white = step(1.0 - near * 0.9, churn);
		ALBEDO = mix(water, foam, white);
		ALPHA = max(white * 0.95, near * 0.45);
		ROUGHNESS = 0.6;
	}
}
