// The hideout's signs and decals (the imported material: texture times the baked light), with the bunks' lights switch.
shader_type spatial;

#include "res://assets/shaders/hideout_dark.gdshaderinc"

uniform sampler2D decals : source_color, filter_nearest_mipmap, repeat_enable;

void fragment() {
	ALBEDO = texture(decals, UV).rgb * COLOR.rgb * bunks_light();
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
