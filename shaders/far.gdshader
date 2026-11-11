shader_type spatial;
// Distant mountains and clouds. Scene fog would hide them completely, so they
// skip it and blend into the horizon haze themselves.
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 base_col : source_color = vec3(0.42, 0.47, 0.55);
uniform vec3 top_col : source_color = vec3(0.6, 0.63, 0.68);
uniform vec3 haze_col : source_color = vec3(0.85, 0.82, 0.76);
uniform float haze = 0.55;
uniform float max_h = 240.0;
uniform bool cloud = false;
uniform vec3 tint : source_color = vec3(1.0);  // dusk (scenery.gd set_dusk)
uniform sampler2D puff : filter_linear;

varying float h;

void vertex() {
	h = VERTEX.y;
}

void fragment() {
	if (cloud) {
		vec4 p = texture(puff, UV);
		// sunlit tops, cooler grey undersides
		vec3 lit = mix(vec3(1.0, 0.98, 0.95), vec3(0.74, 0.77, 0.83), smoothstep(0.35, 0.95, UV.y));
		ALBEDO = mix(lit, haze_col, 0.22) * tint;
		ALPHA = p.a * 0.85;
	} else {
		float t = clamp(h / max_h, 0.0, 1.0);
		vec3 c = mix(base_col, top_col, t * t);
		ALBEDO = mix(c, haze_col, haze * (1.0 - 0.5 * t)) * tint;
	}
}
