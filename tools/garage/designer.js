// Loads the garage designer's modelling code (tools/garage/garage_concepts.html, plus the cars of more_cars.js) to run
// headlessly in Node, with a few small tags patched in, and runs an exporter after it in the same script (so the
// exporter sees CARS, buildCar, buildWheel and every other helper of the page). Used by export.js (the cars) and
// export_wheels.js (the wheel designs).
//
// The designer's own modelling code runs unchanged, with four small tags patched in (which parts are wheels, which are
// the steering wheel, which are the interior, and flat decals turned to face the way they were projected from), a hook
// for more wheel faces, and (unless GARAGE_FULL=1) a lighter sampling than the page draws, for a phone.
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

// A decal is a fan of rings round its middle, projected onto the body along one direction, and lifted off it along that
// direction by its layer's height. Two things tear it where it wraps round a corner (a lamp over the corner of a nose onto
// the bonnet or the side): there the projection meets the body at a slant, so its triangles stretch and, flat, cut under
// the curve they lie on; and a lift along the projection is no lift at all off a panel that runs along it. So:
//  - __refineDecal splits every edge whose middle, projected onto the body as the corners were, lies off the straight
//    edge by more than SAG (and every edge longer than MAXL), a few rounds over: only where the decal bends, and by edge,
//    so that neighbouring triangles stay joined without cracks;
//  - __snapDecals (once the car is built) moves every decal point onto the nearest point of the body's own triangles (the
//    mesh the game draws), lifts it off them along their normal by its layer's height, gives it that normal (so that it
//    is lit as the panel under it is), and turns any triangle folded over at a silhouette to face out as the others do.
const REFINE = `function __convex(sh){const n=sh.length;if(n<3)return false;let pos=0,neg=0;
  for(let i=0;i<n;i++){const a=sh[i],b=sh[(i+1)%n],c=sh[(i+2)%n],cr=(b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]);if(cr>1e-9)pos++;else if(cr<-1e-9)neg++;}
  return pos===0||neg===0;}
function __zipper(p,sh){const n=sh.length;let u0=1e9,u1=-1e9,v0=1e9,v1=-1e9;for(const [u,v] of sh){u0=Math.min(u0,u);u1=Math.max(u1,u);v0=Math.min(v0,v);v1=Math.max(v1,v);}
  const ax=(u1-u0)>=(v1-v0)?0:1;let i0=0,i1=0;for(let i=0;i<n;i++){if(sh[i][ax]<sh[i0][ax])i0=i;if(sh[i][ax]>sh[i1][ax])i1=i;}
  const A=[],B=[];for(let i=i0;;i=(i+1)%n){A.push(i);if(i===i1)break;}for(let i=i0;;i=(i-1+n)%n){B.push(i);if(i===i1)break;}
  let a=0,b=0;while(a<A.length-1||b<B.length-1){
    if(b>=B.length-1||(a<A.length-1&&sh[A[a+1]][ax]<=sh[B[b+1]][ax])){p.t(A[a],A[a+1],B[b]);a++;}else{p.t(A[a],B[b+1],B[b]);b++;}}}
function __refineDecal(p,api,frame,off){
  const SAG=.0016,MAXL=.1,d=frame.d,P=p.P,T=p.T;
  const len=(a,b)=>Math.hypot(P[a*3]-P[b*3],P[a*3+1]-P[b*3+1],P[a*3+2]-P[b*3+2]);
  const key=(a,b)=>a<b?a*1048576+b:b*1048576+a;
  for(let round=0;round<5&&p.count<12000;round++){
    const mid=new Map(),I=p.I;let any=false;
    for(let i=0;i<I.length;i+=3)for(let e=0;e<3;e++){const a=I[i+e],b=I[i+(e+1)%3],k=key(a,b);if(mid.has(k))continue;
      const L=len(a,b);if(L<.004){mid.set(k,-1);continue;}
      const u=(T[a*2]+T[b*2])/2,w=(T[a*2+1]+T[b*2+1])/2,o=frame.o(u,w);
      const ta=(P[a*3]-o[0])*d[0]+(P[a*3+1]-o[1])*d[1]+(P[a*3+2]-o[2])*d[2],tb=(P[b*3]-o[0])*d[0]+(P[b*3+1]-o[1])*d[1]+(P[b*3+2]-o[2])*d[2];
      const h=api.ray(o,d,frame.maxT,Math.min(ta,tb)-.03);
      if(!h){mid.set(k,-1);continue;}
      const q=[h[0]-d[0]*off,h[1]-d[1]*off,h[2]-d[2]*off],m=[(P[a*3]+P[b*3])/2,(P[a*3+1]+P[b*3+1])/2,(P[a*3+2]+P[b*3+2])/2];
      if(L<=MAXL&&Math.hypot(q[0]-m[0],q[1]-m[1],q[2]-m[2])<=SAG){mid.set(k,-1);continue;}
      mid.set(k,p.v(q[0],q[1],q[2],u,w));any=true;}
    // (a triangle whose edges lie on the body may still cut under it in its middle, where the body bulges both ways: then
    // its longest edge is split too)
    for(let i=0;i<I.length;i+=3){const v=[I[i],I[i+1],I[i+2]];if(v.some((_,e)=>mid.get(key(v[e],v[(e+1)%3]))>=0))continue;
      const u=(T[v[0]*2]+T[v[1]*2]+T[v[2]*2])/3,w=(T[v[0]*2+1]+T[v[1]*2+1]+T[v[2]*2+1])/3,o=frame.o(u,w);
      const tt=Math.min(...v.map(j=>(P[j*3]-o[0])*d[0]+(P[j*3+1]-o[1])*d[1]+(P[j*3+2]-o[2])*d[2]));
      const h=api.ray(o,d,frame.maxT,tt-.03);if(!h)continue;
      const q=[h[0]-d[0]*off,h[1]-d[1]*off,h[2]-d[2]*off],m=[0,1,2].map(a=>(P[v[0]*3+a]+P[v[1]*3+a]+P[v[2]*3+a])/3);
      if(Math.hypot(q[0]-m[0],q[1]-m[1],q[2]-m[2])<=SAG)continue;
      let e=0,bl=-1;for(let f=0;f<3;f++){const L=len(v[f],v[(f+1)%3]);if(L>bl){bl=L;e=f;}}
      const a0=v[e],b0=v[(e+1)%3],k=key(a0,b0),uu=(T[a0*2]+T[b0*2])/2,ww=(T[a0*2+1]+T[b0*2+1])/2,oo=frame.o(uu,ww);
      const ta=(P[a0*3]-oo[0])*d[0]+(P[a0*3+1]-oo[1])*d[1]+(P[a0*3+2]-oo[2])*d[2],tb=(P[b0*3]-oo[0])*d[0]+(P[b0*3+1]-oo[1])*d[1]+(P[b0*3+2]-oo[2])*d[2];
      const hh=api.ray(oo,d,frame.maxT,Math.min(ta,tb)-.03);
      mid.set(k,hh?p.v(hh[0]-d[0]*off,hh[1]-d[1]*off,hh[2]-d[2]*off,uu,ww):p.v((P[a0*3]+P[b0*3])/2,(P[a0*3+1]+P[b0*3+1])/2,(P[a0*3+2]+P[b0*3+2])/2,uu,ww));any=true;}
    if(!any)break;
    const NI=[];
    for(let i=0;i<I.length;i+=3){const v=[I[i],I[i+1],I[i+2]],m=[0,1,2].map(e=>mid.get(key(v[e],v[(e+1)%3])));const c=m.filter(x=>x>=0).length;
      if(c===0)NI.push(v[0],v[1],v[2]);
      else if(c===3)NI.push(v[0],m[0],m[2],m[0],v[1],m[1],m[2],m[1],v[2],m[0],m[1],m[2]);
      else if(c===1){const e=m.findIndex(x=>x>=0),a=v[e],b=v[(e+1)%3],cc=v[(e+2)%3];NI.push(a,m[e],cc,m[e],b,cc);}
      else{const e=m.findIndex(x=>x<0),a=v[e],b=v[(e+1)%3],cc=v[(e+2)%3],mbc=m[(e+1)%3],mca=m[(e+2)%3];
        NI.push(mbc,cc,mca);
        if(len(a,mbc)<len(b,mca))NI.push(a,b,mbc,a,mbc,mca);else NI.push(a,b,mca,b,mbc,mca);}}
    p.I=NI;}
  for(let q=p.N.length;q<p.P.length;q++)p.N.push(0);
  for(let q=p.M.length;q<p.P.length;q++)p.M.push(-1);
  return p.normals();}
function __snapDecals(parts,body,cabin){
  // a part's triangles in 3 cm cells, for the nearest point on them and for rays
  function mesh(m){const P=m.P,N=m.N,I=m.I,C=.03,cells=new Map(),key=(i,j,k)=>((i+512)*1024+(j+512))*1024+(k+512);
    for(let t=0;t<I.length;t+=3){const mn=[1e9,1e9,1e9],mx=[-1e9,-1e9,-1e9];
      for(let e=0;e<3;e++)for(let a=0;a<3;a++){const v=P[I[t+e]*3+a];if(v<mn[a])mn[a]=v;if(v>mx[a])mx[a]=v;}
      for(let i=Math.floor(mn[0]/C);i<=Math.floor(mx[0]/C);i++)for(let j=Math.floor(mn[1]/C);j<=Math.floor(mx[1]/C);j++)for(let k=Math.floor(mn[2]/C);k<=Math.floor(mx[2]/C);k++){
        const kk=key(i,j,k);let l=cells.get(kk);if(!l)cells.set(kk,l=[]);l.push(t);}}
    const at=i=>[P[i*3],P[i*3+1],P[i*3+2]];
    const near=(v,r)=>{const out=new Set(),ci=Math.floor(v[0]/C),cj=Math.floor(v[1]/C),ck=Math.floor(v[2]/C);
      for(let i=ci-r;i<=ci+r;i++)for(let j=cj-r;j<=cj+r;j++)for(let k=ck-r;k<=ck+r;k++){const l=cells.get(key(i,j,k));if(l)for(const t of l)out.add(t);}return out;};
    const normal=(t,w)=>{const n=[0,1,2].map(a=>N[I[t]*3+a]*w[0]+N[I[t+1]*3+a]*w[1]+N[I[t+2]*3+a]*w[2]),l=Math.hypot(n[0],n[1],n[2]);return l<1e-6?null:n.map(x=>x/l);};
    return {
      // the nearest point within 2.5 cm: {q, n} (its normal smoothed as the mesh's own)
      nearest(v){let best=null,bd=.025*.025;
        for(const t of near(v,1)){const A=at(I[t]),B=at(I[t+1]),Cc=at(I[t+2]),w=closest(v,A,B,Cc);
          const q=[A[0]*w[0]+B[0]*w[1]+Cc[0]*w[2],A[1]*w[0]+B[1]*w[1]+Cc[1]*w[2],A[2]*w[0]+B[2]*w[1]+Cc[2]*w[2]],dd=(q[0]-v[0])**2+(q[1]-v[1])**2+(q[2]-v[2])**2;
          if(dd<bd){bd=dd;best={q,t,w};}}
        if(!best)return null;const n=normal(best.t,best.w);return n?{q:best.q,n}:null;},
      // the first point a ray from o along d meets within maxT (<= 6 cm): {q, n}
      ray(o,d,maxT){let best=null;
        for(const t of near(o,2)){const A=at(I[t]),B=at(I[t+1]),Cc=at(I[t+2]);
          const e1=vsub(B,A),e2=vsub(Cc,A),pv=vcross(d,e2),det=vdot(e1,pv);if(Math.abs(det)<1e-14)continue;
          const inv=1/det,tv=vsub(o,A),u=vdot(tv,pv)*inv;if(u<0||u>1)continue;const qv=vcross(tv,e1),w=vdot(d,qv)*inv;if(w<0||u+w>1)continue;
          const tt=vdot(e2,qv)*inv;if(tt>0&&tt<maxT&&(!best||tt<best.tt))best={tt,w:[1-u-w,u,w],t};}
        if(!best)return null;const n=normal(best.t,best.w);return n?{q:[o[0]+d[0]*best.tt,o[1]+d[1]*best.tt,o[2]+d[2]*best.tt],n}:null;}};}
  // the nearest point of a triangle to p, with its barycentric weights (Ericson, Real-Time Collision Detection 5.1.5)
  function closest(p,a,b,c){const ab=vsub(b,a),ac=vsub(c,a),ap=vsub(p,a),d1=vdot(ab,ap),d2=vdot(ac,ap);if(d1<=0&&d2<=0)return [1,0,0];
    const bp=vsub(p,b),d3=vdot(ab,bp),d4=vdot(ac,bp);if(d3>=0&&d4<=d3)return [0,1,0];
    const vc=d1*d4-d3*d2;if(vc<=0&&d1>=0&&d3<=0){const v=d1/(d1-d3);return [1-v,v,0];}
    const cp=vsub(p,c),d5=vdot(ab,cp),d6=vdot(ac,cp);if(d6>=0&&d5<=d6)return [0,0,1];
    const vb=d5*d2-d1*d6;if(vb<=0&&d2>=0&&d6<=0){const w=d2/(d2-d6);return [1-w,0,w];}
    const va=d3*d6-d5*d4;if(va<=0&&(d4-d3)>=0&&(d5-d6)>=0){const w=(d4-d3)/((d4-d3)+(d5-d6));return [0,1-w,w];}
    const den=1/(va+vb+vc),v=vb*den,w=vc*den;return [1-v-w,v,w];}
  const B=mesh(body),G=cabin?mesh(cabin):null;
  for(const p of parts){if(!p||!p.decal)continue;
    const off=.0026+p.layer*.0026,nv=p.count,nrm=[];
    for(let i=0;i<nv;i++){const v=[p.P[i*3],p.P[i*3+1],p.P[i*3+2]];
      let h=B.nearest(v);
      if(!h){nrm.push(null);continue;}
      // (where the greenhouse stands out over the body, as round the back of a van, the decal goes on the greenhouse)
      if(G){const g=G.ray([h.q[0]+h.n[0]*1e-4,h.q[1]+h.n[1]*1e-4,h.q[2]+h.n[2]*1e-4],h.n,.06);if(g)h={q:g.q,n:vdot(g.n,h.n)<0?g.n.map(x=>-x):g.n};}
      p.P[i*3]=h.q[0]+h.n[0]*off;p.P[i*3+1]=h.q[1]+h.n[1]*off;p.P[i*3+2]=h.q[2]+h.n[2]*off;nrm.push(h.n);}
    // every triangle facing out (as the panels under it do), and every point lit as the panel under it
    const Ip=p.I;
    for(let i=0;i<Ip.length;i+=3){const a=Ip[i],b=Ip[i+1],c=Ip[i+2];let s=[0,0,0];for(const q of [a,b,c])if(nrm[q])s=vadd(s,nrm[q]);
      if(!s[0]&&!s[1]&&!s[2])continue;
      const f=vcross(vsub([p.P[b*3],p.P[b*3+1],p.P[b*3+2]],[p.P[a*3],p.P[a*3+1],p.P[a*3+2]]),vsub([p.P[c*3],p.P[c*3+1],p.P[c*3+2]],[p.P[a*3],p.P[a*3+1],p.P[a*3+2]]));
      if(vdot(f,s)<0){Ip[i+1]=c;Ip[i+2]=b;}}
    p.normals();
    for(let i=0;i<nv;i++)if(nrm[i]){p.N[i*3]=nrm[i][0];p.N[i*3+1]=nrm[i][1];p.N[i*3+2]=nrm[i][2];}}}`;

