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

varying vec3 obj_p;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	obj_p = VERTEX;
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
	ALBEDO = albedo * ao;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	CLEARCOAT = coat;
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
	EMISSION = env * tint * f * reflect_amount * mix(1.0, occ, 0.85);
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
}
