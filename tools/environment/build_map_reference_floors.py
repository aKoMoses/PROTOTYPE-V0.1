"""Bake the approved courtyard finish into layouts for the other play spaces."""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[2] / "art/environment/map_reference"
OUT.mkdir(parents=True, exist_ok=True)
N = 2048
LAYOUTS = {
    "test": (36, 30, [(-10, -5), (10, 5), (-10, 5), (10, -5)]),
    "training": (88, 76, [(-38, 7), (38, 7), (16, -2), (32, -2), (8, -30)]),
    "survival": (48, 48, [(-7.5, -5), (7.5, -4.5), (0, 9)]),
    "factory": (48, 48, [(-7, -4), (7, 7), (-5, 11), (10, -11)]),
    "passage": (8, 12, []),
}

for index, (name, (width, depth, solids)) in enumerate(LAYOUTS.items()):
    N = 4096 if name == "training" else 2048
    rng = np.random.default_rng(202610020 + index)
    def uv(x, z):
        return ((x / width + .5) * N, (z / depth + .5) * N)
    noise = np.asarray(Image.fromarray((rng.random((64,64))*255).astype("uint8")).resize((N,N),Image.Resampling.BICUBIC),dtype=np.float32)/255-.5
    grain = rng.normal(0,1.6,(N,N))
    im = Image.fromarray(np.dstack([np.clip(c+noise*20+grain,0,255) for c in (174,165,145)]).astype("uint8")).convert("RGBA")
    relief = Image.new("L",(N,N),128)
    hd = ImageDraw.Draw(relief)
    def blend(layer):
        return Image.alpha_composite(im,layer)
    layer = Image.new("RGBA",(N,N)); d=ImageDraw.Draw(layer)
    # Uneven concrete pours and localized fractures, at the same metre scale.
    for x in np.arange(-width/2+4,width/2,7.5):
        d.line([uv(x,-depth/2),uv(x+.2,depth/2)],fill=(71,69,60,120),width=2)
        hd.line([uv(x,-depth/2),uv(x+.2,depth/2)],fill=72,width=2)
    for z in np.arange(-depth/2+4,depth/2,7.0):
        d.line([uv(-width/2,z),uv(width/2,z)],fill=(71,69,60,110),width=2)
        hd.line([uv(-width/2,z),uv(width/2,z)],fill=78,width=2)
    for _ in range(int(width*depth/16)):
        x,z=rng.uniform(-width/2,width/2),rng.uniform(-depth/2,depth/2)
        points=[uv(x,z)]; angle=rng.uniform(0,math.tau)
        for _ in range(int(rng.integers(4,11))):
            angle+=rng.uniform(-.55,.55)
            x+=math.cos(angle)*rng.uniform(.1,.35); z+=math.sin(angle)*rng.uniform(.1,.35)
            points.append(uv(x,z))
        d.line(points,fill=(69,64,53,160),width=2)
        hd.line(points,fill=75,width=2)
    # Rubbed enamel lanes are grounded marks; training identities remain above.
    for x,z in solids:
        u,v=uv(x,z)
        rx,rz=N*2.5/width,N*1.7/depth
        d.ellipse((u-rx,v-rz,u+rx,v+rz),fill=(92,78,57,30))
        for i in range(8):
            sx=x-2+i*.52; sz=z+2.1
            d.polygon([uv(sx,sz),uv(sx+.19,sz),uv(sx+.56,sz+.65),uv(sx+.37,sz+.65)],fill=(208,155,50,150))
        for _ in range(100):
            u,v=uv(x+rng.uniform(-2.9,2.9),z+rng.uniform(-2,2.9)); r=rng.uniform(1,4)
            d.ellipse((u-r,v-r,u+r,v+r),fill=(0,0,0,0))
    for _ in range(int(width*depth/2)):
        u,v=rng.integers(0,N,2); r=rng.uniform(1,4)
        d.polygon([(u-r,v),(u,v-r),(u+r,v+r*.5)],fill=(101,93,76,65))
    # Paired broken tyre arcs and small plates break up the large open routes.
    for cx,cz in [(-width*.28,depth*.23),(width*.27,-depth*.25)]:
        for offset in [-.3,.3]:
            radius=min(width,depth)*.12+offset
            for angle in np.arange(25,170,2):
                if rng.random()<.18: continue
                t=math.radians(angle); x=cx+math.cos(t)*radius; z=cz+math.sin(t)*radius
                d.line([uv(x-.11*math.cos(t),z-.11*math.sin(t)),uv(x+.11*math.cos(t),z+.11*math.sin(t))],fill=(65,59,47,90),width=3)
    for cx,cz in [(-width*.21,-depth*.05),(width*.19,depth*.31)]:
        w,h=min(2.5,width*.21),min(1.7,depth*.22)
        corners=[uv(cx-w/2,cz-h/2),uv(cx+w/2,cz-h/2),uv(cx+w/2,cz+h/2),uv(cx-w/2,cz+h/2)]
        d.polygon(corners,fill=(106,115,113,215));d.line(corners+[corners[0]],fill=(53,59,55,225),width=4)
        hd.polygon(corners,fill=140)
        for x in np.arange(cx-w*.37,cx+w*.4,.28):
            for z in np.arange(cz-h*.30,cz+h*.32,.26):
                d.line([uv(x-.05,z-.06),uv(x+.05,z+.06)],fill=(199,179,129,155),width=2)
    im=blend(layer)
    # Fragmented wear accumulates beside equipment and along the service lanes.
    # Each patch has a soft irregular edge, with concrete showing between chips.
    layer=Image.new("RGBA",(N,N))
    patches=[(x-.5,z+2.2) for x,z in solids]
    patches += [(-width*.30,depth*.22),(width*.28,-depth*.27),
                (-width*.12,-depth*.21),(width*.23,depth*.14)]
    for cx,cz in patches:
        sx=max(48,int(N*4.8/width)); sy=max(48,int(N*3.7/depth))
        yy,xx=np.mgrid[-1:1:complex(sy),-1:1:complex(sx)]
        coarse=np.asarray(Image.fromarray((rng.random((12,16))*255).astype("uint8")).resize((sx,sy),Image.Resampling.BICUBIC),dtype=np.float32)/255
        fine=np.asarray(Image.fromarray((rng.random((64,80))*255).astype("uint8")).resize((sx,sy),Image.Resampling.BICUBIC),dtype=np.float32)/255
        edge=np.clip((1.1-np.sqrt(xx*xx+yy*yy*.85)+coarse*.30)*3,0,1)
        flecks=np.clip((fine-.47)*7,0,1)*np.clip((coarse-.23)*2,0,1)
        rgba=np.zeros((sy,sx,4),dtype=np.uint8)
        rgba[:,:,:3]=[75,69,57]; rgba[:,:,3]=(edge*flecks*105).astype("uint8")
        u,v=uv(cx,cz)
        layer.alpha_composite(Image.fromarray(rgba),(int(u-sx/2),int(v-sy/2)))
    im=blend(layer)
    # Oil spills use fragmented noise masks rather than visible circle stamps.
    layer=Image.new("RGBA",(N,N))
    for cx,cz in solids:
        size=max(48,int(N*3/min(width,depth)))
        yy,xx=np.mgrid[-1:1:complex(size),-1:1:complex(size)]
        noise=np.asarray(Image.fromarray((rng.random((32,32))*255).astype("uint8")).resize((size,size),Image.Resampling.BICUBIC),dtype=np.float32)/255-.5
        mask=np.clip((.7-np.sqrt(xx*xx+yy*yy*1.6)+noise*.9)*2,0,1)
        rgba=np.zeros((size,size,4),dtype=np.uint8);rgba[:,:,:3]=[59,57,47];rgba[:,:,3]=(mask*95).astype("uint8")
        u,v=uv(cx+1.6,cz+1.2);layer.alpha_composite(Image.fromarray(rgba),(int(u-size/2),int(v-size/2)))
    im=blend(layer)
    im.convert("RGB").save(OUT/f"{name}_floor.png")
    height=np.asarray(relief,dtype=np.float32)/255
    dy,dx=np.gradient(height)
    vector=np.dstack((-dx*3,dy*3,np.ones_like(dx)));vector/=np.linalg.norm(vector,axis=2,keepdims=True)
    Image.fromarray(np.clip((vector*.5+.5)*255,0,255).astype("uint8")).save(OUT/f"{name}_normal.png")
    print(f"MAP FLOOR BAKED: {name}, {width} x {depth} m, {N}px")
