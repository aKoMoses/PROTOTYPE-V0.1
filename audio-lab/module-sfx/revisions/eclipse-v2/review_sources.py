from design import ROOT,SR,CUES
from prepare import read,rms,natural_grain
import numpy as np
for c in CUES:
 x=read(ROOT/"raw"/(c["id"]+".wav"))
 n=round(.05*SR)
 values=[rms(x[i:i+n]) for i in range(0,len(x),n)]
 peak=max(values)
 region,start,end,main=natural_grain(x,c)
 print(c["id"],"grain",round(start/SR,2),round(end/SR,2),"rms",round(rms(region),4),"events",[(round(i*.05,2),round(v,3)) for i,v in enumerate(values) if v>max(.015,peak*.2)])
