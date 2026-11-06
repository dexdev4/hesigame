shader_type spatial;
// Distant mountains and clouds. Scene fog would hide them completely, so they
// skip it and blend into the horizon haze themselves.
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 base_col : source_color = vec3(0.42, 0.47, 0.55);
uniform vec3 top_col : source_color = vec3(0.6, 0.63, 0.68);
uniform vec3 haze_col : source_color = vec3(0.86, 0.74, 0.6);
uniform float haze = 0.55;
uniform float max_h = 240.0;
uniform bool cloud = false;
uniform sampler2D puff : filter_linear;

varying float h;

void vertex() {
	h = VERTEX.y;
}

void fragment() {
	if (cloud) {
		vec4 p = texture(puff, UV);
		ALBEDO = mix(vec3(1.0, 0.97, 0.93), haze_col, 0.25 + 0.3 * UV.y);
		ALPHA = p.a * 0.85;
	} else {
		float t = clamp(h / max_h, 0.0, 1.0);
		vec3 c = mix(base_col, top_col, t * t);
		ALBEDO = mix(c, haze_col, haze * (1.0 - 0.5 * t));
	}
}
