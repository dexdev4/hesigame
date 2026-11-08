shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
// Tinted car glass: you see into the cabin when looking straight through,
// while at shallow angles it turns into a mirror of the sky and horizon,
// like a real windscreen.

#include "res://shaders/car_env.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.025, 0.035, 0.045, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.3;  // how much of the cabin shows head-on
uniform float reflect_amount : hint_range(0.0, 2.0) = 1.0;

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
	// blending scales everything by ALPHA, so lift the reflection to keep it at full strength
	// a little more than plain Fresnel: car glass is coated and the cabin behind it is dark
	EMISSION = env * min(0.1 + f * 1.25, 1.0) * reflect_amount / max(ALPHA, 0.05);
}
