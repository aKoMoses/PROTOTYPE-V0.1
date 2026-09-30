"""Deterministic authored ground atlas. No downloaded assets, no gameplay geometry."""
from pathlib import Path
import sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

out = (Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]) / 'art/environment'
out.mkdir(parents=True, exist_ok=True)
N = 2048
rng = np.random.default_rng(70903)
def noise(grid, blur=0):
    a = Image.fromarray((rng.random((grid, grid))*255).astype('uint8'))
    a = a.resize((N,N), Image.Resampling.BICUBIC)
    if blur: a = a.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(a,dtype=float)/255-.5
cloud = noise(7)*34 + noise(19)*18 + noise(60)*7 + noise(180)*4
base=np.empty((N,N,3),dtype=np.uint8)
for c,col in enumerate([145,130,108]):
    base[:,:,c]=np.clip(col+cloud*(1 if c<2 else .82),0,255)
im=Image.fromarray(base,'RGB').convert('RGBA')
def uv(x,z): return ((x+30)/60*N,(z+30)/60*N)
def layer(): return Image.new('RGBA',(N,N))
def blend(a,blur=0):
    global im
    if blur:a=a.filter(ImageFilter.GaussianBlur(blur))
    im=Image.alpha_composite(im,a)

# Large wind-blown sand shoulders and quiet compacted fighting lanes.
a=layer();d=ImageDraw.Draw(a)
for x,z,rx,rz in [(-26,0,3,29),(26,0,3,29),(0,-27,28,2),(0,27,28,2),(-13,-12,7,3),(14,13,7,3),(-1,2,5,16)]:
    u,v=uv(x,z);d.ellipse((u-rx/60*N,v-rz/60*N,u+rx/60*N,v+rz/60*N),fill=(193,174,137,70))
blend(a,35)

# Wheels enter from north service bays, then follow the perimeter service loop.
routes=[ [(-12,-29),(-13,-24),(-23,-19),(-24,-7),(-24,8),(-23,20),(-17,24)],
         [(12,-29),(13,-24),(23,-21),(24,-8),(24,7),(24,19),(17,24)],
         [(-14,-24),(-4,-25),(7,-25),(15,-24)],
         [(-17,24),(-6,25),(5,25),(17,24)],
         [(-24,-5),(-20,-4),(-17,-3),(-13,0),(-12,4)],
         [(24,5),(20,4),(17,3),(13,0),(12,-4)] ]
def smooth(points):
    padded=[points[0]]+points+[points[-1]]; result=[]
    for i in range(1,len(padded)-2):
        p0,p1,p2,p3=[np.array(p,dtype=float) for p in padded[i-1:i+3]]
        for t in np.linspace(0,1,60,endpoint=False):
            result.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
    return result
for route in routes:
    pts=smooth(route)
    a=layer();d=ImageDraw.Draw(a)
    for side in [-.52,.52]:
        shifted=[]
        for i,p in enumerate(pts):
            tangent=pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)];tangent/=max(np.linalg.norm(tangent),.001)
            shifted.append(p+np.array([-tangent[1],tangent[0]])*side)
        d.line([uv(*p) for p in shifted],fill=(75,64,49,42),width=12)
    blend(a,4)
    a=layer();d=ImageDraw.Draw(a)
    distance=0
    for i in range(1,len(pts)):
        delta=pts[i]-pts[i-1];distance+=np.linalg.norm(delta)
        if distance<.50:continue
        distance=0
        tangent=delta/max(np.linalg.norm(delta),.001);normal=np.array([-tangent[1],tangent[0]])
        for side in [-.52,.52]:
            center=pts[i]+normal*side
            d.line([uv(*(center-normal*.115-tangent*.08)),uv(*(center+normal*.115+tangent*.08))],fill=(89,72,49,38),width=3)
    blend(a,1)

