# Split the starter coupe GLB body into game surfaces, in CarModel space
# (x right, y up, z = -d, rear bumper at z = 0, nose towards -z).
import json,struct,sys
import numpy as np
from PIL import Image
# usage: python3 tools/convert_coupe.py MODEL.glb OUT.mesh [GLASS_MIN_Y] [lines] [gloss] [bodyside] [lq] [rearbody]
#   dark texture above GLASS_MIN_Y (default 0.84 m) is window glass, below it black trim
#   rearbody: the rear bumper (z = 0) is taken from the body alone, not from every part of the model (the Pulse, Vector,
#   Kestrel, Bruiser, Copperhead, Halcyon and Blue Static were made that way: it moves the whole car by a centimetre or so)
#   (the settings the shipped cars were made with: Pulse and Vector `0.92 lines gloss bodyside rearbody`; Kestrel, Bruiser,
#   Copperhead, Halcyon and Blue Static `0.85 lines gloss bodyside rearbody`; Last Exit `0.85 lines gloss bodyside`;
#   Vanta and Night Marshal `0.92 lines gloss bodyside`; each again with `lq` in place of `lines` for its light version)
import io
src,out=sys.argv[1:3]
GLASS_Y=float(sys.argv[3]) if len(sys.argv)>3 else 0.84
FLAGS=sys.argv[4:]
LQ='lq' in FLAGS               # the light distance version (no carved lines)
LINES=('lines' in FLAGS) and not LQ          # carve the texture's shut lines and handles
GLOSS_TRIM='gloss' in FLAGS     # black lower panels as gloss black
BODYSIDE='bodyside' in FLAGS    # paint the broad black lower bodyside band
RED_PAINT=False
PAINT_LIGHT=False
PAINT_LUM=0.3
d=open(src,'rb').read()
ln=struct.unpack('<I',d[12:16])[0]; j=json.loads(d[20:20+ln])
off=20+ln; bl=struct.unpack('<I',d[off:off+4])[0]; B=d[off+8:off+8+bl]
def tex(i):  # embedded image i as float RGB
    bv=j['bufferViews'][j['images'][i]['bufferView']]; o=bv.get('byteOffset',0)
    return np.asarray(Image.open(io.BytesIO(B[o:o+bv['byteLength']])).convert('RGB'),dtype=np.float32)/255
CT={5126:np.float32,5123:np.uint16,5125:np.uint32}; NC={'SCALAR':1,'VEC2':2,'VEC3':3}
def acc(i):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
    o=bv.get('byteOffset',0)+a.get('byteOffset',0); n=a['count']*NC[a['type']]
    arr=np.frombuffer(B,dtype=CT[a['componentType']],count=n,offset=o).astype(np.float64 if a['componentType']==5126 else np.int64)
    return arr.reshape(a['count'],NC[a['type']]) if NC[a['type']]>1 else arr
A=tex(j['textures'][j['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']]['source'])
E=tex(j['textures'][j['materials'][0]['emissiveTexture']['index']]['source'])
def to_game(p):
    return np.stack([-p[:,0],p[:,1],-(p[:,2]+REAR)],1)   # rotate 180 about y, rear bumper to z=0
def ngame(n):
    return np.stack([-n[:,0],n[:,1],-n[:,2]],1)
def samp(img,uv):
    h,w=img.shape[:2]; x=np.clip((uv[:,0]*w).astype(int),0,w-1); y=np.clip((uv[:,1]*h).astype(int),0,h-1); return img[y,x]
