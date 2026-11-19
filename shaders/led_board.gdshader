shader_type spatial;
render_mode unshaded, cull_back;
// One row of a fuel station's price board: seven-segment figures lit like LEDs on a dark face (LedBoard builds the
// quad and sets the figures). The quad is ASPECT x 1 (width x height, in units of its height): five figure cells and
// a gap for the decimal point, which sits after `point_after` of them. A segment that is on glows (in HDR, so that it
// blooms where the game has bloom), one that is off shows as a faint ghost of the 8, and up close the lit segments are
// made of tiny dots, as a real LED panel is. From far off the dots and the segments blur into a glow of the board's
// colour that is still bright, so a sign can be seen from a long way and read from nearer.

uniform vec4 lit_color : source_color = vec4(1.0, 0.6, 0.06, 1.0);
uniform float level = 2.4;                 // how bright a lit segment is (above 1 is HDR)
uniform vec4 cells_a = vec4(10.0);         // the figure in cells 0 to 3: 0..9, anything else is a blank cell
uniform float cell_b = 10.0;               // ...and in cell 4
uniform float point_after = 3.0;           // the decimal point comes after this many cells (0: none)
uniform float ghost = 0.05;                // how bright a segment that is off is

const int N = 5;
const float PITCH = 0.54;                  // a cell's width
const float GAP = 0.2;                     // the room for the decimal point
const float MARGIN = 0.22;                 // from the board's edge to the first cell
const float ASPECT = 3.34;                 // 2 * MARGIN + N * PITCH + GAP
const float GW = 0.4;                      // a figure: its width, height, the thickness of a bar and the gap between bars
const float GH = 0.74;
const float T = 0.105;
const float G = 0.014;
const float R = 0.036;                     // the rounding of a bar's corners
const float SLANT = 0.1;                   // the figures lean a little, as LED figures do

// the bars: a (top), b (top right), c (bottom right), d (bottom), e (bottom left), f (top left), g (middle)
const vec2 SEG_C[7] = vec2[7](
	vec2(0.0, GH * 0.5 - T * 0.5), vec2(GW * 0.5 - T * 0.5, GH * 0.25), vec2(GW * 0.5 - T * 0.5, -GH * 0.25),
	vec2(0.0, -GH * 0.5 + T * 0.5), vec2(-GW * 0.5 + T * 0.5, -GH * 0.25), vec2(-GW * 0.5 + T * 0.5, GH * 0.25),
	vec2(0.0, 0.0));
const vec2 SEG_H[7] = vec2[7](
	vec2(GW * 0.5 - T - G, T * 0.5), vec2(T * 0.5, GH * 0.25 - G), vec2(T * 0.5, GH * 0.25 - G),
	vec2(GW * 0.5 - T - G, T * 0.5), vec2(T * 0.5, GH * 0.25 - G), vec2(T * 0.5, GH * 0.25 - G),
	vec2(GW * 0.5 - T - G, T * 0.5));
// which bars each figure lights (bit 0 is a ... bit 6 is g)
const int MASK[10] = int[10](63, 6, 91, 79, 102, 109, 125, 7, 127, 111);

float bar(vec2 p, int k) {
	vec2 d = abs(p - SEG_C[k]) - (SEG_H[k] - vec2(R));
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - R;
}

void fragment() {
	// where this is on the board, in units of its height (y up)
	float x = UV.x * ASPECT;
	float y = 1.0 - UV.y;
	float px = (fwidth(UV.x) * ASPECT + fwidth(UV.y)) * 0.5;  // how big a pixel is in those units
	float edge = max(px * 0.8, 0.002);

	float on = 0.0;     // how much of a lit bar this pixel is
	float off = 0.0;    // ...and of one that is off
	float halo = 0.0;   // the glow round a lit bar
	float core = 0.0;   // how far inside a lit bar (its middle is the hottest)
	float xa = x - MARGIN;
	float gap_at = point_after * PITCH;
	bool in_gap = false;
	if (point_after > 0.5 && xa >= gap_at) {
		if (xa < gap_at + GAP) {
			in_gap = true;
		}
		xa -= GAP;
	}
	if (in_gap) {
		// the decimal point: a round dot at the foot of the figures, leaning with them
		float yc = -GH * 0.5 + T * 0.55;
		vec2 c = vec2(gap_at + MARGIN + GAP * 0.5 + yc * SLANT, 0.5 + yc);
		float d = length(vec2(x, y) - c) - T * 0.62;
		float xg = x - MARGIN - gap_at;
		on = 1.0 - smoothstep(-edge, edge, d);
		halo = exp(-max(d, 0.0) / 0.035) * smoothstep(0.0, 0.05, min(xg, GAP - xg));
		core = smoothstep(0.0, -T * 0.5, d);
	} else if (xa >= 0.0 && xa < float(N) * PITCH) {
		int i = int(floor(xa / PITCH));
		float code = i < 4 ? cells_a[clamp(i, 0, 3)] : cell_b;
		int mask = (code > -0.5 && code < 9.5) ? MASK[clamp(int(code + 0.5), 0, 9)] : 0;
		vec2 p = vec2(xa - float(i) * PITCH - PITCH * 0.5, y - 0.5);
		p.x -= p.y * SLANT;
		float d_on = 1.0e3;
		float d_off = 1.0e3;
		for (int k = 0; k < 7; k++) {
			float d = bar(p, k);
			if (((mask >> k) & 1) == 1) {
				d_on = min(d_on, d);
			} else {
				d_off = min(d_off, d);
			}
		}
		on = 1.0 - smoothstep(-edge, edge, d_on);
		off = (1.0 - smoothstep(-edge, edge, d_off)) * (1.0 - on);
		// (the glow round a bar dies away before the edge of its cell, or the cells would show as lighter boxes)
		float lxc = xa - float(i) * PITCH;
		halo = exp(-max(d_on, 0.0) / 0.035) * smoothstep(0.0, 0.07, min(lxc, PITCH - lxc));
		core = smoothstep(0.0, -T * 0.5, d_on);
	}

	// the LED dots in a lit bar, up close (a dot every 0.035: gone when a pixel is as big as one)
	vec2 g = fract(vec2(x, y) / 0.035) - 0.5;
	float dot_m = smoothstep(0.5, 0.26, length(g));
	float dots = mix(1.0, 0.5 + 0.9 * dot_m, 1.0 - smoothstep(0.012, 0.03, px));

	vec3 lc = lit_color.rgb;
	vec3 hot = mix(lc, vec3(1.0, 0.93, 0.75), 0.4 * core);
	vec3 col = vec3(0.012, 0.012, 0.016);                              // the dark face
	col += hot * level * (0.72 + 0.45 * core) * dots * on;             // lit bars
	col += lc * level * 0.16 * halo * (1.0 - on);                      // their glow on the face
	col += lc * ghost * off;                                           // bars that are off
	// from far off the figures have no detail: the board is a patch of its colour, so that a sign is seen from a long way
	// (a pixel as big as a tenth of the board's height or more: the whole face glows, as a lit-up sign does)
	float far_k = smoothstep(0.045, 0.2, px);
	col = mix(col, lc * level * 0.55, far_k * 0.8);
	// the frame
	float eb = min(min(UV.x * ASPECT, (1.0 - UV.x) * ASPECT), min(UV.y, 1.0 - UV.y));
	col = mix(col, vec3(0.2, 0.21, 0.23), 1.0 - smoothstep(0.0, 0.04, eb));
	ALBEDO = col;
}
