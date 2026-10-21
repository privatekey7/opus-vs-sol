shader_type spatial;
// Soft round billboard particle (blood, smoke, fire, sparks) drawn procedurally from UVs.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 color : source_color = vec4(1.0);
uniform float softness = 0.6;      // 0 = hard disc, 1 = very soft edge
uniform float brightness = 1.0;    // > 1 for glowing particles

void vertex() {
	// Face the camera but keep the per-particle scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	ALBEDO = color.rgb * COLOR.rgb * brightness;
	ALPHA = a * color.a * COLOR.a;
}