def classify(uv,pos):
    a=samp(A,uv); e=samp(E,uv); lum=a.mean(1)
    k=np.full(len(uv),'paint',dtype=object)
    dark=lum<0.07
    k[dark&(pos[:,1]>GLASS_Y)]='glass'
    k[dark&(pos[:,1]<=GLASS_Y)]='gloss' if GLOSS_TRIM else 'dark'
    if BODYSIDE:
        # the broad black band low on the sides becomes body colour above a
        # black sill strip (thin lines are not 'big' dark areas and stay)
        big=samp(BIG_DARK,uv)[:,0]>0.5
        k[dark&big&(pos[:,1]>0.34)&(pos[:,1]<=GLASS_Y)&(np.abs(pos[:,0])>0.8)]='paint'
    if LINES:
        # thin painted details: shut lines, handles, fuel flap (darker than the paint)
        ratio=lum/max(PAINT_LUM,1e-3)
        k[(k=='paint')&(ratio<0.72)&(~dark)]='gloss'
        # faint heater lines printed on the rear window are still glass
        k[(k=='gloss')&(lum<0.13)&(~dark)&(pos[:,1]>GLASS_Y)]='glass'
    if not PAINT_LIGHT:  # on a white car the paint itself is 'white'
        k[(a[:,0]>0.6)&(a[:,1]>0.6)&(a[:,2]>0.6)]='headlens'
    if not RED_PAINT:  # red lens areas count as tail lamp, unless the car itself is red
        k[(a[:,0]>0.35)&(a[:,1]<0.2)&(a[:,2]<0.2)]='tail'
    # number plates painted into the texture: white panels across the middle
    # of the nose and tail (lamps sit further out)
    k[(k=='headlens')&(np.abs(pos[:,0])<0.32)&(e.max(1)<0.2)]='plate'
    k[(e[:,0]>0.5)&(e[:,1]>0.5)]='head'
    k[(e[:,0]>0.3)&(e[:,1]<0.2)]='tail'
    return k
surf={}
def add(kind,P,N,UV=None):
    s=surf.setdefault(kind,{'p':[],'n':[]}); s['p'].append(P); s['n'].append(N)
p=j['meshes'][0]['primitives'][0]
_prims=j['meshes'][0]['primitives']
REAR=-min(float(j['accessors'][q['attributes']['POSITION']]['min'][2]) for q in (_prims[:1] if 'rearbody' in FLAGS else _prims))  # rear of the whole vehicle to z = 0
_ALLMIN=-REAR
_ALLMAX=max(float(j['accessors'][q['attributes']['POSITION']]['max'][2]) for q in _prims)
_P0MIN=float(j['accessors'][p['attributes']['POSITION']]['min'][2]); _P0MAX=float(j['accessors'][p['attributes']['POSITION']]['max'][2])
PARTIAL=(_P0MAX-_P0MIN)<0.7*(_ALLMAX-_ALLMIN)   # a truck: the main texture covers only the cab
P=acc(p['attributes']['POSITION']); N=acc(p['attributes']['NORMAL']); UV=acc(p['attributes']['TEXCOORD_0']); T=acc(p['indices']).reshape(-1,3)
tp=P[T]; tn=N[T]; tu=UV[T]
if BODYSIDE:
    # dark areas wider than a few texels (opening = erode then dilate)
    _dk=(A.mean(2)<0.07)
    def _shift_all(m,r,op):
        out=m.copy()
        for dy in range(-r,r+1):
            for dx in range(-r,r+1):
                sh=np.roll(np.roll(m,dy,0),dx,1)
                out=op(out,sh)
        return out
    _er=_shift_all(_dk,4,np.logical_and)
    BIG_DARK=_shift_all(_er,5,np.logical_or).astype(np.float32)[...,None].repeat(3,2)
# the body colour: the commonest albedo over the body
_cols=(samp(A,tu.mean(1))*255).astype(int)//16
_vals,_cnt=np.unique(_cols,axis=0,return_counts=True)
_paint=_vals[np.argmax(_cnt)]*16/255.0
RED_PAINT=bool(_paint[0]>0.3 and _paint[1]<0.2 and _paint[2]<0.2)
PAINT_LUM=float(_paint.mean())
PAINT_LIGHT=bool(PAINT_LUM>0.6)
print('paint colour',(_paint*255).astype(int),'red paint' if RED_PAINT else '')
ORIG_CLS=None
MAXD=0 if LQ else 3
total=0
if LINES:
    # texel categories (paint, dark, white, red, lit head, lit tail) and a
    # summed-area table for each, so a triangle can ask "does more than one
    # kind of thing lie under me?" however thin it is (shut lines are ~2 texels)
    _lum=A.mean(2)
    _cat=np.zeros(_lum.shape,np.int8)
    _cat[_lum<0.07]=1
    if not PAINT_LIGHT:
        _cat[(A[...,0]>0.6)&(A[...,1]>0.6)&(A[...,2]>0.6)]=2
    if not RED_PAINT:
        _cat[(A[...,0]>0.35)&(A[...,1]<0.2)&(A[...,2]<0.2)]=3
    # the thin lines (shut lines, handles, the fuel flap): darker than the paint but not black. They count as a kind of
    # texel of their own, so that the mesh is refined along them: without it only the black ones were, and a grey line
    # came out as a row of dashes wherever a triangle's middle happened to land on it
    _cat[(_lum>=0.07)&(_lum<PAINT_LUM*0.72)&(_cat==0)]=6
    _Eb=np.asarray(Image.fromarray((E*255).astype(np.uint8)).resize((A.shape[1],A.shape[0])),dtype=np.float32)/255
    _cat[(_Eb[...,0]>0.5)&(_Eb[...,1]>0.5)]=4
    _cat[(_Eb[...,0]>0.3)&(_Eb[...,1]<0.2)]=5
    _sat=[]
    for ci in range(7):
        m=(_cat==ci).astype(np.int32)
        st=np.zeros((m.shape[0]+1,m.shape[1]+1),np.int32)
        st[1:,1:]=m.cumsum(0).cumsum(1)
        _sat.append(st)
    _H,_W=_lum.shape
