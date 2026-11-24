// Details of the real cars each design is drawn after that the designs themselves leave out, so that every car reads as a
// real one up close: its badge on the nose, the shark-fin or mast antenna, the third brake light, the side repeaters (or,
// on the American cars, the amber and red side markers), the fuel filler door, the wiper on a hatchback's rear window, the
// rear doors of the van; and a chrome bezel round each headlamp projector or bulb, as in a real lamp. designer.js puts this
// into the designer's code after more_cars.js (CARS, makeDecal, FR and every helper of the page are in scope). Each car's own
// extras run first, then these. Everything here is small and on the body, inside the car's outline: the hit boxes, measured
// from the meshes afterwards, are unchanged by it.
{
// what each car gets (the designer's own terms: x back from the nose, y up, metres; side 1 is the left, -1 the right)
//   badge: on the nose (y: its height, rx/ry: half size, layer 1 on a grille; round: a roundel; bar: a bar) or, with top: x,
//          on the bonnet, seen from above
//   fin: a shark-fin antenna just ahead of the rear window; mast: a mast antenna, 'front' or 'rear' of the roof, or {x, side}
//          on a front wing
//   chmsl: the third brake light: 'roof' on the roof's back edge (hatchbacks, the SUV), 'glass' inside the top of the rear
//          window (saloons and coupes), {x, base, dy} under a roof spoiler (at roofline(base) + dy), 'van' high on the back
//   wiper: the rear wiper of a hatchback, parked along the bottom of the rear window
//   fuel: the filler door over the rear wheel {side, r} (or w and h for a square flap; x and y to place it by hand; cap: a
//          chrome filler cap in it)
//   repeater: an amber repeater on each front wing; markers: the US side markers, amber at the front, red at the back
// (the new lenses, badges and bezels are in materials the cars already have, the designer's own amber and red lenses, trim
// and chrome, so that they add no surface, and no draw call, to a car)
const DET = {
  pulse:   {badge: {y: .708, rx: .036, ry: .024}, fin: true, chmsl: {x: 3.826, base: 3.6, dy: -.016}, wiper: true, fuel: {side: -1}},
  vector:  {badge: {y: .63, rx: .04, ry: .024, layer: 1}, fin: true, chmsl: 'glass', fuel: {side: -1}, repeater: true},
  hornet:  {mast: 'rear', chmsl: {x: 3.216, base: 3.04, dy: -.022}, wiper: true, fuel: {side: -1, r: .072}, repeater: true},
  comet:   {badge: {y: .535, rx: .034, ry: .022}, fin: true, chmsl: 'glass', fuel: {side: 1}},
  kestrel: {badge: {y: .665, rx: .042, ry: .042, layer: 1, round: true}, mast: 'front', wiper: true, fuel: {side: -1}, repeater: true},
  vanta:   {badge: {y: .64, rx: .036, ry: .036, round: true}, fin: true, chmsl: 'glass', fuel: {side: -1}},
  bruiser: {badge: {y: .6, rx: .07, ry: .018, layer: 1, bar: true}, chmsl: 'glass', fuel: {side: -1, r: .07, cap: true}, markers: true},
  halcyon: {badge: {top: .2, rx: .02, ry: .03}},
  copperhead: {mast: {x: -.3, side: -1}, markers: true},
  marshal: {badge: {y: .7, rx: .04, ry: .026, layer: 1}, chmsl: 'glass', fuel: {side: 1}, markers: true},
  static:  {badge: {top: .24, rx: .018, ry: .028}, fuel: {side: -1, w: .12, h: .07}},
  lastexit:{badge: {top: .3, rx: .026, ry: .022}},
  suv:     {badge: {y: .72, rx: .045, ry: .03, layer: 1}, fin: true, chmsl: 'roof', wiper: true, fuel: {side: -1, r: .09}},
  van:     {badge: {y: .76, rx: .055, ry: .035, layer: 1}, chmsl: 'van', fuel: {side: 1, x: 2.45, y: .95, r: .07}, van: true},
  sedan:   {badge: {y: .67, rx: .042, ry: .028, layer: 1}, fin: true, chmsl: 'glass', fuel: {side: 1}, markers: true},
  hatch:   {badge: {y: .685, rx: .036, ry: .03, layer: 1, round: true}, mast: 'rear', chmsl: 'roof', wiper: true, fuel: {side: -1}, repeater: true},
};
// the lenses the details add (the designer's own amberLens is darker: a lamp's unlit corner)
const DET_MATS = {
  chmsl: {c: '#ff2616', m: 0, r: .2, e: [6.5, .3, .16]},
};

// ---- the pieces
// a small rounded box (the page's own has 400 triangles, for a part the size of a fist: these are a few centimetres)
function box(mat, c, h, e = .3, rot = null) { const p = rbox(mat, h[0], h[1], h[2], e, 4, 8); p.xf(rot || M3.I(), c); return p; }
// the bezel: a shape grown by m all round (about the middle of its bounding box)
function grown(shape, m) {
  let u0 = 1e9, u1 = -1e9, v0 = 1e9, v1 = -1e9;
  for (const [u, v] of shape) { u0 = Math.min(u0, u); u1 = Math.max(u1, u); v0 = Math.min(v0, v); v1 = Math.max(v1, v); }
  const cu = (u0 + u1) / 2, cv = (v0 + v1) / 2, hu = Math.max((u1 - u0) / 2, 1e-4), hv = Math.max((v1 - v0) / 2, 1e-4);
  return {shape: shape.map(([u, v]) => [cu + (u - cu) * (hu + m) / hu, cv + (v - cv) * (hv + m) / hv]), cu, cv, hu, hv};
}
// a shark fin on the roof at x: low at the front, highest two thirds back, then a short steep tail
function fin(k, x0, mat = 'paint', len = .17, h = .058, w = .064) {
  const api = k.api, cab = api.cab, p = new Part(mat), n = 14, M = 10;
  const rows = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n, x = x0 + t * len, yb = cab.roofF(x) - .003;
    const ht = t <= .72 ? h * Math.pow(Math.sin(t / .72 * Math.PI / 2), 1.2) : h * (1 - Math.pow((t - .72) / .28, 2) * .8);
    const wt = w / 2 * (.3 + .7 * Math.sin(Math.PI * Math.pow(t, .75)));
    rows.push({x, yb, ht, wt});
  }
  grid(p, n + 1, M + 1, (i, j) => { const r = rows[i], a = Math.PI * j / M; return [r.x, r.yb + r.ht * Math.pow(Math.sin(a), .7), r.wt * Math.cos(a)]; });
  // (the tail closed by a fan)
  const r = rows[n], base = (n) * (M + 1), c = p.v(r.x, r.yb + r.ht * .3, 0);
  for (let j = 0; j < M; j++) p.t(base + j, base + j + 1, c);
  p.normals().orientOut([x0 + len / 2, cab.roofF(x0 + len / 2) - .05, 0]);
  k.add(p);
}
// a thin mast antenna from base (x, y, z), leaning back by `lean` (radians from upright)
function mast(k, x, y, z, lean, len = .3) {
  const tip = [x + Math.sin(lean) * len, y + Math.cos(lean) * len, z];
  k.add(k.cyl('trim', [x, y - .004, z], tip, .0042, .0022, 8));
  k.add(box('trim', [x, y + .004, z], [.018, .009, .012], .45));
}
// the third brake light: a dark housing with a red lens facing back, and the lens's lit face just behind it, which the game
// shows only while the car brakes (material 'chmsl', category 'brake')
function chmsl(k, x, y, slope, wide = .13) {
  const r = M3.rz(Math.atan(slope)), c = Math.cos(Math.atan(slope)), s = Math.sin(Math.atan(slope));
  k.add(box('trim', [x, y, 0], [.013, .009, wide + .01], .35, r));
  k.add(box('tl', [x + .0105 * c, y + .0105 * s, 0], [.004, .0062, wide], .3, r));
  k.add(box('chmsl', [x + .0112 * c, y + .0112 * s, 0], [.0039, .0056, wide - .004], .3, r));
}
// a rear wiper parked along the bottom of the rear window, pivoting in the middle
function rearWiper(k, x, len = .34) {
  const f = k.api.cab.roofF, s = (f(x + .01) - f(x - .01)) / .02, l = Math.hypot(1, s), n = [-s / l, 1 / l];
  const at = d => [x + n[0] * d, f(x) + n[1] * d];
  const r = M3.rz(Math.atan(s));
  const [px, py] = at(.012);
  k.add(box('trim', [px, py, 0], [.017, .011, .017], .5, r));
  const [ax, ay] = at(.016);
  k.add(box('trim', [ax, ay, len * .28], [.007, .006, len * .28], .3, r));
  const [bx, by] = at(.011);
  k.add(box('trim', [bx, by, len * .56], [.006, .005, len * .44], .25, r));
}
// a dark seam round a flap in the side (the fuel filler door), as the panel lines are drawn: a thin strip laid on the body
// (made a decal so that __snapDecals lays it on the body's own triangles, just off them)
function flapSeam(k, side, x, y, a, b = a, corner = a) {
  const api = k.api, N = 48, pts = [];
  if (a === b && corner === a) for (let i = 0; i < N; i++) { const t = i / N * Math.PI * 2; pts.push([Math.cos(t), Math.sin(t)]); }
  else for (const s of pg([[-a, -b], [a, -b], [a, b], [-a, b]], corner, 6)) pts.push([s[0], s[1]]);
  const p = new Part('seam'), hw = .0011;
  const ring = pts.map(([u, v], i) => {
    const q = pts[(i + 1) % pts.length], o = pts[(i - 1 + pts.length) % pts.length], tx = q[0] - o[0], ty = q[1] - o[1], tl = Math.hypot(tx, ty) || 1;
    const nx = ty / tl, ny = -tx / tl;   // (outwards, for a ring drawn anticlockwise)
    return [0, 1].map(e => { const sx = x + (a === b && corner === a ? u * a : u) + nx * hw * (e ? 1 : -1), sy = y + (a === b && corner === a ? v * a : v) + ny * hw * (e ? 1 : -1);
      return [sx, sy, side * api.hwAt(sx, sy)]; });
  });
  for (const [ip, op] of ring) { p.v(...ip); p.v(...op); }
  const m = ring.length;
  for (let i = 0; i < m; i++) { const j = (i + 1) % m; p.q(2 * i, 2 * j, 2 * j + 1, 2 * i + 1); }
  p.normals();
  p.decal = [0, 0, -side]; p.layer = -.55;
  k.add(p);
}
function sideDecal(k, side, shape, mat, layer = 0) { k.add(makeDecal(k.api, shape, mat, FR.S(k.L, side), layer)); }

