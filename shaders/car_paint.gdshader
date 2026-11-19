shader_type spatial;
// Car paint, gloss-black trim, chrome and alloy rims in one shader.
// Built-in lighting does the sun and soft sky light (with a clear coat for a
// tight highlight); on top, a sharp reflection of the surroundings
// (car_env.gdshaderinc) is added with Fresnel, so panels show the horizon
// line, sky and road the way real car paint does. Metallic flake glints in
// the sun up close. Vertex colour carries the baked ambient occlusion.

#include "res://shaders/car_env.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.7, 0.1, 0.1, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.3;
uniform float roughness : hint_range(0.0, 1.0) = 0.38;
uniform float coat : hint_range(0.0, 1.0) = 0.6;
uniform float coat_roughness : hint_range(0.0, 1.0) = 0.05;
uniform float reflect_amount : hint_range(0.0, 2.0) = 1.0;
uniform float reflect_f0 : hint_range(0.0, 1.0) = 0.04;  // reflectance head-on: 0.04 clear coat, ~0.9 chrome
uniform float metal_tint : hint_range(0.0, 1.0) = 0.0;   // reflections take the base colour (chrome, gold rims)
uniform float flake : hint_range(0.0, 2.0) = 0.0;        // metallic flake glints
uniform float flake_scale = 190.0;                       // flakes per metre
uniform float flake_far = 3.2;                           // how far away the flakes still show (metres)
uniform float flake_tint : hint_range(0.0, 1.0) = 0.55;  // how much of the paint colour the flakes take (0 white, 1 the colour itself)
uniform vec4 pearl_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);  // pearlescent: the colour it turns to at a glancing view
uniform float pearl : hint_range(0.0, 1.0) = 0.0;
uniform float candy : hint_range(0.0, 1.0) = 0.0;        // candy: a deep tinted lacquer over bright metal
uniform float sheen : hint_range(0.0, 1.0) = 0.0;        // matte and satin: a soft glow at glancing angles instead of reflections
// The inside of a model's body and greenhouse, seen through the glass: a material drawn from both sides (render_mode
// cull_disabled, see CarModel._car_shader_mat) shows its back faces in this colour when its alpha is set.
uniform vec4 back_color : source_color = vec4(0.0);
// The patterns the garage designer draws on a part, worked out here from where the part is in the car (see _pattern_uv):
// 1 a hexagon mesh grille, 2 slats, 3 carbon weave, 5 louvred vent, 9 quilting, 10 tartan, 11 pleats, 12 wood grain. When
// they get too fine for the pixels (far away) they fade to their average, so they never shimmer.
uniform int pattern = 0;

varying vec3 obj_p;
varying vec3 obj_n;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	obj_p = VERTEX;
	obj_n = NORMAL;
}


// The flat coordinates a pattern is laid out in (metres), as the designer lays its decals: on the side of the car, along it
// and up; on the front or back, across and up; on top, along and across. (x is across the car, y up, z along it.)
vec2 _pattern_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.y > 0.6) {
		return vec2(p.z, -p.x);
	}
	if (an.z > 0.6) {
		return vec2(-p.x, p.y);
	}
	return vec2(p.z, p.y);
}

