shader_type spatial;
// Four-lane highway surface. Lines are computed from world position so the
// mesh can stay fixed under the player while the road scrolls by.

uniform float scroll = 0.0;   // player distance modulo 360 m
uniform float road_half = 7.2;
uniform vec3 asphalt : source_color = vec3(0.17, 0.18, 0.2);
uniform vec3 shoulder : source_color = vec3(0.28, 0.29, 0.3);
uniform vec3 paint : source_color = vec3(0.91, 0.89, 0.83);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_mask(float d, float half_w, float aa) {
	return 1.0 - smoothstep(half_w - aa, half_w + aa, d);
}

void fragment() {
	float x = wp.x;
	float z = scroll - wp.z;
	float ax = abs(x);
	float aa = max(fwidth(x), 0.01);

	vec3 col = ax > road_half ? shoulder : asphalt;
	float patch = fract(sin(floor(z / 9.0) * 12.9898) * 43758.5453);
	col *= 0.94 + 0.09 * patch;

	float edge = line_mask(abs(ax - (road_half - 0.07)), 0.09, aa);
	float dash = step(mod(z, 12.0), 3.2);
	float lanes = max(line_mask(abs(x + 3.6), 0.08, aa),
		max(line_mask(abs(x), 0.08, aa), line_mask(abs(x - 3.6), 0.08, aa))) * dash;
	col = mix(col, paint, max(edge, lanes));

	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
}