def mixed(uv):
    """True where a triangle (UVs (n,3,2)) covers more than one kind of texel."""
    c=uv.mean(1,keepdims=True)
    uv=c+(uv-c)*0.62  # the middle of the triangle: slanted ones barely overlap a line's box
    u=uv[...,0]*_W; v=uv[...,1]*_H
    x0=np.clip(np.floor(u.min(1)).astype(int),0,_W-1); x1=np.clip(np.ceil(u.max(1)).astype(int),1,_W)
    y0=np.clip(np.floor(v.min(1)).astype(int),0,_H-1); y1=np.clip(np.ceil(v.max(1)).astype(int),1,_H)
    kinds=np.zeros(len(uv),int)
    for st in _sat:
        cnt=st[y1,x1]-st[y0,x1]-st[y1,x0]+st[y0,x0]
        kinds+=(cnt>0)
    big=((x1-x0)*(y1-y0))>2  # nothing left to resolve below a couple of texels
    return (kinds>1)&big
for depth in range(MAXD+1):
    c=classify(tu.mean(1),tp.mean(1))
    if depth==MAXD:
        final=(tp,tn,tu,c); break
    m=tp.mean(1,keepdims=True); mu=tu.mean(1,keepdims=True)
    dis=np.zeros(len(tp),bool)
    if LINES:
        dis|=mixed(tu)
    for v in range(3):
        # does any corner (pulled slightly in) disagree with the centroid?
        cv=classify((tu[:,v]*0.9+mu[:,0]*0.1),(tp[:,v]*0.9+m[:,0]*0.1))
        if LINES:
            dis|=cv!=c
            continue
        # refine along glass and lamp edges, and the big black lower panels
        # (the thin panel lines higher up are left alone: too many triangles)
        low=(tp[:,v,1]<0.55)
        coarse=lambda q: np.where((q=='paint')|((q=='dark')&~low),'body',q)
        dis|=coarse(cv)!=coarse(c)
    # emit settled triangles
    keep=~dis
    for kind in set(c[keep]):
        sel=keep&(c==kind)
        add(kind,tp[sel].reshape(-1,3),tn[sel].reshape(-1,3))
    tp,tn,tu=tp[dis],tn[dis],tu[dis]
    # split into 4
    def mid(x,a,b): return (x[:,a]+x[:,b])/2
    def sub(x):
        a,b,cc=x[:,0],x[:,1],x[:,2]; ab,bc,ca=mid(x,0,1),mid(x,1,2),mid(x,2,0)
        return np.concatenate([np.stack([a,ab,ca],1),np.stack([ab,b,bc],1),np.stack([ca,bc,cc],1),np.stack([ab,bc,ca],1)])
    tp,tn,tu=sub(tp),sub(tn),sub(tu)
    print('depth',depth,'refining',len(tp))
tp,tn,tu,c=final
for kind in set(c):
    sel=c==kind
    add(kind,tp[sel].reshape(-1,3),tn[sel].reshape(-1,3))
