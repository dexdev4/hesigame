// The world as a car's paint, glass and chrome see it, for sharp reflections.
// The engine's own sky reflection is soft (a small, blurred radiance map) and
// its horizon is almost as bright as the ground, so cars looked flat. This
// gives every glossy part a crisp horizon line: blue sky fading to a bright
// hazy horizon, a dark band of trees and barriers just below it, then the
// grey road. Colours match the sky set up in game.gd.

uniform vec3 env_zenith : source_color = vec3(0.16, 0.33, 0.58);
uniform vec3 env_horizon : source_color = vec3(0.93, 0.9, 0.84);
uniform vec3 env_treeline : source_color = vec3(0.07, 0.085, 0.06);
uniform vec3 env_road : source_color = vec3(0.25, 0.26, 0.28);
uniform vec3 env_sun_dir = vec3(-0.545, 0.53, 0.65);  // towards the sun (game.gd's DirectionalLight)

// 1 while the garage is showing (set by garage_scene.gd), 0 on the road: then everything glossy reflects the workshop.
global uniform float env_studio;

// The workshop as paint and glass see it: a dark room, long light bars in the ceiling, warm light slats
// along the walls and the glowing ring of the turntable on the floor (the same room garage_scene.gd builds).
vec3 studio_environment(vec3 r, float aa) {
	float y = r.y;
	float soft = aa * 6.0 + 0.04;
	vec3 col = vec3(0.03, 0.032, 0.036);                           // dark walls
	if (y > 0.0) {
		vec2 p = r.xz / max(y, 0.04) * 5.0;                        // where the ray meets the ceiling, 5 m over the car
		float bars = 0.0;
		for (int i = 0; i < 4; i++) {
			float bx = -4.5 + 3.0 * float(i);
			bars = max(bars, smoothstep(0.36 + soft, 0.16, abs(p.x - bx)) * smoothstep(7.0 + soft * 4.0, 5.5, abs(p.y)));
		}
		col = mix(col, vec3(3.4, 3.3, 3.2), bars * smoothstep(0.1, 0.4, y));
		float az = atan(r.x, r.z);
		float slats = pow(0.5 + 0.5 * sin(az * 34.0), 10.0);
		col += vec3(1.0, 0.6, 0.18) * slats * 0.4 * smoothstep(0.55, 0.0, y);   // backlit slats in the walls
		col += vec3(1.0, 0.62, 0.2) * 0.8 * exp(-abs(y - 0.06) * 36.0);        // the LED line round the walls
	} else {
		vec2 q = r.xz / max(-y, 0.04) * 0.8;                       // where it meets the floor
		float ring = smoothstep(0.3, 0.0, abs(length(q) - 3.6));
		col = vec3(0.02, 0.022, 0.026) + vec3(1.0, 0.62, 0.2) * ring * 1.1;
	}
	return col;
}

// r: reflection direction in world space (y up). aa: blur of the horizon edge.
vec3 car_environment(vec3 r, float aa) {
	if (env_studio > 0.5) {
		return studio_environment(r, aa);
	}
	float y = r.y;
	float up = clamp(y, 0.0, 1.0);
	vec3 sky = mix(env_horizon, env_zenith, pow(smoothstep(0.0, 0.95, up), 0.5));
	sky += env_horizon * 0.45 * exp(-up * 26.0);              // bright haze right on the horizon
	float toward_sun = max(dot(normalize(vec3(r.x, max(r.y, 0.0), r.z)), env_sun_dir), 0.0);
	sky += vec3(1.0, 0.93, 0.8) * pow(toward_sun, 6.0) * 0.35;  // glow round the sun
	// soft clouds: broad bands that keep large panels from looking plain
	float cl = sin(r.x * 5.0 + r.z * 3.0) * sin(r.z * 4.0 - r.x * 2.0 + 1.3);
	sky = mix(sky, env_horizon * 1.05, smoothstep(0.35, 0.9, cl) * 0.35 * smoothstep(0.08, 0.35, up));
	float down = clamp(-y, 0.0, 1.0);
	vec3 ground = mix(env_treeline, env_road, smoothstep(0.015, 0.2, down));
	ground *= 1.0 - 0.45 * smoothstep(0.35, 1.0, down);       // the shade under the car itself
	return mix(ground, sky, smoothstep(-aa, aa, y));
}

// Schlick's Fresnel: how much a surface reflects at this viewing angle.
float car_fresnel(float f0, float ndv) {
	float k = 1.0 - clamp(ndv, 0.0, 1.0);
	float k2 = k * k;
	return f0 + (1.0 - f0) * k2 * k2 * k;
}
