// Runs in the same script as the garage designer's code (see export.js): builds each car with the designer's own buildCar and
// writes it as a GLB, with what the designer draws in its fragment shader turned into geometry:
//   - the body and the greenhouse split into paint, glass, trim and accent along the zero lines of their masks (each triangle
//     is cut where a mask changes sign, so the edges are clean however coarse the mesh)
//   - the wheel arches cut out of the body, the dark trim round them (archTrim) and the dark side intakes (dents with `dark`)
//   - the body opened under the greenhouse where the interior shows, with the dark shelf in front of and behind the opening
//   - the panel lines (seams) as thin dark strips laid on the paint
// The inside of the body and of the greenhouse (which the designer shades in the interior's colour, seen through the glass) is
// left to the game, which draws the back faces of the body's materials in that colour (the file says it: "extras.interior").
// Coordinates: the designer's x runs from the front bumper back, y up, z to the left; the file's are glTF's, the car facing
// -z with its middle at 0: (x, y, z) -> (-z, y, x - L/2).
'use strict';
{
const fs = globalThis.__fs, path = globalThis.__path;
const ARGS = globalThis.__args;
const OUT_DIR = ARGS[0] || 'garage_out';
const WANT = ARGS.slice(1);

// what kind of part each of the designer's materials is, for the game (the category part of a material's name)
const CAT = {paint: 'paint', glass: 'glass', glassDark: 'glass', trim: 'gloss', gloss: 'gloss', matte: 'dark', chrome: 'chrome', satin: 'chrome',
  rimInner: 'gloss', void: 'dark', chassis: 'under', liner: 'under', hl: 'gloss', hlChrome: 'chrome', drl: 'head', proj: 'head', warm: 'head',
  cyan: 'head', tl: 'dark', tlGlow: 'tail', tlDim: 'tail', amber: 'headlens', amberLens: 'dark', rev: 'dark', grille: 'grille', slats: 'grille',
  vent: 'grille', carbon: 'gloss', plate: 'plate', flashR: 'dark', flashB: 'dark', rubber: 'dark', shelf: 'dark', seam: 'dark'};
const HEAD = new Set(['drl', 'proj', 'warm', 'cyan']), TAIL = new Set(['tlGlow', 'tlDim']), IND = new Set(['amber']);
// patterns the designer draws in its shader (the game has no textures for them): how much each darkens the colour on average,
// and how much of a lit pattern (a gauge, a screen) glows
const PAT_K = {1: .48, 2: .63, 3: .95, 4: 1.05, 5: .585, 9: .85, 10: .8, 11: .92, 12: .85};
const PAT_E = {7: .3, 8: .15};

// ---------------------------------------------------------------- polygons with attributes
// a vertex: [x, y, z, nx, ny, nz, g, t, a, arch]
function lerpV(a, b, t) {
  const o = new Array(a.length);
  for (let i = 0; i < a.length; i++) o[i] = a[i] + (b[i] - a[i]) * t;
  return o;
}
// the polygon cut by the zero line of fn: [where fn > 0, where fn <= 0] (null for an empty side)
function split(poly, fn) {
  const n = poly.length, v = poly.map(fn), P = [], Q = [];
  for (let i = 0; i < n; i++) {
    const a = poly[i], b = poly[(i + 1) % n], va = v[i], vb = v[(i + 1) % n];
    if (va > 0) P.push(a); else Q.push(a);
    if ((va > 0) !== (vb > 0)) { const c = lerpV(a, b, va / (va - vb)); P.push(c); Q.push(c); }
  }
  return [P.length >= 3 ? P : null, Q.length >= 3 ? Q : null];
}

// ---------------------------------------------------------------- output
// triangles by node and material, their corners shared where position and normal are the same
class Out {
  constructor() { this.nodes = {}; }
  group(node, key) {
    const n = this.nodes[node] || (this.nodes[node] = {});
    return n[key] || (n[key] = {P: [], N: [], I: [], ids: new Map()});
  }
  corner(g, v) {
    const l = Math.hypot(v[3], v[4], v[5]) || 1, nx = v[3] / l, ny = v[4] / l, nz = v[5] / l;
    const k = Math.round(v[0] * 1e5) + ',' + Math.round(v[1] * 1e5) + ',' + Math.round(v[2] * 1e5) + ',' +
      Math.round(nx * 1e4) + ',' + Math.round(ny * 1e4) + ',' + Math.round(nz * 1e4);
    let i = g.ids.get(k);
    if (i === undefined) { i = g.P.length / 3; g.P.push(v[0], v[1], v[2]); g.N.push(nx, ny, nz); g.ids.set(k, i); }
    return i;
  }
  tri(node, key, a, b, c) {   // three vertices [x, y, z, nx, ny, nz, ...]
    const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    const cr = vcross(e1, e2);
    if (Math.hypot(cr[0], cr[1], cr[2]) < 1e-12) return;
    const g = this.group(node, key);
    const ia = this.corner(g, a), ib = this.corner(g, b), ic = this.corner(g, c);
    if (ia !== ib && ib !== ic && ia !== ic) g.I.push(ia, ib, ic);
  }
  poly(node, key, p) { for (let k = 1; k + 1 < p.length; k++) this.tri(node, key, p[0], p[k], p[k + 1]); }
}

// ---------------------------------------------------------------- one car
function exportCar(S0) {
  const S = Object.assign({}, S0, {body: Object.assign({}, S0.body), cabin: Object.assign({}, S0.cabin)});
  globalThis.__steerFrame = null;
  const built = buildCar(S);
  const api = built.api, L = api.L, cut = built.cut, cab = api.cab, W = S.wheels;
  const out = new Out();
  const In = S.interior || {};
  const trimK = S.trimMat || 'trim';
  const slotsB = ['paint', S.glassMat || 'glass', trimK, S.accentMat || 'trim'];
  const slotsC = ['paint', S.glassMat || 'glass', S.cabinTrimMat || trimK, S.cabinAccentMat || S.accentMat || 'chrome'];

  // ---- body: arches, dark trim, the open tub, masks
  const body = built.parts.find(p => p.mat === 'body'), cabinP = built.parts.find(p => p.mat === 'cabin');
  const darkDents = (api.B.dents || []).filter(d => d.dark && d.poly.length === 4).slice(0, 3);
  const archCut = (x, y, z) => { let c = -1; for (const a of api.arches) c = Math.max(c, Math.min(a.Ra - Math.hypot(x - a.x, y - a.cy), Math.abs(z) - a.zWell)); return c; };
  const vert = (p, i, extra) => {
    const x = p.P[i * 3], y = p.P[i * 3 + 1], z = p.P[i * 3 + 2];
    const v = [x, y, z, p.N[i * 3], p.N[i * 3 + 1], p.N[i * 3 + 2], p.M[i * 3], p.M[i * 3 + 1], p.M[i * 3 + 2], -1];
    if (extra) {
      const ac = archCut(x, y, z);
      let xtr = -1;
      if (S.archTrim > 0) xtr = S.archTrim + ac;
      if (Math.abs(z) > .3) for (const d of darkDents) {
        let sd = polySd(x, y, d.poly) - d.dark;
        if (d.ramp && d.ramp[1] > d.ramp[0]) sd = Math.min(sd, x - lerp(d.ramp[0], d.ramp[1], .3));
        xtr = Math.max(xtr, sd);
      }
      v[7] = Math.max(v[7], xtr);
      v[9] = ac;
    }
    return v;
  };
  const izAt = x => { const t = clamp((x - cut.x0) / (cut.x1 - cut.x0), 0, 1) * 7, i0 = Math.min(Math.floor(t), 6); return lerp(cut.zs[i0], cut.zs[i0 + 1], t - i0); };
  const paintPolys = [];
  // a piece's materials, by its masks: glass, else trim, else accent, else paint
  function byMasks(node, poly, slots, shelf) {
    const [gl, rest] = split(poly, v => v[6]);
    if (gl) out.poly('Glass', slots[1], gl);
    if (!rest) return;
    if (shelf) { out.poly('Body', 'shelf', rest); return; }
    const [tr, r2] = split(rest, v => v[7]);
    if (tr) out.poly(node, slots[2], tr);
    if (!r2) return;
    const [ac, pt] = split(r2, v => v[8]);
    if (ac) out.poly(node, slots[3], ac);
    if (pt) { out.poly(node, slots[0], pt); paintPolys.push(pt); }
  }
  {
    for (let i = 0; i < body.I.length; i += 3) {
      let polys = [[vert(body, body.I[i], true), vert(body, body.I[i + 1], true), vert(body, body.I[i + 2], true)]];
      // the arches: keep only what is outside them
      polys = polys.map(p => split(p, v => -v[9])[0]).filter(Boolean);
      for (const p of polys) {
        if (!cut) { byMasks('Body', p, slotsB, false); continue; }
        // (only the top of the tub, facing up, is opened: the designer's rule alone, above the cabin floor and inside the
        // cabin's width, would also take out the bottoms of the doors where the sides tuck in under the car)
        const [hi, lo] = split(p, v => Math.min(v[1] - cut.y, (v[4] - .2) * .5));
        if (lo) byMasks('Body', lo, slotsB, false);
        if (!hi) continue;
        const [inz, outz] = split(hi, v => izAt(v[0]) - Math.abs(v[2]));
        if (outz) byMasks('Body', outz, slotsB, false);
        if (!inz) continue;
        const [a1, b1] = split(inz, v => v[0] - cut.x0);   // in front of the opening: as before
        if (b1) byMasks('Body', b1, slotsB, false);
        if (!a1) continue;
        const [a2, b2] = split(a1, v => cut.x1 - v[0]);
        if (b2) byMasks('Body', b2, slotsB, false);
        if (!a2) continue;
        const [m1, s1] = split(a2, v => v[0] - cut.cx0);  // the shelf in front of the opening
        if (s1) byMasks('Body', s1, slotsB, true);
        if (!m1) continue;
        const [m2, s2] = split(m1, v => cut.cx1 - v[0]);  // ...and behind it; the opening itself is left open
        if (s2) byMasks('Body', s2, slotsB, true);
      }
    }
    for (let i = 0; i < cabinP.I.length; i += 3) byMasks('Body', [vert(cabinP, cabinP.I[i]), vert(cabinP, cabinP.I[i + 1]), vert(cabinP, cabinP.I[i + 2])], slotsC, false);
  }

  // ---- the panel lines: thin dark strips on the paint
  for (const s of (S.seams || [])) {
    const [nx, ny, nz, w] = s.p, b = s.b, zb = s.z;
    for (const poly of paintPolys) {
      const f = poly.map(v => nx * v[0] + ny * v[1] + nz * Math.abs(v[2]) - w);
      const pts = [];
      for (let k = 0; k < poly.length; k++) {
        const a = poly[k], c = poly[(k + 1) % poly.length], fa = f[k], fc = f[(k + 1) % poly.length];
        if ((fa > 0) !== (fc > 0)) pts.push(lerpV(a, c, fa / (fa - fc)));
      }
      if (pts.length !== 2) continue;
      const m = lerpV(pts[0], pts[1], .5), az = Math.abs(m[2]);
      if (m[0] < b[0] || m[0] > b[1] || m[1] < b[2] || m[1] > b[3] || az < zb[0] || az > zb[1]) continue;
      const d = vnorm(vsub(pts[1], pts[0]).slice(0, 3)), nrm = vnorm(vadd(pts[0].slice(3, 6), pts[1].slice(3, 6)));
      const side = vnorm(vcross(nrm, d)), hw = .0013, lift = .0008;
      const q = (p, sg) => [p[0] + side[0] * hw * sg + nrm[0] * lift, p[1] + side[1] * hw * sg + nrm[1] * lift, p[2] + side[2] * hw * sg + nrm[2] * lift, nrm[0], nrm[1], nrm[2]];
      const a0 = q(pts[0], -1), a1 = q(pts[0], 1), b0 = q(pts[1], -1), b1 = q(pts[1], 1);
      out.tri('Body', 'seam', a0, a1, b1);
      out.tri('Body', 'seam', a0, b1, b0);
    }
  }

  // ---- every other part: decals, trim, lamps, the wheel-well liners, the interior, the steering wheel
  for (const p of built.parts) {
    if (!p || !p.I.length || p === body || p === cabinP || p.wheel) continue;
    const node = p.steer ? 'SteeringWheel' : p.interior ? 'Interior' : HEAD.has(p.mat) ? 'Lights_Head' : TAIL.has(p.mat) ? 'Lights_Tail' : IND.has(p.mat) ? 'Lights_Indicator' : 'Body';
    for (let i = 0; i < p.I.length; i += 3) out.tri(node, p.mat, vert(p, p.I[i]), vert(p, p.I[i + 1]), vert(p, p.I[i + 2]));
  }

  // ---- the wheels and brake callipers, each about its own centre (the game turns them)
  const corners = {};
  for (const front of [true, false]) for (const sg of [1, -1]) {
    const nm = (front ? 'F' : 'R') + (sg > 0 ? 'L' : 'R');
    corners[nm] = [front ? W.xF : W.xR, front ? W.rF : W.rR, sg * (front ? W.zF : W.zR)];
    for (const q of __buildWheel(S, front)) {
      const c = q.clone();
      if (sg < 0) { c.xf(M3.sc(1, 1, -1)); for (let i = 0; i < c.I.length; i += 3) { const t = c.I[i + 1]; c.I[i + 1] = c.I[i + 2]; c.I[i + 2] = t; } }
      const node = (c.mat === 'caliper' ? 'Caliper_' : 'Wheel_') + nm;
      for (let i = 0; i < c.I.length; i += 3) out.tri(node, c.mat, vert(c, c.I[i]), vert(c, c.I[i + 1]), vert(c, c.I[i + 2]));
    }
  }
  return {S, out, L, corners, steer: globalThis.__steerFrame, eye: cut ? cut.eye : null};
}

// ---------------------------------------------------------------- the file
function writeGLB(file, car) {
  const {S, out, L, corners, steer} = car;
  const R = resolveMats(S);
  const tint = (S.interior && S.interior.tint != null) ? S.interior.tint : .5;
  const In = S.interior || {};
  const matIdx = {}, materials = [], used = new Set();
  function material(key) {
    if (matIdx[key] != null) return matIdx[key];
    let m;
    if (key === 'shell') m = mat({c: In.shell || '#1a1b1d', r: .8});
    else if (key === 'shelf') m = mat({c: In.shelf || '#0d0e10', r: .8});
    else if (key === 'seam') m = mat({c: '#050506', r: .7, cc: .1});
    else m = R.get(key);
    let alb = m.alb.slice();
    if (PAT_K[m.pat]) alb = alb.map(v => Math.min(1, v * PAT_K[m.pat]));
    let emi = m.flash ? flashE(m.flash, .5) : m.emi.slice();
    if (PAT_E[m.pat]) emi = emi.map(v => v * PAT_E[m.pat]);
    const cat = CAT[key] || (/^i[A-Z]/.test(key) || key === 'shell' ? 'part' : 'gloss');
    const glass = cat === 'glass';
    const o = {name: cat + ':' + key, doubleSided: true,
      pbrMetallicRoughness: {baseColorFactor: [alb[0], alb[1], alb[2], glass ? tint : 1], metallicFactor: m.prm[0], roughnessFactor: m.prm[1]}};
    if (glass) o.alphaMode = 'BLEND';
    const ext = {};
    if (m.prm[2] > 0) { ext.KHR_materials_clearcoat = {clearcoatFactor: m.prm[2], clearcoatRoughnessFactor: .03}; used.add('KHR_materials_clearcoat'); }
    const em = Math.max(emi[0], emi[1], emi[2]);
    if (em > 0) {
      if (em > 1) { o.emissiveFactor = emi.map(v => v / em); ext.KHR_materials_emissive_strength = {emissiveStrength: em}; used.add('KHR_materials_emissive_strength'); }
      else o.emissiveFactor = emi.slice();
    }
    if (Object.keys(ext).length) o.extensions = ext;
    matIdx[key] = materials.length;
    materials.push(o);
    return matIdx[key];
  }
  const toG = (x, y, z) => [-z, y, x - L / 2];
  const nodesOut = [{name: 'Car_' + S.id, children: []}], meshes = [], accessors = [], views = [], chunks = [];
  let offset = 0;
  function addView(arr, target) {
    const buf = Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength);
    views.push({buffer: 0, byteOffset: offset, byteLength: buf.length, target});
    chunks.push(buf);
    offset += buf.length;
    const pad = (4 - (offset % 4)) % 4;
    if (pad) { chunks.push(Buffer.alloc(pad)); offset += pad; }
    return views.length - 1;
  }
  const order = ['Body', 'Glass', 'Interior', 'SteeringWheel', 'Lights_Head', 'Lights_Tail', 'Lights_Indicator',
    'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR', 'Caliper_FL', 'Caliper_FR', 'Caliper_RL', 'Caliper_RR'];
  for (const name of order) {
    const groups = out.nodes[name];
    if (!groups) continue;
    let xf, node = {name};
    if (name.startsWith('Wheel_') || name.startsWith('Caliper_')) {
      const c = corners[name.slice(-2)];
      node.translation = toG(c[0], c[1], c[2]);
      xf = (x, y, z) => [-z, y, x];
    } else if (name === 'SteeringWheel' && steer) {
      const t = toG(steer.wc[0], steer.wc[1], steer.wc[2]), ph = -steer.th, cs = Math.cos(ph), sn = Math.sin(ph);
      node.translation = t;
      node.rotation = [Math.sin(ph / 2), 0, 0, Math.cos(ph / 2)];
      xf = (x, y, z) => { const g = toG(x, y, z), v = [g[0] - t[0], g[1] - t[1], g[2] - t[2]]; return [v[0], cs * v[1] + sn * v[2], -sn * v[1] + cs * v[2]]; };
    } else xf = toG;
    const nf = (name.startsWith('Wheel_') || name.startsWith('Caliper_')) ? xf
      : (name === 'SteeringWheel' && node.rotation) ? ((x, y, z) => { const g = [-z, y, x], ph = -steer.th, cs = Math.cos(ph), sn = Math.sin(ph); return [g[0], cs * g[1] + sn * g[2], -sn * g[1] + cs * g[2]]; })
      : ((x, y, z) => [-z, y, x]);
    const prims = [];
    for (const key of Object.keys(groups)) {
      const g = groups[key], n = g.P.length / 3;
      if (!g.I.length) continue;
      const P = new Float32Array(n * 3), N = new Float32Array(n * 3), I = Uint32Array.from(g.I);
      const mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
      for (let i = 0; i < n; i++) {
        const p = xf(g.P[i * 3], g.P[i * 3 + 1], g.P[i * 3 + 2]), q = nf(g.N[i * 3], g.N[i * 3 + 1], g.N[i * 3 + 2]);
        for (let k = 0; k < 3; k++) { P[i * 3 + k] = p[k]; N[i * 3 + k] = q[k]; mn[k] = Math.min(mn[k], p[k]); mx[k] = Math.max(mx[k], p[k]); }
      }
      const pa = accessors.push({bufferView: addView(P, 34962), componentType: 5126, count: n, type: 'VEC3', min: mn, max: mx}) - 1;
      const na = accessors.push({bufferView: addView(N, 34962), componentType: 5126, count: n, type: 'VEC3'}) - 1;
      const ia = accessors.push({bufferView: addView(I, 34963), componentType: 5125, count: I.length, type: 'SCALAR'}) - 1;
      prims.push({attributes: {POSITION: pa, NORMAL: na}, indices: ia, material: material(key)});
    }
    if (!prims.length) continue;
    node.mesh = meshes.push({name, primitives: prims}) - 1;
    nodesOut[0].children.push(nodesOut.push(node) - 1);
  }
  const bin = Buffer.concat(chunks);
  // the colours the designer gives the inside of the body and of the greenhouse (seen through the glass), and the shelf under
  // the windows: the game draws the back faces of the body in the first
  const json = {asset: {version: '2.0', generator: 'Redline Rush garage exporter'}, scene: 0, scenes: [{nodes: [0]}], nodes: nodesOut, meshes,
    materials, accessors, bufferViews: views, buffers: [{byteLength: bin.length}],
    extras: {interior: Object.assign({shell: In.shell || '#1a1b1d', shelf: In.shelf || '#0d0e10', tint}, car.eye ? {eye: toG(car.eye[0], car.eye[1], car.eye[2])} : {})}};
  if (used.size) json.extensionsUsed = [...used];
  let js = Buffer.from(JSON.stringify(json), 'utf8');
  if (js.length % 4) js = Buffer.concat([js, Buffer.alloc(4 - js.length % 4, 0x20)]);
  const head = Buffer.alloc(12), jh = Buffer.alloc(8), bh = Buffer.alloc(8);
  head.writeUInt32LE(0x46546C67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(12 + 8 + js.length + 8 + bin.length, 8);
  jh.writeUInt32LE(js.length, 0); jh.writeUInt32LE(0x4E4F534A, 4);
  bh.writeUInt32LE(bin.length, 0); bh.writeUInt32LE(0x004E4942, 4);
  fs.writeFileSync(file, Buffer.concat([head, jh, js, bh, bin]));
  let tris = 0;
  for (const m of meshes) for (const p of m.primitives) tris += accessors[p.indices].count / 3;
  return tris;
}

// the designer's wheel, before buildCar marks its parts as wheels
const __buildWheel = buildWheel;
buildWheel = function (S, front) { const ps = __buildWheel(S, front); for (const p of ps) p.wheel = true; return ps; };

fs.mkdirSync(OUT_DIR, {recursive: true});
const ids = WANT.length ? WANT : CARS.map(c => c.id);
for (const id of ids) {
  const S = CARS.find(c => c.id === id);
  if (!S) { console.log('no car', id); continue; }
  const t0 = Date.now();
  const car = exportCar(S);
  const file = path.join(OUT_DIR, id + '.glb');
  const tris = writeGLB(file, car);
  const nodes = Object.keys(car.out.nodes).map(n => n + ':' + Object.values(car.out.nodes[n]).reduce((s, g) => s + g.I.length / 3, 0)).join(' ');
  console.log(`${id}: ${tris} triangles, ${Date.now() - t0} ms -> ${file}\n   ${nodes}`);
}
}
