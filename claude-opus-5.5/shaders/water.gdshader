shader_type spatial;
// Opaque stylised ocean: procedural ripples, fresnel tint and a foam band at the shore.
#include "res://shaders/noise.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.02, 0.22, 0.38);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.62, 0.66);
uniform float shore_x = 137.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ripple(vec2 p, float t) {
	float h0 = vnoise(p * 0.25 + vec2(t * 0.15, t * 0.05));
	float hx = vnoise(p * 0.25 + vec2(0.2, 0.0) + vec2(t * 0.15, t * 0.05));
	float hz = vnoise(p * 0.25 + vec2(0.0, 0.2) + vec2(t * 0.15, t * 0.05));
	float g0 = vnoise(p * 0.9 - vec2(t * 0.3, t * 0.2));
	float gx = vnoise(p * 0.9 + vec2(0.2, 0.0) - vec2(t * 0.3, t * 0.2));
	float gz = vnoise(p * 0.9 + vec2(0.0, 0.2) - vec2(t * 0.3, t * 0.2));
	return vec2(hx - h0, hz - h0) * 1.5 + vec2(gx - g0, gz - g0) * 0.6;
}

void fragment() {
	float dist_shore = wpos.x - shore_x;
	float dist_cam = length(wpos - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - dist_cam / 400.0, 0.15, 1.0);
	vec2 r = ripple(wpos.xz, TIME) * fade;
	vec3 wn = normalize(vec3(-r.x, 1.0, -r.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float depth_t = smoothstep(0.0, 40.0, dist_shore);
	vec3 col = mix(shallow_color, deep_color, depth_t);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, vec3(0.55, 0.7, 0.85), fres * 0.45);
	// foam band that breathes in and out at the shoreline
	float wave = sin(TIME * 0.9 + wpos.z * 0.05) * 0.8;
	float foam_n = vnoise(wpos.xz * vec2(1.5, 0.6) + vec2(TIME * 0.4, 0.0));
	float foam = smoothstep(3.0 + wave, 0.5 + wave, dist_shore) * step(0.35, foam_n + 0.3);
	foam += smoothstep(0.6, 0.0, dist_shore - wave) ;
	foam = clamp(foam, 0.0, 1.0);
	ALBEDO = mix(col, vec3(0.95, 0.97, 0.97), foam);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.6;
}
