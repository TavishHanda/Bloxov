// The world reacts (0.22.0, scripts/reacts.gd): bodies walking through bushes and curtains push them aside.
// pushers: x, y, z of a body's feet and w how hard (0: none). Looks only.
uniform vec4 pushers[4];

// How far `world` (a point of the leaves or cloth) is pushed, before scaling by how loose that point is.
vec3 push_offset(vec3 world, float reach, float t) {
	vec3 off = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 p = pushers[i];
		if (p.w <= 0.0 || world.y < p.y - 0.4 || world.y > p.y + 2.1) {
			continue;
		}
		vec2 d = world.xz - p.xz;
		float dist = length(d);
		if (dist < reach) {
			float f = 1.0 - dist / reach;
			vec2 away = d / max(dist, 0.001);
			off.xz += away * f * f * reach * 0.55 * min(p.w, 1.0);
			// (a rustle while someone moves through: faster, the faster they go)
			off.xz += vec2(sin(t * 9.0 + world.y * 7.0), cos(t * 8.0 + world.x * 6.0)) * 0.035 * f * max(p.w - 0.5, 0.0);
		}
	}
	return off;
}
