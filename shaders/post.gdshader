shader_type canvas_item;
// Full-screen finish for the High graphics setting: radial speed blur towards
// the screen edges, a touch of colour fringing at speed, a filmic grade and a
// vignette. The centre of the screen (the road ahead) stays sharp.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float speed = 0.0;      // 0 standing still .. 1 flat out
uniform float vignette = 0.32;
uniform vec2 focus = vec2(0.5, 0.42);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	float r = length(d * vec2(1.0, 0.8));
	vec3 col = texture(screen_tex, uv).rgb;
	float amt = speed * speed * smoothstep(0.16, 0.62, r) * 0.055;
	if (amt > 0.0008) {
		vec3 acc = col;
		for (int i = 1; i < 6; i++) {
			acc += texture(screen_tex, uv - d * amt * float(i) / 5.0).rgb;
		}
		col = acc / 6.0;
		// slight fringing where the blur is strongest
		float ca = amt * 0.12;
		col.r = mix(col.r, texture(screen_tex, uv + d * ca).r, 0.6);
		col.b = mix(col.b, texture(screen_tex, uv - d * ca).b, 0.6);
	}
	// gentle S-curve and warm highlights / cool shadows
	vec3 graded = col * col * (3.0 - 2.0 * col);
	col = mix(col, graded, 0.18);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col += (vec3(1.0, 0.97, 0.92) - 1.0) * lum * 0.35 + (vec3(0.95, 0.98, 1.04) - 1.0) * (1.0 - lum) * 0.25;
	col *= 1.0 - vignette * smoothstep(0.38, 0.95, r);
	COLOR = vec4(col, 1.0);
}
