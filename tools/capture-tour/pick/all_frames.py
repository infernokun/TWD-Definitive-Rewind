"""Every frame of one scene folder, labelled with its file name. Usage: python -I all_frames.py <folder> <out.jpg>"""
import sys, os, glob
from PIL import Image, ImageDraw, ImageFont

src, out = sys.argv[1], sys.argv[2]
shots = sorted(glob.glob(os.path.join(src, '*.jpg')))
cols, w, h, lh = 6, 213, 120, 16
rows = (len(shots) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * (h + lh)), (35, 35, 35))
dr = ImageDraw.Draw(sheet)
font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 12)
for i, p in enumerate(shots):
    x, y = (i % cols) * w, (i // cols) * (h + lh)
    im = Image.open(p).convert('RGB')
    im.thumbnail((w - 2, h))
    sheet.paste(im, (x + 1, y + lh))
    dr.text((x + 3, y + 1), os.path.splitext(os.path.basename(p))[0], font=font, fill=(140, 220, 255))
sheet.save(out, quality=85)
