shader_type spatial;
// Roadside grass with mown stripes so speed reads even off the road.

uniform float scroll = 0.0;
uniform vec3 grass_a : source_color = vec3(0.36, 0.46, 0.2);
uniform vec3 grass_b : source_color = vec3(0.32, 0.42, 0.18);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float z = scroll - wp.z;
	float band = mod(floor(z / 16.0), 2.0);
	float n = fract(sin(dot(floor(vec2(wp.x, z) / 3.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = mix(grass_a, grass_b, band) * (0.93 + 0.1 * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
