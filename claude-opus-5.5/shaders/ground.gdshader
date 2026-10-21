shader_type spatial;
// Noisy natural ground: lawns and sand. wet_level darkens sand below the waterline.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 color_a : source_color = vec3(0.30, 0.48, 0.18);
uniform vec3 color_b : source_color = vec3(0.42, 0.56, 0.22);
uniform float scale = 0.4;
uniform float wet_level = -100.0;
uniform vec3 wet_color : source_color = vec3(0.55, 0.45, 0.32);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm3(wpos.xz * scale);
	float g = hash12(floor(wpos.xz * 25.0));
	vec3 col = mix(color_a, color_b, n) * (0.93 + 0.12 * g);
	float wet = smoothstep(wet_level + 0.25, wet_level - 0.05, wpos.y);
	col = mix(col, wet_color, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.5, wet);
	SPECULAR = 0.25;
}