function details(S, k, d) {
  const api = k.api, cab = api.cab, L = k.L, W = S.wheels;
  if (d.badge) {
    const b = d.badge, ly = b.layer || 0;
    if (b.top != null) {   // on the bonnet, seen from above (u: back from the nose, v: across)
      k.T(el(b.top, 0, b.rx, b.ry), 'chrome', ly, false);
      k.T(el(b.top, 0, b.rx * .74, b.ry * .76), 'trim', ly + 1, false);
      k.T(rr(b.top, 0, b.rx * .5, b.ry * 1.05, b.rx * .2), 'chrome', ly + 2, false);
    } else if (b.bar) {    // a chrome bar badge
      k.F(rr(0, b.y, b.rx * 2, b.ry * 2, b.ry * .6), 'chrome', ly, false);
      k.F(rr(0, b.y, b.rx * 1.7, b.ry * 1.1, b.ry * .4), 'trim', ly + 1, false);
    } else {               // a chrome ring with a dark field and a chrome emblem in it
      k.F(el(0, b.y, b.rx, b.ry), 'chrome', ly, false);
      k.F(el(0, b.y, b.rx * .8, b.ry * .78), 'trim', ly + 1, false);
      if (b.round) k.F(el(0, b.y, b.rx * .36, b.ry * .36), 'chrome', ly + 2, false);
      else k.F(rr(0, b.y, b.rx * 1.05, b.ry * .42, b.ry * .2), 'chrome', ly + 2, false);
    }
  }
  const C = cab.C, f = cab.roofF, rw = C.rwTop || (cab.x1 - .45);
  if (d.fin) fin(k, rw - .25);
  if (d.mast === 'front') { const x = (C.wsTop || cab.x0 + .5) + .07; mast(k, x, f(x), 0, .7, .3); }
  else if (d.mast === 'rear') { const x = rw - .1; mast(k, x, f(x), 0, .5, .24); }
  else if (d.mast) {   // on a front wing, just ahead of the windscreen (x: from the windscreen's foot)
    const x = cab.x0 + d.mast.x, z = d.mast.side * (api.hwAt(x, api.topY(x, 0) - .05) - .09);
    mast(k, x, api.topY(x, z), z, .22, .42);
  }
  if (d.chmsl) {
    if (d.chmsl === 'roof' || d.chmsl === 'glass') {
      const x = d.chmsl === 'roof' ? rw - .016 : rw + .05, s = (f(x + .01) - f(x - .01)) / .02;
      chmsl(k, x, f(x) + (d.chmsl === 'roof' ? .007 : -.017), s, d.chmsl === 'roof' ? .13 : .12);
    } else if (d.chmsl === 'van') {   // at the top of the van's back, on the greenhouse
      let x = cab.x1;
      for (let t = cab.x1 - .5; t <= cab.x1; t += .002) if (f(t) < 2.27) { x = t; break; }
      chmsl(k, x + .006, 2.27, 0, .16);
    } else chmsl(k, d.chmsl.x, f(d.chmsl.base) + d.chmsl.dy, 0, .12);
  }
  if (d.wiper) {   // (its pivot a hand's breadth above the foot of the rear window)
    let x = cab.x1;
    for (let t = cab.x1; t > cab.x1 - .6; t -= .002) if (f(t) - cab.baseY(t) > .1) { x = t - .03; break; }
    rearWiper(k, x, S.id === 'suv' ? .4 : .34);
  }
  if (d.fuel) {
    // (over the back half of the rear wheel arch, where it curves down and leaves room under the window line)
    const fu = d.fuel, x = fu.x != null ? fu.x : W.xR + .16, top = cab.baseY(x) - .05;
    const bot = W.rR + Math.sqrt(Math.max(0, (W.rR + .06) ** 2 - (x - W.xR) ** 2)) + .05;
    let r = fu.r || (fu.w ? Math.max(fu.w, fu.h) / 2 : .08);
    r = Math.min(r, Math.max(.05, (top - bot) / 2));
    const y = fu.y != null ? fu.y : Math.min(top - r, Math.max(bot + r, (top + bot) / 2));
    if (fu.w) flapSeam(k, fu.side, x, y, fu.w / 2, fu.h / 2, .018);
    else flapSeam(k, fu.side, x, y, r);
    if (fu.cap) {   // a round chrome filler cap (the muscle car's)
      sideDecal(k, fu.side, el(x, y, r - .009), 'satin', 0);
      sideDecal(k, fu.side, el(x, y, r - .03), 'chrome', 1);
    }
  }
  if (d.repeater) {
    const x = W.xF + W.rF + .14, y = Math.min(2 * W.rF + .1, cab.baseY(x) - .16);
    k.S(rr(x, y, .05, .017, .007), 'amberLens', 0);
  }
  if (d.markers) {   // US side markers: amber at the front corners, red at the back
    const xf = Math.max(.14, (W.xF - W.rF) * .5), xr = L - Math.max(.14, (L - W.xR - W.rR) * .5);
    k.S(rr(xf, W.rF + .14, .07, .024, .008), 'amberLens', 0);
    k.S(rr(xr, W.rR + .2, .07, .024, .008), 'tl', 0);
  }
  if (d.van) {   // the van's back: a handle on the right-hand door, hinges, red reflectors in the bumper, and the sliding door's track
    k.R(rr(-.075, 1.02, .13, .03, .01), 'trim', 0, false);
    k.R(rr(.9, .74, .035, .1, .01), 'trim', 0, true);
    k.R(rr(.66, .4, .12, .03, .008), 'tl', 0, true);
    sideDecal(k, -1, rr(4.15, 1.0, 1.0, .026, .01), 'trim', 0);
  }
}

