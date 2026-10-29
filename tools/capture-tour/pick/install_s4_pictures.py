"""Copies the chosen Season 4 shots into the repo (1920x1080 JPEG) and rewrites the Season 4 part of
pictures.json: one source per scene table entry, seasons.4.steps, and no label pictures.
Usage: python -I install_s4_pictures.py <choice.json> <crops.json> <repo src dir>"""
import sys, os, re, json
from PIL import Image

choice = json.load(open(sys.argv[1], encoding='utf-8-sig'))
crops = json.load(open(sys.argv[2], encoding='utf-8-sig'))
src = sys.argv[3]
out = os.path.join(src, 'pictures', 's4')
os.makedirs(out, exist_ok=True)

lines, steps = [], {}
for k in sorted(choice):
    ep, step = re.match(r'E(\d) (\d\d)$', k).groups()
    name = 'e%s_%s.jpg' % (ep, step)
    Image.open(choice[k]).convert('RGB').resize((1920, 1080), Image.LANCZOS).save(os.path.join(out, name), quality=90)
    key = 's4e%s_%s' % (ep, step)
    opt = {'file': 'pictures/s4/' + name}
    opt.update(crops[k])
    body = ', '.join('"%s": %s' % (o, json.dumps(v)) for o, v in opt.items())
    lines.append('        %-20s { %s },' % ('"%s":' % key, body))
    steps.setdefault(ep, []).append('"%d": "%s"' % (int(step), key))

path = os.path.join(src, 'pictures.json')
text = open(path, encoding='utf-8').read()
# Sources: the episode key art stays, the location paintings go, the shots come in after the key art.
text = re.sub(r'(        "s4_ep4":[^\n]*\n)(?:        "s4_[^\n]*\n)*', lambda m: m.group(1) + '\n'.join(lines) + '\n', text)
step_block = '            "steps": {\n' + ',\n'.join(
    '                "%s": { %s }' % (ep, ', '.join(steps[ep])) for ep in sorted(steps)) + '\n            },\n'
text = re.sub(r'(        "4": \{\n            "kind": "background",\n            "episodes": [^\n]*\n)            "labels": \{.*?\n            \}\n',
              lambda m: m.group(1) + step_block + '            "labels": {}\n', text, flags=re.S)
json.loads(text)
open(path, 'w', encoding='utf-8', newline='\n').write(text)
print(len(lines), 'shots ->', out)
print(sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out)) / 2**20, 'MB')
