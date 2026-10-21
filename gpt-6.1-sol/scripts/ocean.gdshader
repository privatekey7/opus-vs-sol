shader_type spatial;
render_mode cull_disabled;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.26 + TIME * 1.3) * 0.035 + sin(world_pos.z * 0.31 + TIME) * 0.02;
}

void fragment() {
	float waves = sin(world_pos.x * 1.8 + world_pos.z * 0.23 - TIME * 2.0) * 0.5 + 0.5;
	float detail = sin(world_pos.z * 3.0 + TIME * 0.8) * 0.5 + 0.5;
	float shore = 1.0 - smoothstep(150.0, 200.0, world_pos.x);
	ALBEDO = mix(vec3(0.025, 0.25, 0.34), vec3(0.15, 0.59, 0.59), shore) + waves * detail * 0.045;
	ROUGHNESS = 0.3;
	METALLIC = 0.15;
}
