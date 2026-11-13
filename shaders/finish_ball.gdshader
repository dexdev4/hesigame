shader_type canvas_item;
// A little ball in a paint colour and finish: the swatches of the workshop's Paint and Wheels tabs. Drawn by the
// graphics chip, so a whole page of them costs nothing. The ball is lit from the upper left; each finish answers the
// light its own way (the same families as CarModel.FINISH_LOOKS).

uniform vec4 base : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform int finish = 0;  // 0 gloss, 1 semi-gloss, 2 matte, 3 metallic, 4 pearlescent, 5 candy, 6 chrome, 7 alloy (a wheel)
uniform vec4 ring : source_color = vec4(1.0, 1.0, 1.0, 0.0);  // the ring round it (alpha 0: none)
uniform float ring_width = 0.07;
uniform float dim = 0.0;  // a finish that is not owned yet is a little dimmer

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 hue_shift(vec3 c, float a) {
	// a rotation of the colour about the grey axis (YIQ), a being the angle in turns
	const mat3 to_yiq = mat3(vec3(0.299, 0.596, 0.211), vec3(0.587, -0.274, -0.523), vec3(0.114, -0.322, 0.312));
	const mat3 to_rgb = mat3(vec3(1.0, 1.0, 1.0), vec3(0.956, -0.272, -1.106), vec3(0.621, -0.647, 1.703));
	vec3 y = to_yiq * c;
	float ca = cos(a * 6.2832);
	float sa = sin(a * 6.2832);
	y.yz = vec2(y.y * ca - y.z * sa, y.y * sa + y.z * ca);
	return to_rgb * y;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float px = fwidth(r) * 1.2;
	float R = 0.74;  // the ball; the ring sits just outside it
	vec3 col = vec3(0.0);
	float a = 0.0;
	if (r < R + px) {
		vec2 q = p / R;
		float z = sqrt(max(0.0, 1.0 - dot(q, q)));
		vec3 n = vec3(q.x, -q.y, z);              // screen up is up
		vec3 L = normalize(vec3(-0.42, 0.62, 0.66));
		vec3 V = vec3(0.0, 0.0, 1.0);
		vec3 H = normalize(L + V);
		float ndl = max(dot(n, L), 0.0);
		float ndh = max(dot(n, H), 0.0);
		float edge = 1.0 - z;                      // 0 in the middle, 1 at the rim
		vec3 c = base.rgb;
		if (finish == 0) {          // gloss: a sharp highlight and a bright rim light
			col = c * (0.2 + 0.8 * ndl) + vec3(1.0) * pow(ndh, 130.0) * 0.95 + c * pow(edge, 3.0) * 0.25;
		} else if (finish == 1) {   // semi-gloss: the highlight is wide and soft
			col = c * (0.24 + 0.76 * ndl) + vec3(1.0) * pow(ndh, 22.0) * 0.32;
		} else if (finish == 2) {   // matte: nothing reflects, it falls away to dark
			col = c * 0.88 * (0.12 + 0.88 * pow(ndl, 0.85));
		} else if (finish == 3) {   // metallic: glitter in the paint
			float fl = step(0.93, hash21(floor(UV * 46.0)));
			col = c * (0.18 + 0.7 * ndl) + vec3(1.0) * pow(ndh, 50.0) * 0.55 + vec3(1.0) * fl * 0.65 * (0.4 + ndl);
		} else if (finish == 4) {   // pearlescent: the colour turns to another towards the rim
			vec3 pc = hue_shift(c, 0.09) * 1.15 + 0.08;
			vec3 body = mix(c, pc, clamp(pow(edge, 1.6) * 1.15, 0.0, 1.0));
			col = body * (0.22 + 0.78 * ndl) + vec3(1.0) * pow(ndh, 80.0) * 0.7 + pc * pow(edge, 2.0) * 0.25;
		} else if (finish == 5) {   // candy: deep colour, a bright metal glow in the middle, a tinted highlight
			vec3 deep = c * c * 1.6;
			col = deep * (0.12 + 0.88 * ndl) + c * 0.34 * pow(z, 1.5) + mix(vec3(1.0), c, 0.55) * pow(ndh, 90.0) * 0.9;
		} else if (finish == 6) {   // chrome: a mirror of a sky, a horizon and a road
			vec3 rv = reflect(-V, n);
			float h = rv.y;
			vec3 sky = mix(vec3(0.93, 0.92, 0.88), vec3(0.2, 0.4, 0.72), pow(clamp(h, 0.0, 1.0), 0.5));
			vec3 ground = mix(vec3(0.08, 0.09, 0.07), vec3(0.34, 0.35, 0.37), smoothstep(0.0, 0.7, clamp(-h, 0.0, 1.0)));
			col = mix(ground, sky, smoothstep(-0.03, 0.03, h));
			col = mix(col, col * mix(vec3(1.0), c * 1.4, 0.6), 0.7) + vec3(1.0) * pow(ndh, 140.0);
		} else {                    // alloy: brushed metal, a ring of fine lines
			float ang = atan(q.y, q.x);
			float brush = 0.5 + 0.5 * sin(ang * 90.0 + r * 6.0);
			col = c * (0.3 + 0.62 * ndl) * (0.93 + 0.07 * brush) + vec3(1.0) * pow(ndh, 40.0) * 0.4;
		}
		col *= 1.0 - dim * 0.3;
		a = 1.0 - smoothstep(R - px, R + px, r);
	}
	float rr = abs(r - (R + 0.13));
	float ring_a = ring.a * (1.0 - smoothstep(ring_width * 0.5 - px, ring_width * 0.5 + px, rr));
	col = mix(col, ring.rgb, ring_a);
	COLOR = vec4(col, max(a, ring_a));
}
