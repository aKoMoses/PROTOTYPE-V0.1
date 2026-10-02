"""Offline authored courtyard textures. Relief contains no baked lighting."""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[2] / 'art/environment'
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(20261002)
N = 4096

def field(size, grid):
    image = Image.fromarray((RNG.random((grid, grid)) * 255).astype('uint8'))
    return np.asarray(image.resize((size, size), Image.Resampling.BICUBIC), dtype=np.float32) / 255 - .5

def normal_map(height, strength, path):
    dy, dx = np.gradient(height.astype(np.float32))
    vectors = np.dstack((-dx * strength, dy * strength, np.ones_like(dx)))
    vectors /= np.linalg.norm(vectors, axis=2, keepdims=True)
    Image.fromarray(np.clip((vectors * .5 + .5) * 255, 0, 255).astype('uint8')).save(path)

def uv(x, z):
    return ((x + 30) / 60 * N, (z + 30) / 60 * N)

cloud = field(N, 9)*11 + field(N, 45)*8 + field(N, 230)*5 + field(N, 950)*4
grain = RNG.normal(0, 1.8, (N, N)).astype(np.float32)
base = np.dstack([np.clip(value+cloud+grain, 0, 255) for value in [177,169,151]]).astype('uint8')
im = Image.fromarray(base).convert('RGBA')
relief = Image.new('L', (N,N), 128)
hd = ImageDraw.Draw(relief)

def layer():
    return Image.new('RGBA', (N,N))

def blend(image, blur=0):
    global im
    if blur:
        image = image.filter(ImageFilter.GaussianBlur(blur))
    im = Image.alpha_composite(im, image)

# Large irregular concrete pours, with quiet seams rather than a small tile grid.
edges = [-30,-23.5,-16,-8.8,-1.5,6.3,14,21.3,30]
a = layer(); d = ImageDraw.Draw(a)
for row in range(8):
    for col in range(8):
        x0,x1 = edges[col:col+2]; z0,z1 = edges[row:row+2]
        offset = float(RNG.uniform(-.55,.55)) if row not in [0,7] else 0
        points = [uv(x0,z0),uv(x1,z0),uv(x1+offset,z1),uv(x0+offset,z1)]
        color = (203,199,184,int(RNG.integers(2,20))) if (row+col)%3 else (107,102,88,13)
        d.polygon(points,fill=color)
        d.line(points+[points[0]],fill=(79,77,68,105),width=3)
        hd.line(points+[points[0]],fill=70,width=3)
        d.line([(u+2,v+2) for u,v in points+[points[0]]],fill=(223,210,183,70),width=2)
blend(a)

# Concrete pores and aggregate retain texture without noisy contrast.
a=layer(); d=ImageDraw.Draw(a)
for _ in range(46000):
    u,v=RNG.integers(0,N,2); r=float(RNG.uniform(.4,2.5))
    color=(100,96,85,28) if bool(RNG.integers(0,2)) else (220,211,187,43)
    d.ellipse((u-r,v-r*.6,u+r,v+r*.6),fill=color)
blend(a,.35)
a=layer(); d=ImageDraw.Draw(a)
for _ in range(115):
    x,z=RNG.uniform(-29,29,2); points=[uv(x,z)]; direction=float(RNG.uniform(0,math.tau))
    for segment in range(int(RNG.integers(3,7))):
        direction+=float(RNG.uniform(-.65,.65))
        x+=math.cos(direction)*.22; z+=math.sin(direction)*.22
        points.append(uv(x,z))
    d.line(points,fill=(82,79,69,95),width=2); hd.line(points,fill=94,width=2)
    for u,v in points[::2]:
        d.ellipse((u-5,v-3,u+5,v+3),fill=(134,123,101,45))
blend(a)

# Flush steel inserts and rail channels use actual world coordinates.
a=layer(); d=ImageDraw.Draw(a)
plates=[(-23,-16,3,4,8),(23,16,3.2,4,-7),(-18,20,4.8,2.7,0),(18,-22,4.2,2.6,0),
        (-3,-1,2.8,1.9,0),(13,7,2.1,3,0),(-12,-19,2,2.8,0),(4,18,2.8,1.6,0)]
