shader_type spatial;
// Asphalt with optional lane markings. Markings are drawn on PlaneMesh strips:
// UV.x goes across the road, UV.y along it.
#include "res://shaders/noise.gdshaderinc"

uniform bool markings = false;
uniform vec3 asphalt_color : source_color = vec3(0.17, 0.17, 0.18);
instance uniform float seg_len = 50.0;
instance uniform float seg_w = 12.0;
// 1.0 = draw a crosswalk at that end of the strip.
instance uniform float cw_start = 1.0;
instance uniform float cw_end = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm3(wpos.xz * 0.35);
	float grain = hash12(floor(wpos.xz * 40.0));
	vec3 col = asphalt_color * (0.82 + 0.3 * n + 0.08 * grain);
	float paint = 0.0;
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	if (markings) {
		float u = (UV.x - 0.5) * seg_w;
		float v = UV.y * seg_len;
		float au = abs(u);
		bool in_cw = (cw_start > 0.5 && v < 4.0) || (cw_end > 0.5 && v > seg_len - 4.0);
		if (in_cw) {
			float edge_in = step(0.6, v) * step(v, seg_len - 0.6);
			bool zebra_zone = (v < 4.0 && v > 0.6) || (v > seg_len - 4.0 && v < seg_len - 0.6);
			if (zebra_zone && au < seg_w * 0.5 - 0.5) {
				paint = step(fract(u / 1.2), 0.55) * edge_in;
			}
		} else {
			// double yellow centre line
			float yl = step(abs(au - 0.18), 0.07);
			if (yl > 0.0) {
				paint = 1.0;
				paint_col = vec3(0.95, 0.75, 0.15);
			}
			// solid white edge lines
			paint = max(paint, step(abs(au - (seg_w * 0.5 - 0.45)), 0.08));
			// stop lines before crosswalks (right-hand traffic)
			float stop_s = step(abs(v - 4.6), 0.25) * step(u, -0.3) * step(0.5, cw_start);
			float stop_e = step(abs(v - (seg_len - 4.6)), 0.25) * step(0.3, u) * step(0.5, cw_end);
			if (stop_s + stop_e > 0.0 && au < seg_w * 0.5 - 0.45) {
				paint = 1.0;
				paint_col = vec3(0.92, 0.92, 0.88);
			}
		}
		// worn paint
		paint *= 0.75 + 0.25 * vnoise(wpos.xz * 3.0);
	}
	ALBEDO = mix(col, paint_col, paint);
	ROUGHNESS = mix(0.92, 0.7, paint);
	SPECULAR = 0.3;
}