// a chrome bezel round every headlamp projector and bulb (unless the design has drawn one there already)
function withBezels(k) {
  const F0 = k.F, chromed = [];
  k.F = (shape, mat, layer = 0, mirror = true, tilt = null) => {
    if (mat === 'hlChrome') { const g = grown(shape, 0); chromed.push(g); }
    if (mat === 'proj' || mat === 'warm') {
      const g0 = grown(shape, 0);
      const has = chromed.some(g => Math.abs(g0.cu - g.cu) < g.hu && Math.abs(g0.cv - g.cv) < g.hv);
      if (!has) F0(grown(shape, Math.min(.01, Math.max(.0035, .34 * Math.min(g0.hu, g0.hv)))).shape, 'chrome', layer - .5, mirror, tilt);
    }
    F0(shape, mat, layer, mirror, tilt);
  };
  return () => { k.F = F0; };
}

for (const S of CARS) {
  const d = DET[S.id];
  if (!d) continue;
  S.mats = Object.assign({}, S.mats || {}, DET_MATS);
  if (d.van) S.seams = (S.seams || []).concat([seamZ(.004, S.body.L - .14, S.body.L + .05, .5)]);   // the split between the back doors
  const own = S.extras;
  S.extras = function (k, api) {
    const done = withBezels(k);
    if (own) own.call(this, k, api);
    done();
    details(S, k, d);
  };
}
}