# the other primitives: wheel wells, mirrors (paint), chrome trim
# the other parts, by material: wheel wells, solid paint (mirrors, spoiler),
# chrome, black trim, matte aero parts; calipers are left out (the game's
# wheels bring their own)
BY_MAT={'WheelWell':'under','PaintSolid':'paint','Chrome':'chrome','TrimBlack':'gloss','AeroBlack':'dark','Cargo':'cargo','LampRed':'tail'}
for q in j['meshes'][0]['primitives'][1:]:
    mname=j['materials'][q['material']].get('name','')
    kind=BY_MAT.get(mname)
    if kind is None:
        print('skipping part',mname)
        continue
    P2=acc(q['attributes']['POSITION']); N2=acc(q['attributes']['NORMAL']); T2=acc(q['indices']).reshape(-1)
    add(kind,P2[T2],N2[T2])
# ---- measure the car and write its profile (tools/profiles/NAME.json)
def _measure():
    import os
    P0=to_game(P)                                   # every vertex of the main body
    cls0=classify(UV[T].mean(1),P[T].mean(1))       # class of each original triangle
    gtri=to_game(P[T[cls0=='glass']].reshape(-1,3)) if (cls0=='glass').any() else P0
    if PARTIAL:
        PA=[]
        for q in j['meshes'][0]['primitives']:
            if j['materials'][q['material']].get('name','')=='PaintSolid': continue
            PA.append(acc(q['attributes']['POSITION']))
        PA=to_game(np.concatenate(PA))
    else:
        PA=P0
    L=float(-PA[:,2].min()); W=float(2*np.abs(PA[:,0]).max())
    D=-P0[:,2]
    roof=float(PA[:,1].max()) if PARTIAL else float(P0[:,1].max())
    side=gtri[np.abs(gtri[:,0])>0.45]
    belt=float(np.percentile(side[:,1],8)) if len(side) else 0.9
    up=gtri[gtri[:,1]>belt+0.07]                       # real window glass, not dark rear-panel texture
    gd=-up[:,2] if len(up) else -gtri[:,2]
    g0=float(np.percentile(gd,0.5)); g1=float(np.percentile(gd,99.5))
    roof0=float(P0[:,1].max())
    hi=D[P0[:,1]>roof0-0.045]
    g2=float(hi.min()); g3=float(hi.max())
    def width_at(mask): 
        return float(np.abs(P0[mask,0]).max()) if mask.any() else W/2
    wbase=float(np.abs(side[:,0]).max()) if len(side) else W/2*0.8
    wsel=up[(-up[:,2])>g1-0.25]
    ws_hw=float(np.abs(wsel[:,0]).max()) if len(wsel) else wbase*0.7
    wroof=width_at(P0[:,1]>roof0-0.08)
    # shoulder height and body width along the car
    body=[]
    for d in [0.0,0.1,0.3,0.7,1.2,1.8,2.4,3.0,3.5,3.9,4.2,L]:
        if d>L: continue
        DA=-PA[:,2]
        sel=np.abs(DA-d)<0.06
        if not sel.any(): continue
        top=float(PA[sel,1].max())
        if g0<d<g1: top=min(top,belt+0.04)
        body.append([round(d,3),round(top,3),round(float(np.abs(PA[sel,0]).max())/(W/2),3)])
    # wheels from the nodes
    wn=[n for n in j['nodes'] if n.get('name','').startswith('Wheel_')]
    rear=[n for n in wn if n['translation'][2]<0]; front=[n for n in wn if n['translation'][2]>0]
    r=float(wn[0]['translation'][1])
    rear_d=float(np.mean([REAR+n['translation'][2] for n in rear])); front_d=float(np.mean([REAR+n['translation'][2] for n in front]))
    wx=[float(np.mean([abs(n['translation'][0]) for n in rear])),float(np.mean([abs(n['translation'][0]) for n in front]))]
    wm=j['meshes'][1]['primitives'][0]; wpos=acc(wm['attributes']['POSITION'])
    tyre=float(wpos[:,0].max()-wpos[:,0].min())
    axles=sorted(rear_d_ for rear_d_ in [REAR+n['translation'][2] for n in wn])
    return {"L":round(L,3),"W":round(W,3),"roof":round(roof,3),"belt":round(belt,3),
        "gh":[round(g0,3),round(g1,3),round(g2,3),round(g3,3),round(belt,3),round(roof0,3),round(wbase/(W/2),3),round(wroof/(W/2),3)],
        "body":body,"wheel":[round(r,3),round(rear_d,3),round(front_d,3)],"wheel_x":[round(wx[0],3),round(wx[1],3)],"tyre":round(tyre,3),
        "ws_hw":round(ws_hw,3),"axles":[round(a,3) for a in sorted(set(round(a,2) for a in axles))]}
