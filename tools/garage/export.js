#!/usr/bin/env node
// Exports the cars of the garage designer (tools/garage/garage_concepts.html, the "Redline Rush — Garage Concepts" page, plus
// the cars of more_cars.js) as GLB files in the layout tools/convert_garage.py reads ("Redline Rush garage exporter").
//
//   node tools/garage/export.js OUT_DIR [car ids...]      (no ids: every car; GARAGE_FULL=1: the designer's full sampling)
//
// The designer's own modelling code runs here unchanged, with four small tags patched in (which parts are wheels, which
// are the steering wheel, which are the interior, and flat decals turned to face the way they were projected from); then
// export_core.js turns what the designer draws with its shader (masks, arch cut-outs, the open tub under the glass, panel
// lines) into geometry, and writes the file.
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, 'garage_concepts.html'), 'utf8');
let code = html.slice(html.indexOf("'use strict';"), html.indexOf('// ---------- app / UI ----------'));
function patch(a, b) {
  if (!code.includes(a)) throw new Error('patch target not found: ' + a.slice(0, 80));
  code = code.replace(a, b);
}
// parts remember what they are when they are copied (mirrored interior halves, wheels set on each corner)
patch('clone(){const p=new Part(this.mat);', 'clone(){const p=new Part(this.mat);p.wheel=this.wheel;p.steer=this.steer;p.interior=this.interior;');
// a decal faces the way it was projected from (the designer draws both sides; the game draws front faces, and lights by the normal)
patch('for(let k=1;k<K;k++){const a=1+(k-1)*N,b=1+k*N;for(let j=0;j<N;j++){const j2=(j+1)%N;p.q(a+j,a+j2,b+j2,b+j);}}\n  return p.normals();',
  'for(let k=1;k<K;k++){const a=1+(k-1)*N,b=1+k*N;for(let j=0;j<N;j++){const j2=(j+1)%N;p.q(a+j,a+j2,b+j2,b+j);}}\n  p.normals();{let s=0;for(let i=0;i<p.N.length;i+=3)s-=p.N[i]*frame.d[0]+p.N[i+1]*frame.d[1]+p.N[i+2]*frame.d[2];if(s<0)p.flip();}return p;');
// the steering wheel (rim, spokes, hub, paddles, column) and where it sits
patch('  const toW=(a,b,c=0)=>vadd(wc,', '  const __sw0=parts.length;\n  const toW=(a,b,c=0)=>vadd(wc,');
patch('  // ---- seats ----', '  for(let q=__sw0;q<parts.length;q++)parts[q].steer=true;globalThis.__steerFrame={wc:wc.slice(),th};\n  // ---- seats ----');
// everything else the interior adds
patch('  // ---- keep every interior vertex inside the car', '  for(let k=firstPart;k<parts.length;k++)if(!parts[k].steer)parts[k].interior=true;\n  // ---- keep every interior vertex inside the car');
// a lighter mesh than the designer draws, for a phone (the shapes, masks and decals are the same; only the sampling is
// coarser): body stations every 4 cm instead of 2.8 (the extra ones at the ends, round intakes and dense ranges stay),
// 44 points round each half section instead of 54, greenhouse stations every 3 cm and 38 points round it instead of 46;
// tyres with 48 sides and only the rows their shape needs (the flat tread kept rows only for the drawn tread pattern), rims
// with 64 sides instead of 96
if (!process.env.GARAGE_FULL) {
  patch('x+=.028)xs.add', 'x+=.04)xs.add');
  patch('const HR=54,R=2*HR;', 'const HR=44,R=2*HR;');
  patch('for(let x=x0;x<=x1;x+=.022)xs.add(x);', 'for(let x=x0;x<=x1;x+=.03)xs.add(x);');
  patch('const NG=46,RC=2*NG+1', 'const NG=38,RC=2*NG+1');
  patch('for(let k=0;k<=8;k++){const f=k/8,r=lerp(rim+.004', 'for(let k=0;k<=5;k++){const f=k/5,r=lerp(rim+.004');
  patch('for(let k=1;k<=6;k++){const a=k/6*Math.PI/2;prof.push', 'for(let k=1;k<=4;k++){const a=k/4*Math.PI/2;prof.push');
  patch('for(let k=1;k<10;k++)prof.push([R,-zs+2*zs*k/10]);', 'for(let k=1;k<4;k++)prof.push([R,-zs+2*zs*k/4]);');
  patch('for(let k=0;k<=5;k++){const a=(1-k/6)*Math.PI/2;prof.push', 'for(let k=0;k<=3;k++){const a=(1-k/4)*Math.PI/2;prof.push');
  patch("parts.push(lathe('tire',prof,64));", "parts.push(lathe('tire',prof,48));");
  patch('[rim-.012-dish,fz-.008-dish*.6]],96));', '[rim-.012-dish,fz-.008-dish*.6]],64));');
  patch("function disc(prof){face.append(lathe('rim',prof,96));}", "function disc(prof){face.append(lathe('rim',prof,64));}");
}
// the cars of this project that the designer page does not have, before the interiors are given out
const marker = 'for(const c of CARS){const I=INTERIORS[c.id];';
patch(marker, fs.readFileSync(path.join(__dirname, 'more_cars.js'), 'utf8') + '\n' + marker);

globalThis.__fs = fs;
globalThis.__path = path;
globalThis.__args = process.argv.slice(2);
vm.runInThisContext(code + '\n' + fs.readFileSync(path.join(__dirname, 'export_core.js'), 'utf8'), { filename: 'garage.js' });
