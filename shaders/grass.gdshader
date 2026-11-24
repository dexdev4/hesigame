shader_type spatial;
render_mode cull_disabled;
// The ground beside the highway, and under the hills and swells that roll away from it (they use this shader too, so
// there is no seam): a gravel edge along the pavement, kept grass (or sand, or snow) near the road, and, farther out, the
// country's own ground: patchwork fields (style 0), desert soil and scrub (1), forest floor (2), dunes and a beach (3),
// snow (4). Everything is worked out from the world position and is periodic over the scroll period, so the ground never
// jumps when it wraps. Fine detail fades with the size of a pixel on the ground, so it never shimmers.

uniform float scroll = 0.0;
uniform vec3 grass_a : source_color = vec3(0.32, 0.45, 0.17);
uniform vec3 grass_b : source_color = vec3(0.28, 0.4, 0.15);
uniform vec3 field : source_color = vec3(0.56, 0.5, 0.26);
uniform vec3 dirt : source_color = vec3(0.42, 0.37, 0.28);
uniform vec3 accent : source_color = vec3(0.42, 0.32, 0.2);   // the country's second colour: ploughed soil, scrub, moss, dune grass, bare ground
uniform int style = 0;
uniform float edge_r = 9.6;     // outer edge of our shoulder (world x)
uniform float edge_l = -31.6;   // outer edge of the opposite carriageway
uniform float sea_x = -1.0e5;   // style 3: the shore, on the left (world x); the sea itself is its own mesh

const float PERIOD = 3600.0;

varying vec3 wp;
varying vec4 vcol;  // (the hills' woods are a darker tint, in the vertices)

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
	vcol = COLOR;
}

