shader_type spatial;
// Sidewalk / promenade tiles on top faces, plain curb concrete on the sides.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 tile_color : source_color = vec3(0.72, 0.70, 0.66);
uniform vec3 joint_color : source_color = vec3(0.52, 0.50, 0.47);
uniform vec3 curb_color : source_color = vec3(0.78, 0.77, 0.74);
uniform float tile_size = 1.0;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = vnoise(wpos.xz * 0.5);
	vec3 col;
	if (wnormal.y > 0.5) {
		vec2 t = wpos.xz / tile_size;
		vec2 f = abs(fract(t) - 0.5);
		float joint = step(0.46, max(f.x, f.y));
		float tile_var = hash12(floor(t)) * 0.08;
		col = mix(tile_color * (0.92 + tile_var + 0.1 * n), joint_color, joint);
	} else {
		col = curb_color * (0.9 + 0.1 * n);
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
