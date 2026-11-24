shader_type spatial;
render_mode blend_mix, specular_schlick_ggx;
// The sea off the coast road: turquoise shallows turning deep blue away from the shore, slow swells that tilt the surface
// (so the sun glints on it and it mirrors the sky), crests further out and foam where it meets the sand. Worked out from
// the world position; the plane stays put while the road scrolls past.

uniform vec3 shallow : source_color = vec3(0.17, 0.55, 0.6);
uniform vec3 deep : source_color = vec3(0.03, 0.2, 0.38);
uniform float shore_x = -130.0;   // where the water starts, on the left of the road (world x)
uniform float time_s = 0.0;

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float shore = shore_x - wp.x;                      // metres out from the shore (negative on land)
	float k = smoothstep(0.0, 240.0, shore);
	vec3 c = mix(shallow, deep, sqrt(k));
	vec2 q = wp.xz;
	float t = time_s;
	float a = sin(q.y * 0.05 + t * 0.9 + sin(q.x * 0.02) * 2.0);
	float b = sin(q.x * 0.06 + q.y * 0.035 - t * 0.7);
	vec3 n = normalize(vec3(a * 0.05 + b * 0.03, 1.0, b * 0.05 - a * 0.03));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float edge = shore + 1.6 * sin(q.y * 0.35 + t * 1.2) + 0.8 * sin(q.y * 0.9 - t * 1.7);
	float foam = 1.0 - smoothstep(0.0, 2.4, edge);
	float crest = smoothstep(0.8, 1.0, vnoise(q * 0.07 + vec2(t * 0.5, -t * 0.35))) * smoothstep(10.0, 70.0, shore);
	ALBEDO = mix(c, vec3(0.92, 0.96, 0.97), clamp(foam + crest * 0.3, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.55, clamp(foam + crest * 0.3, 0.0, 1.0));
	SPECULAR = 0.7;
	METALLIC = 0.0;
	ALPHA = smoothstep(-0.6, 1.6, shore);              // the edge melts into the sand: no hard line
}