for cx,cz,w,h,angle in plates:
    co,si=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    def p(x,z): return uv(cx+x*co-z*si,cz+x*si+z*co)
    corners=[(-w/2+.15,-h/2),(w/2-.15,-h/2),(w/2,-h/2+.15),(w/2,h/2-.15),
             (w/2-.15,h/2),(-w/2+.15,h/2),(-w/2,h/2-.15),(-w/2,-h/2+.15)]
    vertices=[p(x,z) for x,z in corners]
    d.polygon(vertices,fill=(105,116,119,230)); d.line(vertices+[vertices[0]],fill=(58,65,65,230),width=5)
    hd.polygon(vertices,fill=137); hd.line(vertices+[vertices[0]],fill=75,width=5)
    for sign in [-1,1]:
        d.line([p(-w*.41,sign*h*.41),p(w*.41,sign*h*.41)],fill=(173,154,118,195),width=3)
        for x in [-w*.39,0,w*.39]:
            u,v=p(x,sign*h*.38)
            d.ellipse((u-5,v-5,u+5,v+5),fill=(54,60,58,240))
            d.ellipse((u-3,v-3,u+2,v+2),fill=(177,159,118,230))
            hd.ellipse((u-4,v-4,u+4,v+4),fill=180)
    for x in np.arange(-w*.34,w*.35,.27):
        for z in np.arange(-h*.29,h*.3,.30):
            d.line([p(x-.05,z-.06),p(x+.05,z+.06)],fill=(178,177,159,105),width=3)
            hd.line([p(x-.05,z-.06),p(x+.05,z+.06)],fill=152,width=3)
for x in [-25.2,25.2]:
    d.line([uv(x,-29),uv(x,29)],fill=(86,91,86,130),width=12)
    d.line([uv(x+.07,-29),uv(x+.07,29)],fill=(193,186,160,130),width=3)
    hd.line([uv(x,-29),uv(x,29)],fill=82,width=12)
blend(a)

# Worn ochre marks beside service bays, never bright gameplay colors.
a=layer(); d=ImageDraw.Draw(a)
for cx,cz,w,h in [(-22,5,1.1,5),(22,-5,1.1,5),(-4,-15,5,.85),(4,16,5,.85)]:
    for i in range(7):
        x=cx-w*.5+i*w/7
        pts=[uv(x,cz-h*.5),uv(x+w*.07,cz-h*.5),uv(x+w*.2,cz+h*.5),uv(x+w*.13,cz+h*.5)]
        d.polygon(pts,fill=(211,158,54,175))
    for _ in range(90):
        u,v=uv(cx+RNG.uniform(-w*.5,w*.5),cz+RNG.uniform(-h*.5,h*.5)); r=RNG.uniform(2,8)
        d.ellipse((u-r,v-r*.7,u+r,v+r*.7),fill=(0,0,0,0))
blend(a)
# A battered painted service-lane edge beside the southern recovery pad.
a=layer(); d=ImageDraw.Draw(a)
d.line([uv(-1.2,14.7),uv(-1.2,24.7)],fill=(211,158,54,155),width=9)
for _ in range(220):
    u,v=uv(-1.2+RNG.uniform(-.07,.07),RNG.uniform(14.7,24.7))
    r=RNG.uniform(1,5)
    d.ellipse((u-r,v-r*.6,u+r,v+r*.6),fill=(0,0,0,0))
blend(a)
a=layer(); d=ImageDraw.Draw(a)
for route in [[(-12,-29),(-14,-24),(-24,-16),(-24,15),(-17,24)],
              [(12,-29),(14,-24),(24,-16),(24,15),(17,24)],
              [(-20,-3),(-15,-2),(-10,1),(-8,4)],[(20,3),(15,2),(10,-1),(8,-4)]]:
    for offset in [-.48,.48]:
        d.line([uv(x+offset,z) for x,z in route],fill=(101,88,69,37),width=18,joint='curve')
blend(a,5)

# Sand shoulders are matched to existing gameplay cover footprints.
covers=[(0,-9,10.8,1.55,0),(-7,1.2,2.15,9.6,0),(7,1.2,2.15,9.6,0),(0,11,9.5,1.55,0),
        (-11.3,-9.4,6.2,1.4,-24),(11.3,10.8,6.2,1.4,-24),(12,-6.7,5,1.3,25),(-12,8.1,5,1.3,25),
        (-18.5,8,1.8,5.5,0),(-16,10,4.6,1.6,0),(18.5,-8,1.8,5.5,0),(16,-10,4.6,1.6,0),
        (-17.5,-15,4,3.5,0),(17.5,15,4,3.5,0),(17.8,-16,3.2,3.2,0),(-17.8,16,3.2,3.2,0)]
a=layer(); d=ImageDraw.Draw(a)
for cx,cz,w,h,angle in covers:
    co,si=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    points=[uv(cx+x*co+z*si,cz-x*si+z*co) for x,z in [(-w/2-.75,-h/2-.55),(w/2+.75,-h/2-.55),(w/2+.75,h/2+.55),(-w/2-.75,h/2+.55)]]
    d.polygon(points,fill=(208,179,129,155))
