// The bunks' lights (0.21.16, owner: switched off, they should stay off as you walk round): the walls, floor and kit in
// the bunks tunnel are drawn dark wherever you look at them from. Set by HideoutToys every frame.
// lights_off: 0 = on, 1 = off (fades). area: the bunks (x0, z0, x1, z1), in level space.
uniform float lights_off = 0.0;
uniform vec4 area = vec4(0.0);
const float OFF = 0.12 / 0.9;   // what's left of the light (the ambient light the bunks were dimmed to before, 0.21.7)

varying vec3 level_pos;

void vertex() {
	level_pos = VERTEX;   // (the level's model sits at the level's origin)
}

// How much of the baked light is left here.
float bunks_light() {
	float inside = step(area.x - 0.5, level_pos.x) * step(level_pos.x, area.z + 0.5)
		* clamp((level_pos.z - area.y + 2.0) / 3.0, 0.0, 1.0);
	return mix(1.0, OFF, lights_off * inside);
}

// The lamps left on (the TV, the fairy lights' glow) light the dark bunks at full strength: matte, like the default.
void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI / bunks_light();
}