void fragment() {
	float z = mod(scroll - wp.z, PERIOD);
	float x = wp.x;
	float px = length(vec2(fwidth(x), fwidth(z)));            // metres a pixel covers on the ground
	float fine = 1.0 - smoothstep(0.35, 1.6, px);             // 1 up close, 0 when the detail is smaller than a pixel
	float mid_x = 0.5 * (edge_r + edge_l);
	float d = max(max(x - edge_r, edge_l - x), 0.0);          // metres beyond the outer edge of the pavement
	float in_med = 1.0 - smoothstep(5.0, 7.0, abs(x - mid_x));  // the median: always kept grass

	float n_big = pnoise(vec2(x * 0.012, z * 0.012), PERIOD * 0.012);
	float n_mid = pnoise(vec2(x * 0.055, z * 0.055) + 11.0, PERIOD * 0.055);
	float n_mid2 = pnoise(vec2(x * 0.11, z * 0.07) + 31.0, PERIOD * 0.07);
	float n_fine = pnoise(vec2(x * 1.3, z * 1.3), PERIOD * 1.3);

	// near the road: kept ground, in soft long drifts along it (never in bands across it)
	float drift = smoothstep(0.3, 0.7, pnoise(vec2(x * 0.16, z * 0.028), PERIOD * 0.028));
	vec3 kept = mix(grass_a, grass_b, drift);
	vec3 far_c = kept;
	float vary = 0.9 + 0.2 * n_big;

	if (style == 0) {
		// a patchwork of fields: a parcel is about 35 m by 95 m, in pasture, crop, stubble or ploughed soil, with rows
		vec2 uv = vec2((x + 40.0) / 34.0, z / 95.0);
		uv.y += 0.43 * floor(uv.x);
		vec2 id = floor(uv);
		float h1 = hash(id + 3.1);
		float h2 = hash(id + 17.7);
		vec3 pc = grass_b;
		if (h1 > 0.78) {
			pc = accent;
		} else if (h1 > 0.5) {
			pc = field;
		} else if (h1 > 0.28) {
			pc = mix(grass_a, field, 0.5);
		}
		pc *= 0.9 + 0.2 * h2;
		float rows = 0.5 + 0.5 * sin(x * (7.0 + 4.0 * h2) + 6.0 * h2);
		pc *= 1.0 - 0.1 * rows * fine * step(0.28, h1);
		vec2 fu = fract(uv);
		float edge = min(min(fu.x, 1.0 - fu.x) * 34.0, min(fu.y, 1.0 - fu.y) * 95.0);
		pc *= 0.82 + 0.18 * smoothstep(0.0, 0.9, edge);   // the hedge line between parcels
		far_c = mix(pc, kept, 0.15 * n_mid2) * (0.94 + 0.12 * n_mid);
	} else if (style == 1) {
		// desert: sand, reddish soil in broad patches, scrub, scattered stones and wind ripples
		vec3 sand = kept;
		vec3 soil = mix(sand, dirt, smoothstep(0.45, 0.7, n_mid) * 0.8);
		vec3 scrub = mix(soil, accent, smoothstep(0.6, 0.82, n_mid2) * 0.6);
		float ripple = 0.5 + 0.5 * sin(x * 0.5 + n_big * 14.0 + z * 0.02);
		far_c = scrub * (0.93 + 0.1 * ripple);
		float pebble = step(0.93, hash(floor(vec2(x, z) * 2.5))) * fine;
		far_c = mix(far_c, far_c * 0.62, pebble * 0.7);
	} else if (style == 2) {
		// forest floor: needles, moss, darker where the canopy closes in
		vec3 needles = mix(grass_a, dirt, smoothstep(0.5, 0.72, n_mid) * 0.7);
		vec3 moss = mix(needles, accent, smoothstep(0.55, 0.78, n_mid2) * 0.75);
		far_c = moss * (1.0 - 0.28 * smoothstep(8.0, 60.0, d)) * (0.92 + 0.14 * n_fine * fine + 0.1 * n_big);
	} else if (style == 3) {
		// the coast: sand with tufts of dune grass inland, wet sand and a beach towards the sea
		vec3 sand = field;
		vec3 dunes = mix(sand, accent, smoothstep(0.42, 0.7, n_mid) * 0.85);
		vec3 inland = mix(dunes, grass_a, smoothstep(0.55, 0.8, n_mid2) * 0.5);
		float shore = x - sea_x;                              // metres from the water on the left side, positive inland
		float beach = 1.0 - smoothstep(0.0, 40.0, shore);
		float wet = 1.0 - smoothstep(0.0, 7.0, shore);
		far_c = mix(inland, sand * 1.05, beach) * mix(1.0, 0.78, wet) * (0.95 + 0.1 * n_big);
	} else {
		// snow: drifts, a little blue in the hollows, and bare ground showing through in places
		vec3 snow = mix(grass_a, grass_b, smoothstep(0.35, 0.7, n_mid));
		float rip = 0.5 + 0.5 * sin(x * 0.8 + n_mid * 9.0 + z * 0.03);
		snow *= 0.96 + 0.05 * rip;
		float bare = smoothstep(0.7, 0.86, n_mid2 * 0.6 + n_big * 0.5) * smoothstep(8.0, 22.0, d);
		far_c = mix(snow, accent, bare * 0.7);
	}

	// kept ground fades into the country over 8 to 30 m, except in the median
	float far_k = smoothstep(8.0, 30.0, d) * (1.0 - in_med);
	vec3 col = mix(kept * (0.95 + 0.1 * n_fine * fine), far_c, far_k) * vary;
	if (style == 4) {
		col = mix(kept, far_c, far_k) * (0.97 + 0.04 * n_big);
	}
	// blades and clods in the grain, up close only
	float grain = hash(floor(vec2(x, z) * 5.0));
	col *= 1.0 + (grain - 0.5) * 0.12 * fine;
	// wildflowers out in the grass (farmland only)
	if (style == 0) {
		float fl = hash(floor(vec2(x * 2.5, z * 2.5)));
		float flower = step(0.994, fl) * smoothstep(3.0, 6.0, d) * fine;
		col = mix(col, mix(vec3(0.95, 0.9, 0.4), vec3(0.92, 0.94, 0.98), step(0.997, fl)), flower * 0.8);
	}
	// the gravel shoulder along the pavement
	float gravel = 1.0 - smoothstep(0.0, 1.5 + 0.8 * n_fine, d);
	vec3 stones = dirt * (0.8 + 0.4 * hash(floor(vec2(x, z) * 9.0)));
	col = mix(col, stones, gravel * (1.0 - in_med) * mix(0.75, 0.55, 1.0 - fine));

	ALBEDO = col * vcol.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
