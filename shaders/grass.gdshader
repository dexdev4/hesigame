shader_type spatial;
// Roadside ground: mown stripes near the highway fading into patchy fields,
// with dry dirt along the pavement edges. Periodic over the scroll period.

uniform float scroll = 0.0;
uniform vec3 grass_a : source_color = vec3(0.32, 0.45, 0.17);
uniform vec3 grass_b : source_color = vec3(0.28, 0.4, 0.15);
uniform vec3 field : source_color = vec3(0.56, 0.5, 0.26);
uniform vec3 dirt : source_color = vec3(0.42, 0.37, 0.28);
uniform float edge_r = 9.6;     // outer edge of our shoulder (world x)
uniform float edge_l = -31.6;   // outer edge of the opposite carriageway

const float PERIOD = 3600.0;

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float pnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float y0 = mod(i.y, per);
	float y1 = mod(i.y + 1.0, per);
	return mix(mix(hash(vec2(i.x, y0)), hash(vec2(i.x + 1.0, y0)), u.x),
		mix(hash(vec2(i.x, y1)), hash(vec2(i.x + 1.0, y1)), u.x), u.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float z = mod(scroll - wp.z, PERIOD);
	float x = wp.x;
	float band = mod(floor(z / 16.0), 2.0);
	float n1 = pnoise(vec2(x * 0.08, z * 0.08), PERIOD * 0.08);
	float n2 = pnoise(vec2(x * 0.9, z * 0.9), PERIOD * 0.9);
	vec3 mown = mix(grass_a, grass_b, band);
	// fields further out: large patches of dry grass and crops
	float far_k = smoothstep(18.0, 40.0, min(abs(x - edge_r), abs(x - edge_l)));
	vec3 fields = mix(grass_b, field, smoothstep(0.45, 0.6, n1));
	vec3 col = mix(mown, fields, far_k) * (0.9 + 0.14 * n2);
	// natural variety: broad drifts of colour, darker clumps, dry patches
	float n0 = pnoise(vec2(x * 0.018, z * 0.018), PERIOD * 0.018);
	float n3 = pnoise(vec2(x * 0.35, z * 0.35) + 17.0, PERIOD * 0.35);
	col *= 0.88 + 0.24 * n0;
	col = mix(col, col * vec3(0.78, 0.86, 0.74), smoothstep(0.62, 0.78, n3) * 0.7);
	col = mix(col, field * 1.05, smoothstep(0.7, 0.85, n0 * 0.6 + n1 * 0.4) * 0.5);
	// wildflowers: tiny bright specks out in the grass
	float fl = hash(floor(vec2(x * 3.0, z * 3.0)));
	float flower = step(0.992, fl) * smoothstep(3.0, 6.0, min(abs(x - edge_r), abs(x - edge_l)));
	col = mix(col, mix(vec3(0.95, 0.9, 0.4), vec3(0.92, 0.94, 0.98), step(0.996, fl)), flower * 0.8);
	// worn dirt strip along the pavement
	float d = min(abs(x - edge_r), abs(x - edge_l));
	col = mix(col, dirt, (1.0 - smoothstep(0.0, 1.4 + n2, d)) * 0.7);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
