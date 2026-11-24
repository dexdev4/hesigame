shader_type canvas_item;
// World map terrain: a continent from fractal noise, lifted along the
// highway corridor so every city stands on land, coloured by height (sea,
// shallows, beach, lowland, forest, hills, rock, snow) with each region
// tinted by the country its nearest highway runs through. Hill shading from
// the height gradient, rivers along noise valleys, and a paper finish.

uniform sampler2D height_tex : filter_linear, repeat_disable;   // large-scale shape
uniform sampler2D detail_tex : filter_linear, repeat_enable;    // forests, rivers, grain
uniform vec2 cities[15];
uniform vec3 seg_col[14];   // lowland colour of each highway's country
uniform float seg_snow[14]; // 1 where the country is frosted
uniform float texel = 0.004;

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float route_dist(vec2 uv) {
	float d = 10.0;
	for (int i = 0; i < 14; i++) {
		d = min(d, seg_dist(uv, cities[i], cities[i + 1]));
	}
	return d;
}

float height_at(vec2 uv, float route_d) {
	float n = texture(height_tex, uv).r;
	vec2 c = (uv - vec2(0.5)) * vec2(1.0, 0.92);
	float continent = 1.0 - smoothstep(0.38, 0.58, length(c));
	float corridor = 1.0 - smoothstep(0.02, 0.1, route_d);
	// lowlands along the roads, rolling country and a few ranges between them
	float h = n * 0.62 + continent * 0.36 - 0.4;
	h = mix(h, max(h * 0.4, 0.05), corridor);
	h += (n - 0.5) * 0.3 * smoothstep(0.08, 0.22, route_d) * continent;
	return h;
}

void fragment() {
	vec2 uv = UV;
	float rd = route_dist(uv);
	float h = height_at(uv, rd);
	float hx = height_at(uv + vec2(texel, 0.0), rd) - height_at(uv - vec2(texel, 0.0), rd);
	float hy = height_at(uv + vec2(0.0, texel), rd) - height_at(uv - vec2(0.0, texel), rd);
	float det = texture(detail_tex, uv * 3.0).r;
	float det2 = texture(detail_tex, uv * 9.0 + vec2(0.37, 0.71)).r;

	// each highway's country fades smoothly into the next
	vec3 low = vec3(0.0);
	float wsum = 0.0;
	float snow_land = 0.0;
	for (int i = 0; i < 14; i++) {
		float d = seg_dist(uv, cities[i], cities[i + 1]);
		float w = exp(-d * 22.0);
		low += seg_col[i] * w;
		snow_land += seg_snow[i] * w;
		wsum += w;
	}
	low /= max(wsum, 1e-5);
	snow_land /= max(wsum, 1e-5);
	vec3 col;
	if (h < 0.0) {
		// sea: deep blue offshore, turquoise shallows near the coast
		vec3 deep = vec3(0.09, 0.2, 0.33);
		vec3 shallow = vec3(0.2, 0.44, 0.55);
		col = mix(deep, shallow, smoothstep(-0.18, 0.0, h));
		col += 0.02 * (det2 - 0.5);
		// a pale line of surf along the shore
		col = mix(col, vec3(0.62, 0.76, 0.78), smoothstep(-0.012, 0.0, h) * 0.6);
	} else {
		vec3 beach = vec3(0.82, 0.76, 0.58);
		vec3 forest = low * vec3(0.62, 0.78, 0.62);
		vec3 hills = vec3(0.52, 0.46, 0.34);
		vec3 rock = vec3(0.5, 0.49, 0.47);
		vec3 snow = vec3(0.95, 0.96, 0.98);
		col = mix(beach, low, smoothstep(0.0, 0.025, h));
		// patchy woodland on the lowlands
		float woods = smoothstep(0.55, 0.62, det) * (1.0 - smoothstep(0.18, 0.3, h));
		col = mix(col, forest, woods * 0.85);
		col = mix(col, hills, smoothstep(0.14, 0.24, h));
		col = mix(col, rock, smoothstep(0.24, 0.32, h));
		col = mix(col, snow, max(smoothstep(0.35, 0.43, h), snow_land * smoothstep(0.03, 0.1, h) * 0.8));
		// rivers in the valleys between hills, running to the sea
		float river = 1.0 - smoothstep(0.004, 0.009, abs(det - 0.5));
		river *= smoothstep(0.012, 0.03, h) * (1.0 - smoothstep(0.16, 0.24, h)) * smoothstep(0.025, 0.05, rd);
		col = mix(col, vec3(0.24, 0.47, 0.6), river * 0.9);
		// light from the north-west
		float shade = clamp(1.0 + (-hx * 0.8 - hy * 1.1) * 14.0, 0.65, 1.3);
		col *= shade;
		col += 0.03 * (det2 - 0.5);
	}
	// paper: faint grain and darker edges
	vec2 e = abs(uv - 0.5) * 2.0;
	col *= 1.0 - 0.18 * smoothstep(0.75, 1.0, max(e.x, e.y));
	COLOR = vec4(col, 1.0);
}