for x,z,rx,rz in [(-28,0,2,29),(28,0,2,29),(0,-28,29,2),(0,28,29,2)]:
    u,v=uv(x,z)
    d.ellipse((u-rx/60*N,v-rz/60*N,u+rx/60*N,v+rz/60*N),fill=(206,174,123,135))
blend(a,21)
a=layer(); d=ImageDraw.Draw(a)
for cx,cz,w,h,angle in covers:
    co,si=math.cos(math.radians(angle)),math.sin(math.radians(angle))
    for i in range(105):
        lx=RNG.uniform(-w*.55,w*.55); lz=(-1 if i%2 else 1)*(h*.5+RNG.uniform(.03,.55))
        u,v=uv(cx+lx*co+lz*si,cz-lx*si+lz*co); r=RNG.uniform(1,4)
        d.ellipse((u-r+1,v-r+1,u+r+2,v+r+2),fill=(72,65,47,80))
        d.polygon([(u-r,v),(u,v-r*.8),(u+r,v+r*.6)],fill=(180+i%3*9,156+i%3*8,110,155))
blend(a,.3)

# The reference is a working salvage courtyard: chipped pours, branching
# fractures and interrupted tyre tracks, authored at metre scale rather than
# a repeated small grunge tile. All marks are colour/relief, never baked light.
a=layer(); d=ImageDraw.Draw(a)
for _ in range(280):
    x,z=RNG.uniform(-29,29,2)
    rx,rz=RNG.uniform(.18,.90,2)
    count=int(RNG.integers(8,18))
    points=[]
    for t in np.linspace(0,math.tau,count,endpoint=False):
        jitter=float(RNG.uniform(.55,1.25))
        points.append(uv(x+math.cos(t)*rx*jitter,z+math.sin(t)*rz*jitter))
    shade=int(RNG.integers(94,137))
    d.polygon(points,fill=(shade,shade-3,shade-12,int(RNG.integers(42,98))))
    hd.polygon(points,fill=118)
    # Exposed grit sits inside each irregular spall, with a few fallen chips.
    for _ in range(int(RNG.integers(12,48))):
        u,v=uv(x+RNG.uniform(-rx,rx),z+RNG.uniform(-rz,rz))
        r=float(RNG.uniform(1,4))
        d.polygon([(u-r,v),(u-r*.2,v-r*.65),(u+r,v-r*.1),(u+r*.4,v+r*.6)],
                  fill=(184,172,148,int(RNG.integers(55,155))))
blend(a,.35)

a=layer(); d=ImageDraw.Draw(a)
for index in range(92):
    x,z=RNG.uniform(-29,29,2)
    if index%3==0:
        z=float(RNG.choice(edges[1:-1]))
    points=[uv(x,z)]; direction=float(RNG.uniform(0,math.tau))
    for step in range(int(RNG.integers(8,20))):
        direction+=float(RNG.uniform(-.55,.55))
        x+=math.cos(direction)*float(RNG.uniform(.10,.35))
        z+=math.sin(direction)*float(RNG.uniform(.10,.35))
        points.append(uv(x,z))
        if step%4==2:
            u,v=points[-1]
            branch=[(u,v),(u+RNG.uniform(-19,19),v+RNG.uniform(-19,19)),
                    (u+RNG.uniform(-35,35),v+RNG.uniform(-35,35))]
            d.line(branch,fill=(63,58,50,155),width=2)
            hd.line(branch,fill=75,width=2)
    d.line(points,fill=(144,124,92,74),width=9,joint='curve')
    d.line(points,fill=(61,58,51,185),width=3,joint='curve')
    d.line([(u+2,v+1) for u,v in points],fill=(219,201,166,125),width=1)
    hd.line(points,fill=62,width=3,joint='curve')
blend(a)

