shader_type spatial;
// Four-lane carriageway surface. Everything is computed from world position so
// the mesh can stay under the player while the road scrolls by. All noise is
// periodic over the scroll period so the surface never jumps when it wraps.

uniform float scroll = 0.0;        // player distance modulo PERIOD
uniform float center_x = 0.0;      // carriageway centre line (world x)
uniform float road_half = 7.2;
uniform vec3 asphalt : source_color = vec3(0.17, 0.18, 0.2);
uniform vec3 shoulder : source_color = vec3(0.3, 0.3, 0.31);
uniform vec3 paint : source_color = vec3(0.91, 0.89, 0.83);
uniform float stud_glow = 0.5;  // road studs shine brighter at night
uniform float detail = 1.0;        // 1: asphalt grain bends the light (High graphics)

const float PERIOD = 3600.0;

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// value noise, periodic in y with `per` cells
float pnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float y0 = mod(i.y, per);
	float y1 = mod(i.y + 1.0, per);
	float a = hash(vec2(i.x, y0));
	float b = hash(vec2(i.x + 1.0, y0));
	float c = hash(vec2(i.x, y1));
	float d = hash(vec2(i.x + 1.0, y1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float line_mask(float d, float half_w, float aa) {
	return 1.0 - smoothstep(half_w - aa, half_w + aa, d);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = wp.x - center_x;
	float z = mod(scroll - wp.z, PERIOD);
	float ax = abs(x);
	float aa = max(fwidth(x), 0.01);
	float on_road = step(ax, road_half);

	float n_big = pnoise(vec2(x * 0.15, z * 0.04), PERIOD * 0.04);
	float n_fine = pnoise(vec2(x * 3.0, z * 3.0), PERIOD * 3.0);
	float n_mid = pnoise(vec2(x * 0.6, z * 0.25), PERIOD * 0.25);

	vec3 col = asphalt * (0.88 + 0.14 * n_big + 0.07 * n_fine);
	// repaired patches
	col *= 1.0 - 0.07 * smoothstep(0.62, 0.66, n_mid) * on_road;
	// tyre wear: darker, smoother bands where the wheels run
	float lane_x = mod(x + road_half, 3.6) - 1.8;
	float track = exp(-pow((abs(lane_x) - 0.78) / 0.3, 2.0)) * on_road;
	col *= 1.0 - 0.14 * track;
	// oil drip line down the middle of each lane
	col *= 1.0 - 0.07 * exp(-pow(lane_x / 0.22, 2.0)) * on_road;
	// crack sealant
	float crack = pnoise(vec2(x * 0.9, z * 0.11), PERIOD * 0.11);
	float tar = 1.0 - smoothstep(0.0, 0.008, abs(crack - 0.5));
	col = mix(col, vec3(0.08), tar * 0.3 * on_road);

	if (ax > road_half) {
		col = shoulder * (0.9 + 0.1 * n_fine + 0.06 * n_big);
		float joint = 1.0 - smoothstep(0.0, 0.035, abs(mod(z, 6.0) - 3.0));
		col *= 1.0 - 0.3 * joint;
		if (ax > road_half + 0.3 && ax < road_half + 0.75) {
			col *= 0.8 + 0.22 * step(0.5, fract(z / 0.6));  // rumble strip
		}
	}

	// markings, slightly worn
	float edge = line_mask(abs(ax - (road_half - 0.07)), 0.09, aa);
	float dash = step(mod(z, 12.0), 3.2);
	float lanes = max(line_mask(abs(x + 3.6), 0.08, aa), max(line_mask(abs(x), 0.08, aa), line_mask(abs(x - 3.6), 0.08, aa))) * dash;
	float wear = 0.8 + 0.2 * pnoise(vec2(x * 12.0, z * 1.5), PERIOD * 1.5);
	col = mix(col, paint * (0.85 + 0.15 * n_fine), max(edge, lanes) * wear);

	// raised reflective markers between the dashes
	float mz = abs(mod(z, 12.0) - 7.6);
	float marker = 0.0;
	for (int i = -1; i <= 1; i++) {
		float dx = abs(x - float(i) * 3.6);
		marker = max(marker, (1.0 - smoothstep(0.05, 0.08, dx)) * (1.0 - smoothstep(0.06, 0.09, mz)));
	}
	col = mix(col, vec3(1.0, 0.86, 0.45), marker);

	// asphalt grain: tilt the surface normal with fine noise so low sun
	// glints off the aggregate. Fades out with distance so it never shimmers.
	if (detail > 0.5) {
		float fade = 1.0 - smoothstep(6.0, 30.0, length(VERTEX));
		if (fade > 0.0) {
			float e = 0.015;
			float g0 = pnoise(vec2(x * 16.0, z * 16.0), PERIOD * 16.0);
			float gx = pnoise(vec2((x + e) * 16.0, z * 16.0), PERIOD * 16.0);
			float gz = pnoise(vec2(x * 16.0, (z + e) * 16.0), PERIOD * 16.0);
			vec3 bump = vec3(g0 - gx, 0.0, gz - g0) / e * 0.0035 * fade * (1.0 - 0.7 * max(edge, lanes));
			NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);
		}
	}
	ALBEDO = col;
	EMISSION = vec3(1.0, 0.75, 0.3) * marker * stud_glow;
	ROUGHNESS = 0.9 - 0.25 * track - 0.3 * max(edge, lanes);
	SPECULAR = 0.35;
}
