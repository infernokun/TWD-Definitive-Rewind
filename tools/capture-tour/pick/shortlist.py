"""Shortlists up to 12 varied, sharp, lit frames per scene folder and draws review sheets.
Usage: python -I shortlist.py <captures\\S4> <out dir>
Writes <out>\\sheet_NN.jpg (3 scenes each, thumbs lettered A-L) and <out>\\shortlist.json."""
import sys, os, glob, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
N, COLS, TW, TH, LH = 12, 4, 320, 180, 20
LETTERS = 'ABCDEFGHIJKL'

def metrics(path):
    im = Image.open(path).convert('L').resize((320, 180), Image.BILINEAR)
    a = np.asarray(im, dtype=np.float32)
    lap = a[1:-1, 1:-1] * 4 - a[:-2, 1:-1] - a[2:, 1:-1] - a[1:-1, :-2] - a[1:-1, 2:]
    small = np.asarray(im.resize((9, 8), Image.BILINEAR), dtype=np.float32)
    dhash = (small[:, 1:] > small[:, :-1]).flatten()
    return a.mean(), a.std(), lap.var(), dhash

scenes = sorted(d for d in glob.glob(os.path.join(src, 'E*', '*')) if os.path.isdir(d))
short = {}
for d in scenes:
    shots = sorted(glob.glob(os.path.join(d, '*.jpg')))[2:]        # skip the fade-in
    m = [(p,) + metrics(p) for p in shots]
    for min_luma, min_std in ((22, 12), (10, 6)):                  # night scenes: a lower bar
        rows = [(np.log1p(lapv) + std / 25 + min(luma, 90) / 30, p, h)
                for p, luma, std, lapv, h in m if luma >= min_luma and std >= min_std]
        if len(rows) >= 8:
            break
    rows.sort(key=lambda r: -r[0])
    picked = []
    for thresh in (14, 9, 5):                                      # relax if the scene is samey
        for r in rows:
            if len(picked) >= N:
                break
            if r in picked:
                continue
            if all(np.count_nonzero(r[2] != q[2]) > thresh for q in picked):
                picked.append(r)
    picked.sort(key=lambda r: r[1])                                # back in time order
    key = os.path.relpath(d, src)
    short[key] = [r[1] for r in picked]

font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 15)
keys = list(short)
for s in range(0, len(keys), 3):
    group = keys[s:s + 3]
    rows_per = (N + COLS - 1) // COLS
    block = LH + rows_per * (TH + LH)
    sheet = Image.new('RGB', (COLS * TW, block * len(group)), (35, 35, 35))
    dr = ImageDraw.Draw(sheet)
    for g, key in enumerate(group):
        y0 = g * block
        dr.text((4, y0 + 1), key, font=font, fill=(255, 220, 0))
        for i, p in enumerate(short[key]):
            x, y = (i % COLS) * TW, y0 + LH + (i // COLS) * (TH + LH)
            im = Image.open(p).convert('RGB')
            im.thumbnail((TW - 4, TH))
            sheet.paste(im, (x + 2, y + LH))
            dr.text((x + 4, y + 1), '%s  %s' % (LETTERS[i], os.path.splitext(os.path.basename(p))[0]), font=font, fill=(140, 220, 255))
    sheet.save(os.path.join(out, 'sheet_%02d.jpg' % (s // 3 + 1)), quality=85)
json.dump(short, open(os.path.join(out, 'shortlist.json'), 'w'), indent=1)
print(len(keys), 'scenes,', sum(len(v) for v in short.values()), 'frames shortlisted,', (len(keys) + 2) // 3, 'sheets')
for k, v in short.items():
    if len(v) < 8:
        print('  only', len(v), 'usable in', k)
