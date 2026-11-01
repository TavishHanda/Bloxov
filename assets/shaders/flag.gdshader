// Flags (0.26.1, owner: "that flag should have like kinda a waving animation instead of being stiff"; scripts/flags.gd):
// a sheet held at the pole (local x 0) flying out along +x, rippling in the wind: waves run from the pole to the fly
// end and grow on the way (the pole side barely moves), with slow gusts. Pixel picture with cut-out holes (no
// blending, cheap on phones). Looks only.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D picture : source_color, filter_nearest, repeat_disable;
uniform float width = 1.8;

void vertex() {
	vec3 home = MODEL_MATRIX[3].xyz;
	float t = TIME + home.x * 0.37 + home.z * 0.23;   // (each flag its own time)
	float s = clamp(VERTEX.x / width, 0.0, 1.0);
	float gust = 0.75 + 0.25 * sin(t * 0.31) * sin(t * 0.17 + 1.3);
	float a = 0.22 * s * gust;
	float k = 4.2;                                    // (about 1.5 m between crests)
	float ph = VERTEX.x * k - t * 5.5 + VERTEX.y * 0.9;
	float ph2 = VERTEX.x * k * 2.1 - t * 8.3 + 0.7;
	VERTEX.z += a * sin(ph) + a * 0.3 * sin(ph2);
	VERTEX.x -= 0.05 * s * (1.0 - cos(ph)) * gust;    // (the cloth bunches a little as it ripples)
	VERTEX.y -= 0.05 * s * s * (1.2 - gust);          // (the fly end sags when the wind drops)
	float dz = a * k * cos(ph) + a * 0.3 * k * 2.1 * cos(ph2) + 0.22 * gust * sin(ph) / width;
	NORMAL = normalize(vec3(-dz, 0.0, 1.0));
}

void fragment() {
	vec4 c = texture(picture, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.25);
}
