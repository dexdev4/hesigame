shader_type spatial;
// Plain material for the right-hand guardrail, its posts and the roadside
// markers, which leave a gap where a fuel stop's exit lane leaves the
// highway. Every piece is a separate short box whose UV.x holds the z of its
// centre; a piece whose centre falls inside a gap is collapsed to a point in
// the vertex shader (no per-pixel discard, which some GPUs handle badly).
// cut_a / cut_b: world z ranges (near, far); only the right-hand side (x > 4).

uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float glow = 0.0;
uniform vec2 cut_a = vec2(-1.0e6, -1.0e6);
uniform vec2 cut_b = vec2(-1.0e6, -1.0e6);

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(VERTEX.x, VERTEX.y, UV.x, 1.0)).xyz;
	if (c.x > 4.0 && ((c.z < cut_a.x && c.z > cut_a.y) || (c.z < cut_b.x && c.z > cut_b.y))) {
		VERTEX = vec3(0.0, -50.0, 0.0);
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = albedo.rgb * glow;
}
