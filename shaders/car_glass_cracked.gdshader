shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Car glass that a crash has cracked: exactly the glass of car_glass.gdshader (keep the two in step), with cracks
// and a haze drawn round the places where a window was hit. Only a car whose window has cracked uses it (a
// ShaderMaterial of its own, see CarModel.crack_glass), so the glass of every other car stays the plain shader.

#include "res://shaders/car_env.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.025, 0.035, 0.045, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.62;  // how much of the cabin shows head-on (the seats, the dash and the driver's hands should be easy to see)
uniform float reflect_amount : hint_range(0.0, 2.0) = 1.0;

// Where a window was hit: xyz in the car's own space, w how badly (0 not at all, 1 shattered). Up to two windows.
uniform vec4 crack_a = vec4(0.0);
uniform vec4 crack_b = vec4(0.0);

varying vec3 obj_p;
varying vec3 obj_n;

void vertex() {
	obj_p = VERTEX;
	obj_n = NORMAL;
}

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

// Cracks round a hit: spokes out from it, rings joining them, strongest at the point and gone beyond `reach`.
float crack_web(vec3 p, vec3 n, vec4 c) {
	if (c.w <= 0.0) {
		return 0.0;
	}
	vec3 d = p - c.xyz;
	float r = length(d);
	float reach = 0.2 + 0.8 * c.w;
	if (r > reach || r < 0.004) {
		return 0.0;
	}
	float nl = length(n);
	if (nl < 0.001) {
		return 0.0;
	}
	n /= nl;
	vec3 up = abs(n.y) > 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 t1 = normalize(cross(n, up));
	vec3 t2 = cross(n, t1);
	float a = atan(dot(d, t2), dot(d, t1)) / 6.2832 + 0.5;
	float sector = floor(a * 11.0);
	float off = abs(fract(a * 11.0 + (hash11(sector) - 0.5) * 0.35) - 0.5) * (6.2832 / 11.0) * r;  // metres from the nearest spoke
	float spokes = 1.0 - smoothstep(0.002, 0.011, off);
	float ring_gap = 0.075 + 0.04 * hash11(sector + 3.0);
	float ring = 1.0 - smoothstep(0.001, 0.008, abs(fract(r / ring_gap + hash11(sector) * 0.6) - 0.5) * ring_gap);
	float lines = max(spokes, ring * 0.75 * step(0.04, r));
	return lines * (1.0 - smoothstep(reach * 0.55, reach, r));
}

// A milky haze over a badly broken pane.
float crack_haze(vec3 p, vec4 c) {
	if (c.w < 0.55) {
		return 0.0;
	}
	float reach = 0.2 + 0.8 * c.w;
	return (1.0 - smoothstep(reach * 0.5, reach, distance(p, c.xyz))) * smoothstep(0.55, 1.0, c.w);
}

void fragment() {
	vec3 n_w = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v_w = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r_w = reflect(-v_w, n_w);
	float f = car_fresnel(0.06, dot(NORMAL, VIEW));
	float aa = clamp(fwidth(r_w.y) * 1.2, 0.002, 0.08);
	vec3 env = car_environment(r_w, aa);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = clamp(1.0 - clarity + f * 0.6, 0.0, 0.97);
	float ck = max(crack_web(obj_p, obj_n, crack_a), crack_web(obj_p, obj_n, crack_b));
	float haze = max(crack_haze(obj_p, crack_a), crack_haze(obj_p, crack_b));
	ALPHA = clamp(ALPHA + ck * 0.8 + haze * 0.25, 0.0, 1.0);  // (a broken window is still a window: the haze only dims what is behind it)
	ALBEDO = mix(ALBEDO, vec3(0.8, 0.84, 0.88), clamp(ck + haze * 0.3, 0.0, 1.0));
	// blending scales everything by ALPHA, so lift the reflection to keep it at full strength
	// a little more than plain Fresnel: car glass is coated and the cabin behind it is dark
	EMISSION = env * min(0.1 + f * 1.25, 1.0) * reflect_amount / max(ALPHA, 0.05);
}