function run(coreFile, args) {
  const html = fs.readFileSync(path.join(__dirname, 'garage_concepts.html'), 'utf8');
  let code = html.slice(html.indexOf("'use strict';"), html.indexOf('// ---------- app / UI ----------'));
  function patch(a, b) {
    if (!code.includes(a)) throw new Error('patch target not found: ' + a.slice(0, 80));
    code = code.replace(a, b);
  }
  // parts remember what they are when they are copied (mirrored interior halves, wheels set on each corner)
  patch('clone(){const p=new Part(this.mat);', 'clone(){const p=new Part(this.mat);p.wheel=this.wheel;p.steer=this.steer;p.interior=this.interior;');
  // a decal faces the way it was projected from (the designer draws both sides; the game draws front faces, and lights by the normal)
  // and its triangles are made smaller wherever they stretch over a curve (see __refineDecal)
  patch('for(let k=1;k<K;k++){const a=1+(k-1)*N,b=1+k*N;for(let j=0;j<N;j++){const j2=(j+1)%N;p.q(a+j,a+j2,b+j2,b+j);}}\n  return p.normals();',
    'for(let k=1;k<K;k++){const a=1+(k-1)*N,b=1+k*N;for(let j=0;j<N;j++){const j2=(j+1)%N;p.q(a+j,a+j2,b+j2,b+j);}}\n  p.normals();{let s=0;for(let i=0;i<p.N.length;i+=3)s-=p.N[i]*frame.d[0]+p.N[i+1]*frame.d[1]+p.N[i+2]*frame.d[2];if(s<0)p.flip();}return __refineDecal(p,api,frame,off);');
  // a small decal needs fewer rings round its middle than the page's six (__refineDecal adds points wherever it bends)
  patch('const N=shape.length,K=6;let cu=0,cv=0;for(const s of shape){cu+=s[0];cv+=s[1];}cu/=N;cv/=N;',
    'const N=shape.length;let cu=0,cv=0;for(const s of shape){cu+=s[0];cv+=s[1];}cu/=N;cv/=N;let __r=0;for(const s of shape)__r=Math.max(__r,Math.hypot(s[0]-cu,s[1]-cv));const K=Math.max(2,Math.min(6,Math.ceil(__r/.025)));');
  // a convex decal that lies wholly on the body is laid as a strip between the two halves of its outline (a few triangles where
  // the page fans it out from its middle in rings: a light bar 1.5 m long and 1 cm high is a few hundred triangles instead of
  // thousands); a concave one, or one that wraps over the edge of the body, keeps the page's fan
  patch('const pts=[[cu,cv]];for(let k=1;k<=K;k++)for(const s of shape)pts.push([cu+(s[0]-cu)*k/K,cv+(s[1]-cv)*k/K]);',
    'const __strip=__convex(shape)&&shape.every(([u,v])=>api.ray(frame.o(u,v),frame.d,frame.maxT)),pts=__strip?shape.slice():[[cu,cv]];if(!__strip)for(let k=1;k<=K;k++)for(const s of shape)pts.push([cu+(s[0]-cu)*k/K,cv+(s[1]-cv)*k/K]);');
  patch('for(let j=0;j<N;j++)p.t(0,1+j,1+(j+1)%N);\n  for(let k=1;k<K;k++){', 'if(__strip)__zipper(p,shape);else for(let j=0;j<N;j++)p.t(0,1+j,1+(j+1)%N);\n  if(!__strip)for(let k=1;k<K;k++){');
  // a decal remembers the way it was projected and its layer (the exporter keeps it clear of the body's own triangles)
  patch('const p=new Part(mat),off=.0022+layer*.0026;', 'const p=new Part(mat),off=.0022+layer*.0026;p.decal=frame.d;p.layer=layer;');
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
  // the cars of this project that the designer page does not have, and the details of real cars that every car is given
  // (details.js), before the interiors are given out
  const marker = 'for(const c of CARS){const I=INTERIORS[c.id];';
  patch(marker, fs.readFileSync(path.join(__dirname, 'more_cars.js'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, 'details.js'), 'utf8') + '\n' + marker);


  // once the car's parts are all there, the decals laid onto the body's own triangles (see __snapDecals)
  patch('  if(S.extras)S.extras(kit,api);', '  if(S.extras)S.extras(kit,api);\n  __snapDecals(parts,body,cab.cabin);');
  // more wheel faces (export_wheels.js): a hook just before the face is finished, with what the face is built from
  patch('  face.normals();parts.push(face);', '  if(globalThis.__faceExtra)globalThis.__faceExtra({st,spoke,disc,face,zf,r0,r1,rim,fz,h,dish,conc,parts});\n  face.normals();parts.push(face);');
  code += '\n' + REFINE;
  globalThis.__fs = fs;
  globalThis.__path = path;
  globalThis.__args = args;
  vm.runInThisContext(code + '\n' + fs.readFileSync(path.isAbsolute(coreFile) ? coreFile : path.join(__dirname, coreFile), 'utf8'), { filename: 'garage.js' });
}

module.exports = { run };
