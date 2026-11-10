# Split the starter coupe GLB body into game surfaces, in CarModel space
# (x right, y up, z = -d, rear bumper at z = 0, nose towards -z).
import json,struct,sys
import numpy as np
from PIL import Image
# usage: python3 tools/convert_coupe.py tools/models/starter_coupe.glb assets/models/starter_coupe.mesh
import io
src,out=sys.argv[1:3]
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
REAR=2.13
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
    k[dark&(pos[:,1]>0.84)]='glass'
    k[dark&(pos[:,1]<=0.84)]='dark'
    k[(a[:,0]>0.6)&(a[:,1]>0.6)&(a[:,2]>0.6)]='headlens'
    k[(a[:,0]>0.35)&(a[:,1]<0.2)&(a[:,2]<0.2)]='tail'
    k[(e[:,0]>0.5)&(e[:,1]>0.5)]='head'
    k[(e[:,0]>0.3)&(e[:,1]<0.2)]='tail'
    return k
surf={}
def add(kind,P,N,UV=None):
    s=surf.setdefault(kind,{'p':[],'n':[]}); s['p'].append(P); s['n'].append(N)
p=j['meshes'][0]['primitives'][0]
P=acc(p['attributes']['POSITION']); N=acc(p['attributes']['NORMAL']); UV=acc(p['attributes']['TEXCOORD_0']); T=acc(p['indices']).reshape(-1,3)
tp=P[T]; tn=N[T]; tu=UV[T]
MAXD=3
total=0
for depth in range(MAXD+1):
    c=classify(tu.mean(1),tp.mean(1))
    if depth==MAXD:
        final=(tp,tn,tu,c); break
    # does any corner (pulled slightly in) disagree with the centroid?
    m=tp.mean(1,keepdims=True); mu=tu.mean(1,keepdims=True)
    dis=np.zeros(len(tp),bool)
    for v in range(3):
        cv=classify((tu[:,v]*0.9+mu[:,0]*0.1),(tp[:,v]*0.9+m[:,0]*0.1))
        coarse=lambda q: np.where((q=='paint')|(q=='dark'),'body',q)
        dis|=coarse(cv)!=coarse(c)  # refine only along glass and lamp edges
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
for pi,kind in [(1,'under'),(2,'paint'),(3,'chrome')]:
    q=j['meshes'][0]['primitives'][pi]
    P2=acc(q['attributes']['POSITION']); N2=acc(q['attributes']['NORMAL']); T2=acc(q['indices']).reshape(-1)
    add(kind,P2[T2],N2[T2])
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
# binary: magic, surface count, then per surface: name, vertex count, positions,
# normals, index count, indices (vertices shared where position and normal match)
order=['paint','glass','dark','under','chrome','headlens','head','tail']
with open(out,'wb') as f:
    f.write(b'CPE2'); names=[k for k in order if k in res]
    f.write(struct.pack('<I',len(names)))
    for k in names:
        pp,nn=res[k]
        key=np.round(np.concatenate([pp,nn],1)*20000).astype(np.int64)
        uq,inv=np.unique(key,axis=0,return_inverse=True)
        first=np.zeros(len(uq),np.int64); first[inv[::-1]]=np.arange(len(inv))[::-1]
        vp=pp[first]; vn=nn[first]; idx=inv.reshape(-1).astype(np.uint32)
        nb=k.encode(); f.write(struct.pack('<I',len(nb))); f.write(nb)
        f.write(struct.pack('<I',len(vp))); f.write(vp.astype(np.float32).tobytes()); f.write(vn.astype(np.float32).tobytes())
        f.write(struct.pack('<I',len(idx))); f.write(idx.tobytes())
        print(k,'verts',len(vp),'idx',len(idx))
print('wrote',out)
