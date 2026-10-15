#!/usr/bin/env python3
# Jet axis against the shadow centre, in px. Needs numpy and pillow, e.g.
#   uv run --with numpy --with pillow python scripts/jet-achse.py jet.png schatten.png <holeX px> <holeY px>
# jet.png: snapshot with --debug 5 (jet light alone), schatten.png: the same scene with --debug 1 (blue = captured).
import sys, numpy as np
from PIL import Image
j = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(float).sum(2)
n = 255 - np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(float)[:,:,2]  # debug 1: blue = captured
hx, hy = float(sys.argv[3]), float(sys.argv[4])
H, W = n.shape
# shadow: dark connected blob around hole
y0, y1 = int(hy-300), int(hy+300); x0, x1 = int(hx-300), int(hx+300)
y0=max(y0,0); x0=max(x0,0); y1=min(y1,H); x1=min(x1,W)
sub = n[y0:y1, x0:x1] < 12
from collections import deque
seen = np.zeros_like(sub); q = deque([(int(hy)-y0, int(hx)-x0)])
# start: nearest dark pixel to the hole centre
ys, xs = np.nonzero(sub); k = np.argmin((ys-(hy-y0))**2+(xs-(hx-x0))**2); q = deque([(ys[k], xs[k])]); seen[ys[k], xs[k]] = 1
while q:
    a, b = q.popleft()
    for da, db in ((1,0),(-1,0),(0,1),(0,-1)):
        u, v = a+da, b+db
        if 0<=u<sub.shape[0] and 0<=v<sub.shape[1] and sub[u,v] and not seen[u,v]:
            seen[u,v]=1; q.append((u,v))
ys, xs = np.nonzero(seen)
sx = (xs.min()+xs.max())/2 + x0 + 0.5; sy = (ys.min()+ys.max())/2 + y0 + 0.5
R = (xs.max()-xs.min()+1)/2
# row through the shadow middle: centre of the dark run
print(f"hole ({hx:.1f},{hy:.1f})  shadow bbox centre ({sx:.1f},{sy:.1f}) radius_x {R:.1f}  -> shadow-hole dx {sx-hx:+.1f} dy {sy-hy:+.1f}")
def axis(rows):
    out=[]
    for r in rows:
        if r<0 or r>=H: continue
        row = j[r, int(hx-R*1.5):int(hx+R*1.5)]
        row = np.clip(row - np.percentile(row, 20), 0, None)
        if row.sum() < 50: continue
        xsr = np.arange(len(row)) + int(hx-R*1.5) + 0.5
        # centre of the half-maximum span (robust to filaments)
        m = row.max(); idx = np.nonzero(row >= 0.5*m)[0]
        out.append(((xsr[idx[0]]+xsr[idx[-1]])/2, (row*xsr).sum()/row.sum(), (idx[-1]-idx[0]+1)))
    return np.array(out)
for name, lo, hi in (("jet base  1.0-1.6R above", -1.6, -1.0), ("jet mid   2-4R above", -4, -2), ("jet far   5-8R above", -8, -5),
                     ("cjet base 1.0-1.6R below", 1.0, 1.6), ("cjet mid  2-4R below", 2, 4)):
    a = axis(range(int(sy+lo*R), int(sy+hi*R)))
    if len(a)==0: print(name, "none"); continue
    print(f"{name}: half-max centre {np.median(a[:,0])-sx:+.1f} px from shadow, {np.median(a[:,0])-hx:+.1f} from hole; centroid {np.median(a[:,1])-sx:+.1f}; FWHM {np.median(a[:,2]):.0f}")
