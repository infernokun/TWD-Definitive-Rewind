"""Minimal Lua 5.2 bytecode parser / serializer for Telltale (WDC) compiled scripts.

Telltale's Lua 5.2 chunks use 4-byte ints, 4-byte size_t, 4-byte instructions and
4-byte float lua_Number (see header). This module round-trips such chunks exactly so
individual constants / instructions can be edited and the file rewritten.
"""
import struct

LUA_SIG = b'\x1bLua'
LUAC_TAIL = b'\x19\x93\r\n\x1a\n'

# ---- instruction helpers (Lua 5.2 layout: op:6 A:8 C:9 B:9) ----
OPS = ("MOVE LOADK LOADKX LOADBOOL LOADNIL GETUPVAL GETTABUP GETTABLE SETTABUP SETUPVAL "
       "SETTABLE NEWTABLE SELF ADD SUB MUL DIV MOD POW UNM NOT LEN CONCAT JMP EQ LT LE TEST "
       "TESTSET CALL TAILCALL RETURN FORLOOP FORPREP TFORCALL TFORLOOP SETLIST CLOSURE VARARG "
       "EXTRAARG").split()
OP = {name: i for i, name in enumerate(OPS)}

def ins_abc(op, a, b, c):
    return (OP[op] & 0x3f) | ((a & 0xff) << 6) | ((c & 0x1ff) << 14) | ((b & 0x1ff) << 23)

def ins_abx(op, a, bx):
    return (OP[op] & 0x3f) | ((a & 0xff) << 6) | ((bx & 0x3ffff) << 14)

def decode(ins):
    return dict(op=OPS[ins & 0x3f], A=(ins >> 6) & 0xff, C=(ins >> 14) & 0x1ff,
                B=(ins >> 23) & 0x1ff, Bx=ins >> 14)


class Reader:
    def __init__(self, data):
        self.d = data; self.p = 0
    def bytes(self, n):
        v = self.d[self.p:self.p + n]; self.p += n; return v
    def u8(self):  return self.bytes(1)[0]
    def i32(self): return struct.unpack('<i', self.bytes(4))[0]
    def u32(self): return struct.unpack('<I', self.bytes(4))[0]
    def f32(self): return struct.unpack('<f', self.bytes(4))[0]
    def string(self):
        n = self.u32()
        if n == 0: return None
        s = self.bytes(n)
        assert s[-1] == 0, 'string not NUL terminated'
        return s[:-1]  # keep raw bytes


class Writer:
    def __init__(self): self.out = bytearray()
    def bytes(self, b): self.out += b
    def u8(self, v):  self.out += bytes([v])
    def i32(self, v): self.out += struct.pack('<i', v)
    def u32(self, v): self.out += struct.pack('<I', v)
    def f32(self, v): self.out += struct.pack('<f', v)
    def string(self, s):
        if s is None: self.u32(0); return
        self.u32(len(s) + 1); self.out += s + b'\0'


def read_header(r):
    h = r.bytes(18)
    assert h[:4] == LUA_SIG and h[4] == 0x52, 'not a Lua 5.2 chunk'
    assert h[6:12] == bytes([1, 4, 4, 4, 4, 0]), 'unexpected size layout %r' % h[6:12]
    assert h[12:18] == LUAC_TAIL, 'bad LUAC_TAIL'
    return h


def read_function(r):
    f = {}
    f['line'] = r.i32(); f['lastline'] = r.i32()
    f['numparams'] = r.u8(); f['is_vararg'] = r.u8(); f['maxstack'] = r.u8()
    n = r.i32(); f['code'] = [r.u32() for _ in range(n)]
    n = r.i32(); k = []
    for _ in range(n):
        t = r.u8()
        if t == 0:   k.append(('nil', None))
        elif t == 1: k.append(('bool', bool(r.u8())))
        elif t == 3: k.append(('num', r.bytes(4)))   # keep raw float bytes: exact round trip
        elif t == 4: k.append(('str', r.string()))
        else: raise ValueError('unknown constant type %d' % t)
    f['k'] = k
    n = r.i32(); f['protos'] = [read_function(r) for _ in range(n)]
    n = r.i32(); f['upvalues'] = [r.bytes(2) for _ in range(n)]
    f['source'] = r.string()
    n = r.i32(); f['lineinfo'] = [r.i32() for _ in range(n)]
    n = r.i32(); f['locvars'] = [(r.string(), r.i32(), r.i32()) for _ in range(n)]
    n = r.i32(); f['upvalnames'] = [r.string() for _ in range(n)]
    return f


def write_function(w, f):
    w.i32(f['line']); w.i32(f['lastline'])
    w.u8(f['numparams']); w.u8(f['is_vararg']); w.u8(f['maxstack'])
    w.i32(len(f['code']))
    for ins in f['code']: w.u32(ins)
    w.i32(len(f['k']))
    for t, v in f['k']:
        if t == 'nil': w.u8(0)
        elif t == 'bool': w.u8(1); w.u8(1 if v else 0)
        elif t == 'num': w.u8(3); w.bytes(v)
        elif t == 'str': w.u8(4); w.string(v)
    w.i32(len(f['protos']))
    for p in f['protos']: write_function(w, p)
    w.i32(len(f['upvalues']))
    for u in f['upvalues']: w.bytes(u)
    w.string(f['source'])
    w.i32(len(f['lineinfo']))
    for l in f['lineinfo']: w.i32(l)
    w.i32(len(f['locvars']))
    for name, s, e in f['locvars']: w.string(name); w.i32(s); w.i32(e)
    w.i32(len(f['upvalnames']))
    for u in f['upvalnames']: w.string(u)


def load(data):
    r = Reader(data)
    header = read_header(r)
    main = read_function(r)
    assert r.p == len(data), 'trailing bytes: %d' % (len(data) - r.p)
    return header, main


def dump(header, main):
    w = Writer(); w.bytes(header); write_function(w, main); return bytes(w.out)


def walk(f, path=()):
    yield path, f
    for i, p in enumerate(f['protos']):
        yield from walk(p, path + (i,))


def const_strings(f):
    return [v for t, v in f['k'] if t == 'str']


def find_const(f, s):
    for i, (t, v) in enumerate(f['k']):
        if t == 'str' and v == s: return i
    return -1


if __name__ == '__main__':
    import sys
    for path in sys.argv[1:]:
        data = open(path, 'rb').read()
        h, m = load(data)
        out = dump(h, m)
        print('%-60s functions=%-3d roundtrip=%s' % (path, sum(1 for _ in walk(m)), 'OK' if out == data else 'MISMATCH'))
