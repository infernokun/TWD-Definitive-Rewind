"""Builds the Season 3/4 rewind pictures from the game's own textures (see src/pictures.json).

Two kinds, one per season:
- "strip" (Season 3): the picture strip of Season 3's More Options window, texture columns 156-355 of a
  512x512 DXT5 (transparent elsewhere), the layout of the stock ui_popupMoreOptions_imageEpisodeN.d3dtx.
- "background" (Season 4): the picture of the stock picture popup (Menu_PopupWindow, as used for the Crowd
  Play intro), a 1920x1080 DXT1 of which the popup shows the left part (about u 0.02-0.46), the layout of
  the stock ui_imageTelltaleCrowdPlayBackground.d3dtx.

For every source: extract it from the game archive with ttarchext and decode it (DXT1/DXT5), or read an
image file ("file", relative to pictures.json: the Season 4 scene screenshots), cut it to the picture
area, encode and write twdr_<key>.d3dtx with the header of that kind's stock texture (only the embedded
file name changes). Every written texture is decoded again and compared with its image.
Also writes TWDRewindPictures.lua (season -> kind, episode/step, label and episode -> texture name).

Usage: python -I make_pictures.py <pictures.json> <TWDRewindScenes.lua> <ttarchext.exe> <game Archives dir>
                                  <work dir> <out dir> <lua out file> [preview dir]
Needs Pillow and numpy.
"""
import io
import json
import os
import re
import struct
import subprocess
import sys

import numpy as np
from PIL import Image, ImageEnhance

FMT = {0x40: (b'DXT1', 8), 0x42: (b'DXT5', 16)}
BACKDROP = (30, 30, 30)                 # behind cut-out paintings and outside the picture area

# kind -> texture size, format, picture area (x0, x1) inside the texture
KINDS = {
    'strip': {'size': (512, 512), 'format': 0x42, 'area': (156, 356)},
    'background': {'size': (1920, 1080), 'format': 0x40, 'area': (0, 922)},
}


# ---------------------------------------------------------------------------------------------- d3dtx

def split_msv6(data):
    """6VSM: magic, u32 default size, u32 debug size, u32 async size, u32 class count, 12 bytes per class."""
    magic, dsize, dbg, asize, ncls = struct.unpack_from('<4s4I', data, 0)
    if magic != b'6VSM' or dbg != 0:
        raise ValueError('not a MetaStream v6 texture')
    hdr = 20 + 12 * ncls
    return data[:hdr], data[hdr:hdr + dsize], data[hdr + dsize:hdr + dsize + asize]


def texture_info(default):
    """Name, width, height, format and mip count from the default section."""
    blk, n = struct.unpack_from('<2I', default, 20)
    if blk != n + 8:
        raise ValueError('unexpected name block')
    name = default[28:28 + n].decode('ascii')
    i = 28 + n
    for k in range(i, i + 64):
        w, h, d, a, f = struct.unpack_from('<5I', default, k)
        if 4 <= w <= 8192 and 4 <= h <= 8192 and d == 1 and a == 1 and f in FMT:
            return name, w, h, f, struct.unpack_from('<I', default, k - 4)[0]
    raise ValueError('no surface description')


def decode(data):
    _, default, pixels = split_msv6(data)
    name, w, h, f, _ = texture_info(default)
    four, bs = FMT[f]
    size = max(1, w // 4) * max(1, h // 4) * bs
    top = pixels[-size:]                 # mips are stored smallest first
    dds = b'DDS ' + struct.pack('<7I', 124, 0x1007, h, w, size, 0, 1) + b'\0' * 44
    dds += struct.pack('<2I4s5I', 32, 4, four, 0, 0, 0, 0, 0) + struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    return Image.open(io.BytesIO(dds + top)).convert('RGBA')


def write_like(template, kind, name, dxt):
    """The kind's stock texture with another file name and pixel data."""
    head, default, pixels = split_msv6(template)
    _, w, h, f, mips = texture_info(default)
    k = KINDS[kind]
    if (w, h) != k['size'] or f != k['format'] or mips != 1 or len(pixels) != len(dxt):
        raise ValueError('%s template is not a single-mip %dx%d texture of format 0x%x' % ((kind,) + k['size'] + (k['format'],)))
    old = struct.unpack_from('<I', default, 24)[0]
    raw = name.encode('ascii')
    default = default[:20] + struct.pack('<2I', len(raw) + 8, len(raw)) + raw + default[28 + old:]
    head = head[:4] + struct.pack('<I', len(default)) + head[8:]
    return head + default + dxt


# ---------------------------------------------------------------------------------------------- DXT

def to565(c):
    c = np.clip(np.rint(c), 0, 255).astype(np.int32)
    return ((c[..., 0] >> 3) << 11) | ((c[..., 1] >> 2) << 5) | (c[..., 2] >> 3)


def from565(v):
    r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], -1).astype(np.float32)


