"""Find code that refers to a string by RIP-relative displacement (lea/mov reg, [rip+disp32]).
Usage: python -I find_riprefs.py <exe> name [name ...]
Prints, per name, the virtual address of each instruction-end candidate and the bytes before it."""
import struct, sys

data = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', data, 0x3C)[0]
nsec = struct.unpack_from('<H', data, pe + 6)[0]
optsize = struct.unpack_from('<H', data, pe + 20)[0]
base = struct.unpack_from('<Q', data, pe + 24 + 24)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + optsize + 40 * i
    name = data[o:o + 8].rstrip(b'\0').decode()
    vsize, rva, rsize, raw = struct.unpack_from('<4I', data, o + 8)
    secs.append((name, rva, vsize, raw, rsize))


def off2rva(off):
    for n, rva, vs, raw, rs in secs:
        if raw <= off < raw + rs:
            return rva + off - raw
    return None


text = [s for s in secs if s[0] == '.text'][0]
_, trva, tvs, traw, trs = text
code = data[traw:traw + trs]
import numpy as np
disp = np.frombuffer(code[: (len(code) // 4) * 4 + 0], dtype='<i4')  # aligned only; do all 4 phases below

for name in sys.argv[2:]:
    pat = b'\0' + name.encode() + b'\0'
    i = data.find(pat)
    hits = []
    while i >= 0:
        hits.append(off2rva(i + 1))
        i = data.find(pat, i + 1)
    print('==', name, ['0x%x' % (base + h) for h in hits if h])
    for srva in hits:
        if srva is None:
            continue
        arr = np.frombuffer(code, dtype=np.uint8)
        for phase in range(4):
            n = (len(code) - phase) // 4
            d = np.frombuffer(code[phase:phase + n * 4], dtype='<i4').astype(np.int64)
            pos = np.arange(n, dtype=np.int64) * 4 + phase          # offset of disp within .text
            end = trva + pos + 4                                      # rva of instruction end (if disp is last)
            idx = np.nonzero(end + d == srva)[0]
            for k in idx:
                p = int(pos[k])
                pre = code[max(0, p - 3):p]
                print('   insn end 0x%x  bytes before disp: %s' % (base + trva + p + 4, pre.hex()))
