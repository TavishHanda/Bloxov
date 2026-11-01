// Crows (0.28.0, scripts/birds.gd): one small black bird shape for every crow (a MultiMesh), its wings (|x| past the
// body) flapping. INSTANCE_CUSTOM.r: its own time offset, g: how hard it flaps (0 gliding).
shader_type spatial;
render_mode cull_disabled;

uniform vec3 colour : source_color = vec3(0.05, 0.05, 0.06);

void vertex() {
	float reach = max(0.0, abs(VERTEX.x) - 0.07);
	float a = sin(TIME * 11.0 + INSTANCE_CUSTOM.r * 6.283) * 0.9 * INSTANCE_CUSTOM.g - 0.15 * (1.0 - INSTANCE_CUSTOM.g);
	VERTEX.y += reach * sin(a) * 1.4;
	VERTEX.x -= sign(VERTEX.x) * reach * (1.0 - cos(a)) * 0.5;
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 0.9;
}