def encode(img, fmt):
    """RGBA -> DXT1 (opaque) or DXT5 (alpha 0 or 255 per block). Colour endpoints along each block's
    principal axis, 4-colour mode."""
    a = np.asarray(img, dtype=np.float32)
    bh, bw = a.shape[0] // 4, a.shape[1] // 4
    blocks = a.reshape(bh, 4, bw, 4, 4).transpose(0, 2, 1, 3, 4).reshape(bh * bw, 16, 4)
    rgb, alpha = blocks[..., :3], blocks[..., 3]
    mean = rgb.mean(1, keepdims=True)
    cen = rgb - mean
    cov = np.einsum('nki,nkj->nij', cen, cen)
    axis = np.ones((len(rgb), 3), np.float32)
    for _ in range(8):
        axis = np.einsum('nij,nj->ni', cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    proj = np.einsum('nki,ni->nk', cen, axis)
    lo = mean[:, 0] + proj.min(1)[:, None] * axis
    hi = mean[:, 0] + proj.max(1)[:, None] * axis
    c0, c1 = to565(hi), to565(lo)
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    e0, e1 = from565(c0), from565(c1)
    pal = np.stack([e0, e1, (2 * e0 + e1) / 3, (e0 + 2 * e1) / 3], 1)
    dist = ((rgb[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)
    idx = dist.argmin(-1).astype(np.uint32)
    # DXT1 reads c0 == c1 as 3-colour mode (index 3 = transparent): use index 0 only there.
    idx[c0 == c1] = 0
    cbits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(1).astype(np.uint32)
    color = np.zeros((len(rgb), 8), np.uint8)
    color[:, 0:2] = np.stack([c0 & 255, c0 >> 8], 1)
    color[:, 2:4] = np.stack([c1 & 255, c1 >> 8], 1)
    color[:, 4:8] = cbits.view(np.uint8).reshape(-1, 4)
    if fmt == 0x40:
        return color.tobytes()
    out = np.zeros((len(rgb), 16), np.uint8)
    opaque = alpha.mean(1) >= 128                     # picture areas are block-aligned: all 0 or all 255
    out[:, 0] = np.where(opaque, 255, 0)
    out[:, 1] = out[:, 0]                             # a0 == a1: every alpha index gives the same value
    out[:, 8:16] = color
    return out.tobytes()


# ---------------------------------------------------------------------------------------------- pictures

def cut(src, opt, w, h):
    """Cut a source image into a w x h opaque picture."""
    cx, cy, zoom = opt.get('cx', 0.5), opt.get('cy', 0.5), opt.get('zoom', 1.0)
    if opt.get('fit'):
        scale = w * zoom / src.width
        im = src.resize((max(1, round(src.width * scale)), max(1, round(src.height * scale))), Image.LANCZOS)
        out = Image.new('RGBA', (w, h), BACKDROP + (255,))
        x = round(w / 2 - im.width * cx)          # cx: point of the painting at the picture's centre
        y = round(h * cy - im.height / 2)         # cy: where the painting's centre sits in the picture
        out.alpha_composite(im, dest=(max(x, 0), max(y, 0)), source=(max(-x, 0), max(-y, 0)))
    else:
        ch = src.height / zoom
        cw = ch * w / h
        if cw > src.width:
            cw = src.width
            ch = cw * h / w
        x0 = min(max(0.0, src.width * cx - cw / 2), src.width - cw)
        y0 = min(max(0.0, src.height * cy - ch / 2), src.height - ch)
        crop = src.crop((round(x0), round(y0), round(x0 + cw), round(y0 + ch)))
        out = Image.alpha_composite(Image.new('RGBA', crop.size, BACKDROP + (255,)), crop)
        out = out.resize((w, h), Image.LANCZOS)
    out = out.convert('RGB')
    if opt.get('bright'):
        out = ImageEnhance.Brightness(out).enhance(opt['bright'])
    return out


def texture_image(kind, picture):
    k = KINDS[kind]
    tw, th = k['size']
    x0, _ = k['area']
    if k['format'] == 0x42:
        img = Image.new('RGBA', (tw, th), (0, 0, 0, 0))
    else:
        img = Image.new('RGBA', (tw, th), BACKDROP + (255,))
    img.paste(picture.convert('RGBA'), (x0, 0))
    return img


def extract(ttarchext, archives, work, archive, name):
    out = os.path.join(work, os.path.splitext(archive)[0])
    path = os.path.join(out, name)
    if not os.path.exists(path):
        os.makedirs(out, exist_ok=True)
        subprocess.run([ttarchext, '-o', '-f', name, '67', os.path.join(archives, archive), out],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(path):
        raise SystemExit('could not extract %s from %s' % (name, archive))
    return path


def tex_name(key):
    return 'twdr_%s.d3dtx' % key


def lua_string(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    (cfg_path, scenes_path, ttarchext, archives, work, out_dir, lua_out) = sys.argv[1:8]
    preview = sys.argv[8] if len(sys.argv) > 8 else None
    cfg = json.load(open(cfg_path, encoding='utf-8'))
    for d in (work, out_dir) + ((preview,) if preview else ()):
        os.makedirs(d, exist_ok=True)

    # Every label in the mapping must exist in the scene table of that season, every step in its episode.
    known, count, season, ep = {}, {}, None, None
    for line in open(scenes_path, encoding='utf-8').read().splitlines():
        m = re.match(r'\s{4}\[(\d)\] = \{', line)
        if m:
            season, ep = m.group(1), None
            known.setdefault(season, set())
        m = re.match(r'\s{8}\[(\d+)\] = \{', line)
        if m and season:
            ep = m.group(1)
        m = re.search(r'label = "((?:[^"\\]|\\.)*)"', line)
        if m and season:
            known[season].add(m.group(1))
            if ep:
                count[(season, ep)] = count.get((season, ep), 0) + 1
    kind_of = {}
    for s, sc in cfg['seasons'].items():
        if sc['kind'] not in KINDS:
            raise SystemExit('season %s: unknown kind "%s"' % (s, sc['kind']))
        steps = sc.get('steps', {})
        keys = list(sc['labels'].values()) + [k for k in sc['episodes'].values() if not k.startswith('@')]
        for ep, per in steps.items():
            for step, key in per.items():
                if not 1 <= int(step) <= count.get((s, ep), 0):
                    raise SystemExit('season %s episode %s: no scene table entry %s' % (s, ep, step))
                keys.append(key)
        for label in sc['labels']:
            if label not in known.get(s, ()):
                raise SystemExit('season %s: no scene labelled "%s"' % (s, label))
        for key in keys:
            if key not in cfg['sources']:
                raise SystemExit('season %s: unknown picture "%s"' % (s, key))
            if kind_of.setdefault(key, sc['kind']) != sc['kind']:
                raise SystemExit('picture "%s" is used as two kinds' % key)

    templates = {}
    for kind, t in cfg['templates'].items():
        templates[kind] = open(extract(ttarchext, archives, work, t['archive'], t['file']), 'rb').read()

    worst = {}
    for key in sorted(kind_of):
        kind, opt, k = kind_of[key], cfg['sources'][key], KINDS[kind_of[key]]
        x0, x1 = k['area']
        if 'file' in opt:
            src = Image.open(os.path.join(os.path.dirname(os.path.abspath(cfg_path)), opt['file'])).convert('RGBA')
        else:
            src = decode(open(extract(ttarchext, archives, work, opt['archive'], opt['texture']), 'rb').read())
        img = texture_image(kind, cut(src, opt, x1 - x0, k['size'][1]))
        data = write_like(templates[kind], kind, tex_name(key), encode(img, k['format']))
        open(os.path.join(out_dir, tex_name(key)), 'wb').write(data)
        # Read the texture back: header must parse, pixels must match what was encoded.
        back = decode(data)
        name, w, h, f, mips = texture_info(split_msv6(data)[1])
        if name != tex_name(key) or (w, h) != k['size'] or f != k['format'] or mips != 1:
            raise SystemExit('bad header in %s' % name)
        a, b = np.asarray(img, np.float32), np.asarray(back, np.float32)
        if not np.array_equal(a[..., 3], b[..., 3]):
            raise SystemExit('alpha mismatch in %s' % name)
        mse = ((a[..., :3] - b[..., :3]) ** 2)[:, x0:x1].mean()
        psnr = 10 * np.log10(255 ** 2 / max(mse, 1e-6))
        worst[kind] = min(worst.get(kind, 99.0), psnr)
        if psnr < 26:
            raise SystemExit('%s: round trip too lossy (%.1f dB)' % (name, psnr))
        if preview:
            back.crop((x0, 0, x1, k['size'][1])).convert('RGB').save(os.path.join(preview, key + '.png'))
    for kind in sorted(worst):
        print('   %d %s pictures, worst round trip %.1f dB'
              % (sum(1 for v in kind_of.values() if v == kind), kind, worst[kind]))

    lines = ['-- Generated by tools/make_pictures.py from src/pictures.json. Do not edit.',
             '-- TWDRewindPictures[season]: kind ("strip": Season 3 More Options window; "background": the stock',
             '-- picture popup), steps[ep][scene table entry] / labels[scene table label] / episodes[ep] -> texture.',
             'TWDRewindPictures = {']
    for s in sorted(cfg['seasons'], key=int):
        sc = cfg['seasons'][s]
        lines.append('    [%s] = {' % s)
        lines.append('        kind = %s,' % lua_string(sc['kind']))
        lines.append('        episodes = {')
        for ep in sorted(sc['episodes'], key=int):
            k = sc['episodes'][ep]
            lines.append('            [%s] = %s,' % (ep, lua_string(k[1:] if k.startswith('@') else tex_name(k))))
        lines.append('        },')
        lines.append('        steps = {')
        for ep in sorted(sc.get('steps', {}), key=int):
            per = sc['steps'][ep]
            lines.append('            [%s] = {' % ep)
            for step in sorted(per, key=int):
                lines.append('                [%s] = %s,' % (step, lua_string(tex_name(per[step]))))
            lines.append('            },')
        lines.append('        },')
        lines.append('        labels = {')
        for label in sorted(sc['labels']):
            lines.append('            [%s] = %s,' % (lua_string(label), lua_string(tex_name(sc['labels'][label]))))
        lines.append('        },')
        lines.append('    },')
    lines.append('}')
    open(lua_out, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
