shader_type spatial;
uniform sampler2D albedo_texture : source_color;
uniform vec4 tint : source_color = vec4(1.0);
uniform mat4 mesh_to_root;
uniform vec3 signal_color = vec3(0.1, 1.0, 0.3);
uniform float signal_height = 2.1;
varying vec3 local_position;

void vertex() {
	local_position = (mesh_to_root * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * tint.rgb;
	ROUGHNESS = 0.85;
	vec3 offset = (local_position - vec3(-2.9, signal_height, -0.46)) / vec3(0.25, 0.25, 0.15);
	float lens = 1.0 - smoothstep(0.65, 1.0, length(offset));
	EMISSION = signal_color * lens * 3.5;
}
