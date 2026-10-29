"""One row per scene folder: frames at about 5 s, 20 s, 35 s and 50 s into the scene.
Usage: python -I scene_sheet.py <episode folder> <out.jpg>"""
import sys, os, glob
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
w, h, label_h = 320, 180, 18
picks = (5, 20, 35, 50)
dirs = sorted(d for d in glob.glob(os.path.join(src, '*')) if os.path.isdir(d))
sheet = Image.new('RGB', (w * len(picks), len(dirs) * (h + label_h)), (40, 40, 40))
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 13)
for r, d in enumerate(dirs):
    shots = sorted(glob.glob(os.path.join(d, '*.jpg')))
    y = r * (h + label_h)
    draw.text((4, y + 1), f'{os.path.basename(d)}  ({len(shots)} shots)', font=font, fill=(255, 220, 0))
    for c, k in enumerate(picks):
        if not shots:
            break
        im = Image.open(shots[min(k, len(shots) - 1)]).convert('RGB')
        im.thumbnail((w, h))
        sheet.paste(im, (c * w, y + label_h))
sheet.save(out, quality=85)
print(len(dirs), 'scenes ->', out)