# Motor oil splashes and dusty abrasion, with broken edges and separate drops.
a=layer(); d=ImageDraw.Draw(a)
for cx,cz in [(-9,17),(12,19),(-16,-3),(9,-17),(-4,7),(18,7),(-20,24),(21,-24)]:
    # Fragment a broad spill with two noise scales; individual circular stamps
    # looked like coins. The resulting chipped edges belong to this location.
    size=384
    yy,xx=np.mgrid[-1:1:complex(size),-1:1:complex(size)]
    noise=field(size,25)*.82+field(size,118)*.36
    shape=1-np.sqrt(xx*xx+yy*yy*1.75)
    mask=np.clip((shape+noise-.20)*2.6,0,1)
    broken=np.clip((field(size,88)+.28)*4.4,0,1)
    rgba=np.zeros((size,size,4),dtype=np.uint8)
    rgba[:,:,:3]=[57,56,49]
    rgba[:,:,3]=(mask*broken*115).astype(np.uint8)
    u,v=uv(cx,cz)
    a.alpha_composite(Image.fromarray(rgba),(int(u-size/2),int(v-size/2)))
    for _ in range(90):
        x=cx+float(RNG.normal(0,1.0)); z=cz+float(RNG.normal(0,.75))
        radius=float(RNG.uniform(.015,.095))
        points=[uv(x+math.cos(t)*radius*RNG.uniform(.45,1.4),
                   z+math.sin(t)*radius*RNG.uniform(.45,1.4))
                for t in np.linspace(0,math.tau,7,endpoint=False)]
        d.polygon(points,fill=(56,54,47,int(RNG.integers(35,105))))
blend(a,.25)

a=layer(); d=ImageDraw.Draw(a)
for cx,cz,radius,start,end in [(-8,16,4.8,100,235),(10,17,4.2,-35,75),
                               (-16,-12,4.5,-80,55),(16,-18,4.2,85,215)]:
    for radial_offset in [-.33,.33]:
        r=radius+radial_offset
        for angle in np.arange(start,end,1.4):
            if RNG.random()<.17: continue
            t=math.radians(angle)
            center=np.array([cx+math.cos(t)*r,cz+math.sin(t)*r])
            radial=np.array([math.cos(t),math.sin(t)])*.10
            tangent=np.array([-math.sin(t),math.cos(t)])*.045
            pts=[uv(*(center+radial+tangent)),uv(*(center-radial+tangent)),
                 uv(*(center-radial-tangent)),uv(*(center+radial-tangent))]
            d.polygon(pts,fill=(66,63,53,int(RNG.integers(38,104))))
blend(a,.25)

# Faded gear stencils on the flanks, as in the concept.
a=layer(); d=ImageDraw.Draw(a)
for cx,cz in [(15.5,14),(-18,-17)]:
    u,v=uv(cx,cz); r=1.05*N/60
    d.ellipse((u-r,v-r,u+r,v+r),outline=(72,69,60,150),width=12)
    for t in np.linspace(0,math.tau,12,endpoint=False):
        direction=np.array([math.cos(t),math.sin(t)])
        sideways=np.array([-math.sin(t),math.cos(t)])
        center=np.array([cx,cz])+direction*.88
        d.polygon([uv(*(center+direction*.24+sideways*.15)),
                   uv(*(center+direction*.24-sideways*.15)),
                   uv(*(center-direction*.12-sideways*.15)),
                   uv(*(center-direction*.12+sideways*.15))],fill=(75,71,60,150))
    for _ in range(120):
        px,py=uv(cx+RNG.uniform(-1.2,1.2),cz+RNG.uniform(-1.2,1.2))
        rr=RNG.uniform(1,5)
        d.ellipse((px-rr,py-rr,px+rr,py+rr),fill=(0,0,0,0))
blend(a)
im.convert('RGB').save(OUT/'arena_sand_atlas.png',optimize=True)
height=np.asarray(relief,dtype=np.float32)/255+field(N,450)*.024
normal_map(height,2.7,OUT/'arena_concrete_normal.png')
del base,cloud,grain,height,im,relief

# Preserve ImageGen color assets. These procedural micro normals contain only
# fine pitting, so world projection does not stretch with cover dimensions.
S=1024
for name in ['paint', 'steel']:
    # Consume the original authoring noise to preserve deterministic outputs.
    cloud=field(S,12)*13+field(S,85)*6+field(S,430)*3
    wear=field(S,18)*.7+field(S,94)*.25+field(S,340)*.08
    rust=np.clip((wear-(.30 if name == 'steel' else .28))*24,0,1)
    for _ in range(270 if name == 'steel' else 165):
        x,y=RNG.integers(0,S,2); length=int(RNG.integers(4,35))
        RNG.integers(-3,4)
    normal_map(field(S,180)*.12+rust*.025,1.8,OUT/f'courtyard_{name}_normal.png')
cloud=field(S,12)*19+field(S,100)*7+field(S,450)*4
Image.fromarray(np.dstack([np.clip(col+cloud,0,255) for col in [181,151,108]]).astype('uint8')).save(OUT/'exterior_sand.png')
print('Courtyard atlas (4096), relief and exterior saved; authored albedos preserved:',OUT)
