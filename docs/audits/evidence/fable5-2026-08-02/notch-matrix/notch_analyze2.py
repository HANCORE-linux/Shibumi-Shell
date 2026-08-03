#!/usr/bin/env python3
"""Notch continuity v2: difference-image silhouette + border-line inspection.

mask = |shot - reference| > DIFF_T  (bar-free reference of the same strip)
Per column outer-edge y => silhouette profile. Checks:
  1. in-span gaps (columns without bar pixels)
  2. step continuity of the outer edge (<= STEP_LIMIT px/column)
  3. left/right shoulder mirror symmetry
  4. shoulder-shape invariance across spacing modes
  5. border line: luminance sampled just inside the outer edge along the whole
     span; report contiguous dark runs (potential outline interruptions)
"""
import json
import numpy as np
from PIL import Image

DIFF_T = 25
STEP_LIMIT = 4

ref = {p: np.array(Image.open(f'notch2/ref-{p}-strip.png').convert('L'), dtype=np.int16)
       for p in ('top', 'bottom')}

def analyze(pos, mode, pad):
    a = np.array(Image.open(f'notch2/{pos}-{mode}-{pad}.png').convert('L'), dtype=np.int16)
    d = np.abs(a - ref[pos])
    mask = d > DIFF_T
    h, w = mask.shape
    p = np.full(w, -1, dtype=int)
    for x in range(w):
        col = np.nonzero(mask[:, x])[0]
        if col.size:
            p[x] = col.max() if pos == 'top' else col.min()
    cols = np.nonzero(p >= 0)[0]
    xmin, xmax = int(cols.min()), int(cols.max())
    span = p[xmin:xmax + 1]
    gaps = [int(x) for x in range(xmin, xmax + 1) if p[x] < 0]
    steps = np.abs(np.diff(span))
    big = [(int(xmin + i), int(steps[i])) for i in np.nonzero(steps > STEP_LIMIT)[0]]
    n = min(60, len(span) // 2)
    L = span[:n].astype(float)
    R = span[-n:][::-1].astype(float)
    sym = float(np.abs(L - R).max())
    # border-line luminance just inside the outer edge (2 px inward)
    lum = []
    for x in range(xmin, xmax + 1):
        y = p[x]
        yy = max(0, y - 2) if pos == 'top' else min(h - 1, y + 2)
        lum.append(int(a[yy, x]))
    lum = np.array(lum)
    dark = lum < 40  # below border brightness band
    runs, s = [], None
    for i, v in enumerate(dark):
        if v and s is None:
            s = i
        elif not v and s is not None:
            if i - s >= 4:
                runs.append((int(xmin + s), int(i - s)))
            s = None
    if s is not None and len(dark) - s >= 4:
        runs.append((int(xmin + s), int(len(dark) - s)))
    return dict(img=f'{pos}-{mode}-{pad}', xmin=xmin, xmax=xmax,
                gaps=len(gaps), gap_cols=gaps[:8],
                max_step=int(steps.max()), big_steps=big[:8],
                shoulder_sym=sym,
                border_lum_min=int(lum.min()), border_lum_mean=round(float(lum.mean()), 1),
                dark_runs=runs[:8],
                shoulder=[int(v) for v in span[:24]])

results = []
for pos in ('top', 'bottom'):
    for mode in ('text', 'icon'):
        for pad in ('auto', 'none', 'compact', 'roomy'):
            results.append(analyze(pos, mode, pad))
for r in results:
    print(json.dumps(r))

print('\n== spacing invariance of shoulder shape ==')
for pos in ('top', 'bottom'):
    for mode in ('text', 'icon'):
        shapes = {r['img'].split('-')[2]: r['shoulder'] for r in results
                  if r['img'].startswith(f'{pos}-{mode}-')}
        ref_s = shapes['auto']
        base_r = ref_s[0]
        for pad_, s in shapes.items():
            d = max(abs((a - s[0]) - (b - base_r)) for a, b in zip(s, ref_s))
            print(f'{pos}-{mode} {pad_}: shoulder maxdiff vs auto = {d}')