void fragment() {
	vec3 ao = COLOR.rgb;
	float occ = (ao.r + ao.g + ao.b) / 3.0;
	vec3 albedo = base_color.rgb;
	float ndv0 = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (pearl > 0.0) {
		// a fine pearl layer in the paint: the colour turns towards the pearl hue as the panel turns away from the eye
		float turn = pow(1.0 - ndv0, 1.7);
		albedo = mix(albedo, pearl_color.rgb, clamp(turn * 1.2, 0.0, 1.0) * pearl);
	}
	if (candy > 0.0) {
		albedo = mix(albedo, albedo * albedo * 1.7, candy);  // deeper and richer than the same colour in plain paint
	}
	float rough_p = roughness;
	float coat_p = coat;
	float metal_p = metallic;
	float pat_dark = 0.0;   // how much of the surroundings' reflection the pattern takes away (the holes of a grille)
	if (pattern > 0) {
		vec2 uv = _pattern_uv(obj_p, obj_n);
		vec2 fw = fwidth(uv);
		float px = max(fw.x, fw.y);   // a pixel, in metres on the part
		float fine = 0.0;             // 0: the pattern as drawn, 1: too fine to draw, its average instead
		vec3 avg = albedo;
		if (pattern == 1) {   // hexagon mesh: holes 1.6 cm across
			vec2 q = uv / 0.016;
			const vec2 hs = vec2(1.0, 1.7320508);
			vec2 a = mod(q, hs) - hs * 0.5;
			vec2 b = mod(q - hs * 0.5, hs) - hs * 0.5;
			vec2 g = dot(a, a) < dot(b, b) ? a : b;
			vec2 ag = abs(g);
			float d = max(dot(ag, hs * 0.5), ag.x);
			float w = max(fwidth(d), 1e-4);
			float hole = 1.0 - smoothstep(0.36 - w, 0.36 + w, d);
			fine = smoothstep(0.004, 0.009, px);
			avg = albedo * 0.48;
			albedo = mix(albedo, vec3(0.0015), hole);
			rough_p = mix(rough_p, 0.95, hole);
			coat_p *= 1.0 - hole;
			metal_p *= 1.0 - hole;
			pat_dark = hole;
		} else if (pattern == 2 || pattern == 5) {   // slats across (3 cm), or a vent's louvres along (2.4 cm)
			float period = pattern == 2 ? 0.03 : 0.024;
			float c = (pattern == 2 ? uv.y : uv.x) / period;
			float w = max(fwidth(c), 1e-4);
			float f0 = fract(c);
			float lo = pattern == 2 ? 0.1 : 0.15;
			float hi = pattern == 2 ? 0.55 : 0.6;
			float bar = smoothstep(lo - w, lo + w, f0) * (1.0 - smoothstep(hi - w, hi + w, f0));
			fine = smoothstep(period * 0.2, period * 0.45, px);
			avg = albedo * (pattern == 2 ? 0.63 : 0.585);
			albedo = mix(vec3(0.0015), albedo * (pattern == 2 ? 1.4 : 1.3), bar);
			rough_p = mix(0.95, rough_p, bar);
			coat_p *= bar;
			pat_dark = 1.0 - bar;
		} else if (pattern == 3) {   // carbon weave, 5 mm tows
			vec2 c = floor(uv / 0.005);
			float t1 = mod(c.x + c.y, 4.0) < 2.0 ? 1.0 : 0.0;
			float t2 = mod(c.x - c.y + 400.0, 4.0) < 2.0 ? 1.0 : 0.0;
			fine = smoothstep(0.0012, 0.003, px);
			avg = albedo * 0.95;
			albedo *= mix(0.55, 1.35, mod(c.x, 2.0) < 1.0 ? t1 : t2);
		} else if (pattern == 9) {   // quilting: diamonds 5 cm across, stitched
			vec2 g = vec2(uv.x + uv.y, uv.x - uv.y) / 0.05;
			vec2 f2 = abs(fract(g) - 0.5);
			float st = 1.0 - smoothstep(0.0, 0.06, min(f2.x, f2.y));
			fine = smoothstep(0.006, 0.014, px);
			avg = albedo * 0.85;
			albedo *= mix(1.0, 0.45, st) * (0.85 + 0.3 * min(f2.x, f2.y));
		} else if (pattern == 10) {   // tartan cloth
			vec2 c = fract(uv / 0.07);
			float b1 = step(0.15, c.x) * step(c.x, 0.3) + step(0.15, c.y) * step(c.y, 0.3);
			float b2 = step(0.55, c.x) * step(c.x, 0.6) + step(0.55, c.y) * step(c.y, 0.6);
			fine = smoothstep(0.004, 0.01, px);
			avg = albedo * 0.8;
			albedo = mix(albedo, vec3(0.012), clamp(b1 * 0.6, 0.0, 1.0));
			albedo = mix(albedo, vec3(0.5, 0.5, 0.48), clamp(b2 * 0.5, 0.0, 1.0));
			rough_p = 0.95;
		} else if (pattern == 11) {   // horizontal pleats, 4.2 cm
			float v = abs(obj_n.y) > 0.6 ? obj_p.z : obj_p.y;
			float f0 = fract(v / 0.042);
			fine = smoothstep(0.006, 0.012, px);
			avg = albedo * 0.92;
			albedo *= 0.7 + 0.35 * smoothstep(0.0, 0.25, f0) * (1.0 - smoothstep(0.75, 1.0, f0));
		} else if (pattern == 12) {   // wood grain
			float g = sin(uv.x * 140.0 + sin(uv.y * 22.0) * 4.0 + sin(uv.x * 13.0) * 2.0);
			fine = smoothstep(0.003, 0.008, px);
			avg = albedo * 0.85;
			albedo *= 0.78 + 0.22 * g;
		}
		albedo = mix(albedo, avg, fine);
		pat_dark *= 1.0 - fine;
		rough_p = mix(rough_p, roughness, fine);   // (too fine to draw: the part's own finish all over)
		coat_p = mix(coat_p, coat, fine);
		metal_p = mix(metal_p, metallic, fine);
	}
	ALBEDO = albedo * ao;
	METALLIC = metal_p;
	ROUGHNESS = rough_p;
	CLEARCOAT = coat_p;
	CLEARCOAT_ROUGHNESS = coat_roughness;
	SPECULAR = 0.5;

	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r_w = reflect(-v_w, n_w);
	float ndv = dot(NORMAL, VIEW);
	float f = car_fresnel(reflect_f0, ndv);
	float aa = clamp(fwidth(r_w.y) * 1.2, 0.002, 0.08) + roughness * roughness * 0.25;
	vec3 env = car_environment(r_w, aa);
	vec3 tint = mix(vec3(1.0), albedo, metal_tint);
	// less of the surroundings reaches surfaces deep in the arches and low down
	EMISSION = env * tint * f * reflect_amount * mix(1.0, occ, 0.85) * (1.0 - pat_dark);
	if (candy > 0.0) {
		// the bright metal under the lacquer glows through it in the middle of each panel, in the lacquer's colour
		EMISSION += albedo * candy * 0.3 * pow(ndv0, 1.5) * occ;
	}
	if (sheen > 0.0) {
		EMISSION += mix(env, vec3(1.0), 0.4) * albedo * sheen * pow(1.0 - ndv0, 3.0) * 0.3 * occ;
	}

	if (flake > 0.0) {
		// Metal flake: tiny mirrors set at random angles in the paint. Each one shows a slightly different part of
		// the surroundings, and flashes when it lines up with the sun. They are small round dots scattered through
		// a lattice in the car's own space (a dot where the panel passes through one of the little spheres), and a
		// dot smaller than a pixel is spread over the pixel and dimmer for it, so the flake only ever shimmers, and
		// never crawls about as noise.
		float cell_m = 1.0 / flake_scale;
		float aa_c = clamp(max(length(fwidth(obj_p)), 1.0e-5) / cell_m * 0.6, 0.02, 1.5);   // a pixel, in flake cells
		float fade = 1.0 - smoothstep(flake_far * 0.6, flake_far, length(VERTEX));
		if (fade > 0.0) {
			vec3 q = obj_p * flake_scale;
			vec3 cell = floor(q);
			vec3 spot = vec3(hash13(cell + 1.3), hash13(cell + 5.7), hash13(cell + 9.1)) * 0.4 + 0.3;
			float radius = 0.17 + 0.12 * hash13(cell + 7.7);
			float d = length(fract(q) - spot);
			float dotm = smoothstep(radius + aa_c, max(radius - aa_c, 0.0), d) * (radius * radius) / (radius * radius + aa_c * aa_c);
			vec3 tilt = vec3(hash13(cell), hash13(cell + 19.19), hash13(cell + 47.7)) * 2.0 - 1.0;
			vec3 nf = normalize(n_w + tilt * 0.3);
			vec3 rf = reflect(-v_w, nf);
			float lit = clamp(dot(n_w, env_sun_dir) * 3.0, 0.0, 1.0);
			float glint = pow(max(dot(rf, env_sun_dir), 0.0), 60.0) * lit;
			vec3 seen = car_environment(rf, aa) * 0.25 + vec3(glint) * 0.7;
			EMISSION += seen * mix(vec3(1.0), base_color.rgb * 1.6, flake_tint) * dotm * flake * fade * 2.2 * occ;
		}
	}
	if (back_color.a > 0.5 && !FRONT_FACING) {   // the lining of the cabin: matt, in the shade of the roof
		ALBEDO = back_color.rgb * ao * 0.7;
		METALLIC = 0.0;
		ROUGHNESS = 0.85;
		CLEARCOAT = 0.0;
		SPECULAR = 0.3;
		EMISSION = vec3(0.0);
	}
}
