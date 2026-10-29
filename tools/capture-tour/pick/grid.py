"""Frames with a 10% grid, two per row, labelled. Usage: python -I grid.py <out.jpg> <label=path> ..."""
import sys
from PIL import Image, ImageDraw, ImageFont

out, items = sys.argv[1], [a.split('=', 1) for a in sys.argv[2:]]
w, h, lh = 640, 360, 20
cols = 2
rows = (len(items) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * (h + lh)), (30, 30, 30))
dr = ImageDraw.Draw(sheet)
font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 14)
for i, (label, p) in enumerate(items):
    x, y = (i % cols) * w, (i // cols) * (h + lh)
    im = Image.open(p).convert('RGB').resize((w - 4, h - 2))
    g = ImageDraw.Draw(im)
    for k in range(1, 10):
        g.line([(k * (w - 4) / 10, 0), (k * (w - 4) / 10, h)], fill=(0, 255, 255) if k == 5 else (255, 255, 0), width=1)
        g.line([(0, k * (h - 2) / 10), (w, k * (h - 2) / 10)], fill=(255, 255, 0), width=1)
    sheet.paste(im, (x + 2, y + lh))
    dr.text((x + 4, y + 2), label, font=font, fill=(255, 220, 0))
sheet.save(out, quality=88)
