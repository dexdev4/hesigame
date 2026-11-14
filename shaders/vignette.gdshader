shader_type canvas_item;
// Medium graphics: a darkened edge drawn over the scene without reading the
// screen back, so it costs almost nothing.

uniform float vignette = 0.3;
uniform vec2 focus = vec2(0.5, 0.42);

void fragment() {
	vec2 d = SCREEN_UV - focus;
	float r = length(d * vec2(1.0, 0.8));
	COLOR = vec4(0.0, 0.0, 0.0, vignette * smoothstep(0.38, 0.95, r));
}