res={}
for kind,s in surf.items():
    pp=to_game(np.concatenate(s['p'])); nn=ngame(np.concatenate(s['n']))
    # 180 degree rotation keeps the winding; normalise
    nn/=np.maximum(np.linalg.norm(nn,axis=1,keepdims=True),1e-9)
    res[kind]=(pp.astype(np.float32),nn.astype(np.float32))
    print(kind,len(pp)//3,'tris')
# measurements for the interior profile
gp=res['glass'][0]
print('glass y',gp[:,1].min(),gp[:,1].max(),'d',(-gp[:,2]).min(),(-gp[:,2]).max(),'x',gp[:,0].min(),gp[:,0].max())
allp=np.concatenate([v[0] for v in res.values()])
for dd in np.arange(0.0,4.4,0.25):
    sel=np.abs(-allp[:,2]-dd)<0.06
    if sel.any():
        g=sel&(np.isin(np.arange(len(allp)),[]) )
        print('d %.2f top %.3f hw %.3f'%(dd,allp[sel,1].max(),np.abs(allp[sel,0]).max()))
for dd in np.arange(0.4,3.8,0.2):
    sel=np.abs(-gp[:,2]-dd)<0.05
    if sel.any(): print('glass d %.2f ymin %.3f ymax %.3f xmax %.3f'%(dd,gp[sel,1].min(),gp[sel,1].max(),np.abs(gp[sel,0]).max()))
sel=(np.abs(allp[:,0])<0.15)&(np.abs(allp[:,1]-0.55)<0.05)
print('rear face z at plate height',allp[sel,2].max())
import json,os
_prof=_measure() if not LQ else None
os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)),'profiles'),exist_ok=True)
if _prof: json.dump(_prof,open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'profiles',os.path.splitext(os.path.basename(out))[0]+'.json'),'w'))
if _prof: print('profile',{k:_prof[k] for k in ('L','W','roof','belt','gh','wheel','wheel_x','tyre')})
# binary: magic, surface count, then per surface: name, vertex count, positions,
# normals, index count, indices (vertices shared where position and normal match)
order=['paint','cargo','glass','dark','under','chrome','gloss','plate','headlens','head','tail']
with open(out,'wb') as f:
    f.write(b'CPE2'); names=[k for k in order if k in res]
    f.write(struct.pack('<I',len(names)))
    for k in names:
        pp,nn=res[k]
        if LQ:
            # distance version: merge vertices that fall in the same 6 cm cell, drop flattened triangles
            key=np.round(pp/0.06).astype(np.int64)
            uq,inv=np.unique(key,axis=0,return_inverse=True); inv=inv.reshape(-1)
            cnt=np.bincount(inv,minlength=len(uq)).astype(np.float64)
            vp=np.stack([np.bincount(inv,weights=pp[:,a_],minlength=len(uq)) for a_ in range(3)],1)/cnt[:,None]
            vn=np.stack([np.bincount(inv,weights=nn[:,a_],minlength=len(uq)) for a_ in range(3)],1)
            vn/=np.maximum(np.linalg.norm(vn,axis=1,keepdims=True),1e-9)
            tri=inv.reshape(-1,3)
            ok=(tri[:,0]!=tri[:,1])&(tri[:,1]!=tri[:,2])&(tri[:,0]!=tri[:,2])
            idx=tri[ok].reshape(-1).astype(np.uint32)
        else:
            key=np.round(np.concatenate([pp,nn],1)*20000).astype(np.int64)
            uq,inv=np.unique(key,axis=0,return_inverse=True)
            first=np.zeros(len(uq),np.int64); first[inv[::-1]]=np.arange(len(inv))[::-1]
            vp=pp[first]; vn=nn[first]; idx=inv.reshape(-1).astype(np.uint32)
        nb=k.encode(); f.write(struct.pack('<I',len(nb))); f.write(nb)
        f.write(struct.pack('<I',len(vp))); f.write(vp.astype(np.float32).tobytes()); f.write(vn.astype(np.float32).tobytes())
        f.write(struct.pack('<I',len(idx))); f.write(idx.tobytes())
        print(k,'verts',len(vp),'idx',len(idx))
print('wrote',out)
