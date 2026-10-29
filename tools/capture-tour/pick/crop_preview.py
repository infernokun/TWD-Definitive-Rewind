"""Renders the Season 4 pictures as make_pictures.cut makes them (922x1080), side by side.
Usage: python -I crop_preview.py <tools dir> <choice.json> <crops.json> <out.jpg>"""
import sys, json
sys.path.insert(0, sys.argv[1])
from make_pictures import cut
from PIL import Image, ImageDraw, ImageFont

choice, crops, out = json.load(open(sys.argv[2], encoding='utf-8-sig')), json.load(open(sys.argv[3])), sys.argv[4]
w, h, lh, cols = 230, 270, 20, 7
keys = list(crops)
rows = (len(keys) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * (h + lh)), (30, 30, 30))
dr = ImageDraw.Draw(sheet)
font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', 13)
for i, k in enumerate(keys):
    pic = cut(Image.open(choice[k]).convert('RGBA'), crops[k], 922, 1080).resize((w - 6, h - 4), Image.LANCZOS)
    x, y = (i % cols) * w, (i // cols) * (h + lh)
    sheet.paste(pic, (x + 3, y + lh))
    dr.text((x + 4, y + 2), k, font=font, fill=(255, 220, 0))
sheet.save(out, quality=90)
