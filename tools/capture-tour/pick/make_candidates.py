"""Copies the 5 ranked picks per scene to <out>\\S4\\<scene>\\<rank> <time>.jpg and draws one review
sheet per episode (<out>\\E<n> candidates.jpg). The box on each thumb is the centre crop that fits the
Season 4 picture area (922x1080 of the texture).
Usage: python -I make_candidates.py <captures\\S4> <shortlist.json> <picks.json> <out>"""
import sys, os, json, shutil
from PIL import Image, ImageDraw, ImageFont

src, short_path, picks_path, out = sys.argv[1:5]
short = json.load(open(short_path))
picks = json.load(open(picks_path, encoding='utf-8'))
LETTERS = 'ABCDEFGHIJKL'
CROP = (922 / 1080) / (16 / 9)

chosen = {}
for scene, sel in picks.items():
    if isinstance(sel, str):
        files = [short[scene][LETTERS.index(c)] for c in sel]
    else:
        files = [os.path.join(src, scene, t + '.jpg') for t in sel]
    assert len(files) == 5 and len(set(files)) == 5, scene
    dst = os.path.join(out, 'S4', scene)
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    chosen[scene] = []
    for rank, f in enumerate(files, 1):
        assert os.path.isfile(f), f
        name = '%d  %s' % (rank, os.path.basename(f))
        shutil.copy2(f, os.path.join(dst, name))
        chosen[scene].append(os.path.join(dst, name))

w, h, lh = 256, 144, 20
font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 14)
small = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 12)
for ep in sorted({k.split('\\')[0] for k in chosen}):
    scenes = [k for k in chosen if k.startswith(ep + '\\')]
    sheet = Image.new('RGB', (5 * w, len(scenes) * (h + lh)), (30, 30, 30))
    dr = ImageDraw.Draw(sheet)
    for r, scene in enumerate(scenes):
        y = r * (h + lh)
        dr.text((4, y + 2), scene.replace('\\', '  '), font=font, fill=(255, 220, 0))
        for c, f in enumerate(chosen[scene]):
            im = Image.open(f).convert('RGB').resize((w - 4, h - 2))
            x = c * w + 2
            sheet.paste(im, (x, y + lh))
            cw = (w - 4) * CROP
            x0 = x + ((w - 4) - cw) / 2
            dr.rectangle([x0, y + lh, x0 + cw, y + lh + h - 3], outline=(255, 255, 255), width=1)
            dr.text((x + 4, y + lh + 2), str(c + 1), font=small, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
    sheet.save(os.path.join(out, '%s candidates.jpg' % ep), quality=88)
print(len(chosen), 'scenes,', 5 * len(chosen), 'candidates ->', out)
