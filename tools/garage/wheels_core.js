// Runs after the garage designer's code (see export_wheels.js): builds every wheel design of the workshop with the
// designer's own wheel (buildWheel: lip and barrel, the dark back, brake disc, face, hub cap and wheel nuts), at one size
// (an 18-inch rim in a 0.33 m tyre, 0.235 m wide), and writes each as two CPE2 meshes for the game:
//   OUT_DIR/<id>.mesh       what turns with the wheel, with no tyre (the game makes the tyre for each car's own size)
//   OUT_DIR/<id>_cal.mesh   the brake calliper, which does not turn
//   OUT_DIR/wheels.json     the size they were built at, and the designs' names
// Surfaces are named by what the game paints them with: "rim" (the wheel's colour), "barrel", "void", "disc", "chrome".
// The wheel's axis is x, its face towards -x (the outside of a left wheel; the game mirrors it for the right side).
'use strict';
{
const fs = globalThis.__fs, path = globalThis.__path;
const OUT = globalThis.__args[0] || 'wheels_out';
const R0 = .33, RIM0 = .2286, TW0 = .235;

// the designs: the designer's own styles (spoke, classic, split, disc, steel, holes) and four more drawn below
// (mesh: spokes laced both ways; y: stems that fork; vent: a disc with two rings of holes)
const DESIGNS = [
  ['steel', 'Steel', {style: 'steel', n: 6, conc: .02, hole: .026, holeR: .6}],
  ['5spoke', '5-spoke', {style: 'spoke', n: 5, w0: .045, w1: .05, conc: .035}],
  ['multi', 'Multi-spoke', {style: 'spoke', n: 10, w0: .02, w1: .026, conc: .035}],
  ['mesh', 'Mesh', {style: 'mesh', n: 10, tw: .32, w0: .016, w1: .019, conc: .03}],
  ['turbine', 'Turbine', {style: 'spoke', n: 14, w0: .012, w1: .02, twist: .5, conc: .045}],
  ['double', 'Double-spoke', {style: 'split', n: 5, w0: .022, w1: .026, sepH: .022, sepR: .024, conc: .04}],
  ['split', 'Split-spoke', {style: 'split', n: 5, w0: .026, w1: .03, sepH: .035, sepR: .13, conc: .04}],
  ['blade', 'Blade', {style: 'spoke', n: 7, w0: .026, w1: .075, twist: .75, conc: .03}],
  ['aero', 'Aero', {style: 'disc', n: 10, w0: .016, w1: .026, twist: .6, conc: .02}],
  ['wire', 'Wire', {style: 'mesh', n: 16, tw: .55, w0: .007, w1: .008, conc: .025, cap: 'chrome'}],
  ['tri', 'Tri-spoke', {style: 'spoke', n: 3, w0: .1, w1: .17, conc: .03}],
  ['star', 'Star', {style: 'spoke', n: 8, w0: .026, w1: .07, conc: .035}],
  ['vent', 'Vented disc', {style: 'vent', conc: .02}],
  ['deep', 'Deep dish', {style: 'classic', n: 6, w0: .05, w1: .065, conc: .02, dish: .065}],
  ['y5', 'Y-spoke', {style: 'y', n: 5, conc: .04}],
  ['twist10', 'Twisted 10', {style: 'spoke', n: 10, w0: .018, w1: .024, twist: .32, conc: .04}],
  ['classic', 'Classic 5', {style: 'classic', n: 5, w0: .055, w1: .07, conc: .02, dish: .035}],
  ['pepper', 'Pepper-pot', {style: 'holes', n: 6, conc: .012, hole: .028, holeR: .6}],
  ['forged', 'Forged twin', {style: 'split', n: 6, w0: .024, w1: .03, sepH: .025, sepR: .09, twist: .28, conc: .05}],
  ['rally', 'Rally', {style: 'spoke', n: 6, w0: .05, w1: .055, conc: .006}],
  ['hubcap', 'Steel & cap', {style: 'steel', n: 8, conc: .03, hole: .022, holeR: .66, cap: 'chrome'}],
  ['mono12', 'Monoblock 12', {style: 'spoke', n: 12, w0: .012, w1: .016, conc: .05}],
  ['directional', 'Directional', {style: 'spoke', n: 5, w0: .03, w1: .06, twist: .5, conc: .04}],
  ['track7', 'Track 7', {style: 'spoke', n: 7, w0: .03, w1: .04, conc: .065}],
];

// the faces the designer does not draw
globalThis.__faceExtra = ({st, spoke, disc, face, zf, r0, r1, parts}) => {
  // a spoke from radius rA to rB (the designer's own always runs from the hub to the rim)
  const spokeR = (a0, twist, w0, w1, rA, rB, depth = .022, crown = .004) => {
    const n = 10, rows = [];
    for (let i = 0; i <= n; i++) {
      const f = i / n, r = lerp(rA, rB, f), a = a0 + twist * f, w = lerp(w0, w1, f), z = zf(r);
      const c = [Math.cos(a), Math.sin(a)], t = [-Math.sin(a), Math.cos(a)];
      rows.push({l: [c[0] * r - t[0] * w / 2, c[1] * r - t[1] * w / 2], m: [c[0] * r, c[1] * r], rt: [c[0] * r + t[0] * w / 2, c[1] * r + t[1] * w / 2], z});
    }
    grid(face, n + 1, 3, (i, j) => { const q = rows[i], p = j === 0 ? q.l : j === 1 ? q.m : q.rt; return [p[0], p[1], q.z + (j === 1 ? crown : 0)]; });
    for (const k of ['l', 'rt']) grid(face, n + 1, 2, (i, j) => { const q = rows[i]; return [q[k][0], q[k][1], q.z - (j ? depth : 0)]; });
  };
  if (st.style === 'mesh') {        // spokes laced both ways
    for (let k = 0; k < st.n; k++) { const a = k / st.n * Math.PI * 2; spoke(a, st.tw, st.w0, st.w1, .014, .002); spoke(a, -st.tw, st.w0, st.w1, .014, .002); }
  } else if (st.style === 'y') {    // a stem from the hub that forks halfway out
    const rm = lerp(r0, r1, .46);
    for (let k = 0; k < st.n; k++) {
      const a = k / st.n * Math.PI * 2;
      spokeR(a, 0, .052, .042, r0 - .005, rm + .012);
      spokeR(a - .03, -.26, .03, .026, rm, r1);
      spokeR(a + .03, .26, .03, .026, rm, r1);
    }
  } else if (st.style === 'vent') { // a dished disc with two rings of holes
    const pr = [];
    for (let k = 0; k <= 10; k++) { const r = lerp(r0 - .01, r1 + .004, k / 10); pr.push([r, zf(r)]); }
    disc(pr);
    const hp = new Part('void');
    for (const [cnt, at, hs, off] of [[12, .74, .02, 0], [6, .4, .017, .26]]) for (let k = 0; k < cnt; k++) {
      const a = k / cnt * Math.PI * 2 + off, r = lerp(r0, r1, at);
      const hl = lathe('void', [[0, 0], [hs, 0]], 20);
      hl.xf(M3.I(), [Math.cos(a) * r, Math.sin(a) * r, zf(r) + .0015]);
      hp.append(hl);
    }
    parts.push(hp);
  }
};

// ---- a CPE2 file: magic, surface count, then per surface its name, vertices (positions, then normals) and indices
function writeCPE2(file, groups) {
  const blobs = [];
  for (const [name, g] of Object.entries(groups)) {
    if (!g.I.length) continue;
    const nb = Buffer.from(name, 'utf8'), n = g.P.length / 3;
    const head = Buffer.alloc(4); head.writeUInt32LE(nb.length);
    const cnt = Buffer.alloc(4); cnt.writeUInt32LE(n);
    const icnt = Buffer.alloc(4); icnt.writeUInt32LE(g.I.length);
    blobs.push(head, nb, cnt, Buffer.from(Float32Array.from(g.P).buffer), Buffer.from(Float32Array.from(g.N).buffer), icnt, Buffer.from(Uint32Array.from(g.I).buffer));
  }
  const top = Buffer.alloc(8); top.write('CPE2', 0, 'ascii'); top.writeUInt32LE(Object.values(groups).filter(g => g.I.length).length, 4);
  fs.writeFileSync(file, Buffer.concat([top, ...blobs]));
}
function add(groups, name, part) {
  const g = groups[name] || (groups[name] = {P: [], N: [], I: [], ids: new Map()});
  const idx = [];
  for (let i = 0; i < part.P.length / 3; i++) {
    // the designer's wheel is built round z with its face towards +z: the game's runs round x, its face towards -x
    const x = part.P[i * 3], y = part.P[i * 3 + 1], z = part.P[i * 3 + 2];
    const nx = part.N[i * 3], ny = part.N[i * 3 + 1], nz = part.N[i * 3 + 2], l = Math.hypot(nx, ny, nz) || 1;
    const p = [-z, y, x], q = [-nz / l, ny / l, nx / l];
    const k = p.map(v => Math.round(v * 1e5)).join(',') + '|' + q.map(v => Math.round(v * 1e4)).join(',');
    let j = g.ids.get(k);
    if (j === undefined) { j = g.P.length / 3; g.P.push(...p); g.N.push(...q); g.ids.set(k, j); }
    idx.push(j);
  }
  for (let i = 0; i < part.I.length; i += 3) {
    const a = idx[part.I[i]], b = idx[part.I[i + 1]], c = idx[part.I[i + 2]];
    if (a !== b && b !== c && a !== c) g.I.push(a, b, c);
  }
}
const SURFACE = {rim: 'rim', rimInner: 'barrel', void: 'void', disc: 'disc', chrome: 'chrome'};

fs.mkdirSync(OUT, {recursive: true});
const manifest = {size: {r: R0, rim: RIM0, width: TW0}, designs: []};
for (const [id, name, spec] of DESIGNS) {
  const S = {wheels: {rF: R0, rR: R0, rimF: RIM0, rimR: RIM0, twF: TW0, twR: TW0, zF: .8, zR: .8, xF: 1, xR: 3.5, rimStyle: spec}};
  const turn = {}, cal = {};
  let tris = 0;
  for (const p of buildWheel(S, true)) {
    if (p.mat === 'tire') continue;            // (the game makes the tyre for each car)
    if (p.mat === 'caliper') { add(cal, 'caliper', p); continue; }
    add(turn, SURFACE[p.mat] || 'rim', p);     // (the hub cap is in the rim's own material unless it is chrome)
  }
  for (const g of Object.values(turn)) tris += g.I.length / 3;
  writeCPE2(path.join(OUT, id + '.mesh'), turn);
  writeCPE2(path.join(OUT, id + '_cal.mesh'), cal);
  manifest.designs.push({id, name});
  console.log(`${id.padEnd(12)} ${name.padEnd(14)} ${tris} triangles: ${Object.entries(turn).map(([k, g]) => k + ' ' + g.I.length / 3).join(', ')}`);
}
fs.writeFileSync(path.join(OUT, 'wheels.json'), JSON.stringify(manifest, null, 1));
}