# Fitted maintenance repairs: asymmetrical small plates, not a repeating grid.
a=layer();d=ImageDraw.Draw(a)
for cx,cz,w,h,angle in [(-23,-16,3,4,8),(23,16,3.2,4,-7),(-18,20,4.8,2.7,0),(18,-22,4.2,2.6,0)]:
    co,si=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    def p(x,z):return uv(cx+x*co-z*si,cz+x*si+z*co)
    corners=[(-w/2+.2,-h/2),(w/2-.2,-h/2),(w/2,-h/2+.2),(w/2,h/2-.2),(w/2-.2,h/2),(-w/2+.2,h/2),(-w/2,h/2-.2),(-w/2,-h/2+.2)]
    d.polygon([p(x,z) for x,z in corners],fill=(77,77,69,190))
    for sign in [-1,1]:
        d.line([p(-w*.4,sign*h*.40),p(w*.4,sign*h*.40)],fill=(157,134,95,180),width=4)
        for x in [-w*.4,0,w*.4]:
            u,v=p(x,sign*h*.39);d.ellipse((u-3,v-3,u+3,v+3),fill=(44,48,45,205))
    for i in range(4):
        d.line([p(-w*.32+i*w*.22,-h*.27),p(-w*.32+i*w*.22,h*.27)],fill=(49,54,50,140),width=3)
blend(a)

# Dust gathers at actual cover feet, perimeter and bush edges; baked relief only.
covers=[(0,-9,10.8,1.55,0),(-7,1.2,2.15,9.6,0),(7,1.2,2.15,9.6,0),(0,11,9.5,1.55,0),(-11.3,-9.4,6.2,1.4,-24),(11.3,10.8,6.2,1.4,-24),(12,-6.7,5,1.3,25),(-12,8.1,5,1.3,25),(-18.5,8,1.8,5.5,0),(-16,10,4.6,1.6,0),(18.5,-8,1.8,5.5,0),(16,-10,4.6,1.6,0),(-17.5,-15,4,3.5,0),(17.5,15,4,3.5,0),(17.8,-16,3.2,3.2,0),(-17.8,16,3.2,3.2,0)]
a=layer();d=ImageDraw.Draw(a)
for cx,cz,w,h,angle in covers:
    co,si=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    corners=[]
    for x,z in [(-w/2-.8,-h/2-.7),(w/2+.8,-h/2-.7),(w/2+.8,h/2+.7),(-w/2-.8,h/2+.7)]:
        corners.append(uv(cx+x*co+z*si,cz-x*si+z*co))
    d.polygon(corners,fill=(185,158,116,70))
blend(a,13)

a=layer();d=ImageDraw.Draw(a)
for cx,cz,w,h,angle in covers:
    co,si=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    # Small fragments remain tucked against cover feet, not scattered down lanes.
    for i in range(27):
        lx=rng.uniform(-w*.55,w*.55);lz=(-1 if i%2 else 1)*(h*.5+rng.uniform(.03,.38))
        x=cx+lx*co+lz*si;z=cz-lx*si+lz*co
        u,v=uv(x,z);r=rng.uniform(1.4,4)
        d.ellipse((u-r+1,v-r+1,u+r+2,v+r+2),fill=(67,59,44,75))
        d.polygon([(u-r,v),(u,v-r*.8),(u+r,v+r*.6)],fill=(150+i%3*13,126+i%3*9,89,120))
for cx,cz in [(-26,-20),(25,21),(-22,17),(21,-18)]:
    for j in range(3):
        x=cx+j*.38;z=cz+j*.23;points=[(x,z),(x+.32,z+.3),(x+.18,z+.57),(x+.42,z+.85)]
        d.line([uv(*p) for p in points],fill=(87,70,45,65),width=2)
blend(a, .55)
im.convert('RGB').save(out/'arena_sand_atlas.png',optimize=True)
Image.fromarray(base).resize((512,512),Image.Resampling.LANCZOS).save(out/'exterior_sand.png')

# A broad feathered contact footprint for covers; UV mask is shared by all sizes.
n=256;xx,yy=np.meshgrid(np.linspace(-1,1,n),np.linspace(-1,1,n))
edge=np.maximum(np.abs(xx),np.abs(yy));alpha=np.clip((1-edge)/.34,0,1)*.24
rgba=np.zeros((n,n,4),dtype=np.uint8);rgba[:,:,:3]=[78,62,40];rgba[:,:,3]=(alpha*255).astype('uint8')
Image.fromarray(rgba).save(out/'cover_contact.png')
print('Authored arena atlas and contact mask saved:',out)
