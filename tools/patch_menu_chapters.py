"""Restore chapter rewind in The Walking Dead: The Telltale Definitive Series (Season 2).

Applies four edits to the compiled MenuSeason2 script Menu_chapters.lua:
  1. Menu_Chapters_RewindIsSupported(): `return false` -> `return true`
     (the chapter list only builds per-chapter rewind panels when this is true)
  2. The local popup function that TTDS changed to "Restart Episode" ->
     original behaviour: Popup('popup_rewind_header','popup_rewind_message',
                               'Menu_Chapters_Replay()','label_ok')
  3. Nav-help label for a chapter panel: 'navhelp_restart' -> 'navhelp_rewind'
  4. pcall(require, "TWDRewind_S2.lua") ahead of the script's own requires, which replaces the
     save-file copy (Season 2's Menu_Main.lua does not load DebugLoader.lua)
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from luapatch52 import load, dump, walk, decode, ins_abc, ins_abx, find_const, OP

src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
header, main = load(data)
funcs = {path: f for path, f in walk(main)}

def one(pred, what):
    hits = [(p, f) for p, f in funcs.items() if pred(f)]
    assert len(hits) == 1, '%s: expected exactly one match, got %d' % (what, len(hits))
    return hits[0]

# ---- 1. RewindIsSupported stub ----------------------------------------------
def is_stub(f):
    return (len(f['code']) == 3 and not f['k'] and not f['protos']
            and decode(f['code'][0])['op'] == 'LOADBOOL' and decode(f['code'][0])['B'] == 0
            and f['line'] == 1054)
path, f = one(is_stub, 'RewindIsSupported')
f['code'][0] = ins_abc('LOADBOOL', 0, 1, 0)        # R0 := true
print('[1] RewindIsSupported stub at proto %s lines %d-%d: now returns true' % (path, f['line'], f['lastline']))

# ---- 2. Restart popup -> rewind popup ---------------------------------------
def is_restart_popup(f):
    return (find_const(f, b'popup_restart_header') >= 0 and find_const(f, b'Menu_Chapters_NewStart()') >= 0
            and f['line'] == 112)
path, f = one(is_restart_popup, 'restart popup')
k = f['k']
for old, new in ((b'popup_restart_header', b'popup_rewind_header'),
                 (b'popup_restart_message', b'popup_rewind_message'),
                 (b'Menu_Chapters_NewStart()', b'Menu_Chapters_Replay()')):
    i = find_const(f, old); k[i] = ('str', new)
k.append(('str', b'label_ok')); k_ok = len(k) - 1
# code: ... LOADK R3 := 'Menu_Chapters_NewStart()' ; CALL R0(3 args) ; RETURN
calls = [i for i, ins in enumerate(f['code']) if decode(ins)['op'] == 'CALL']
assert len(calls) == 1, calls
ci = calls[0]; c = decode(f['code'][ci])
assert c['A'] == 0 and c['B'] == 4, c                 # Popup(h, m, fn)  -> 3 args
f['code'].insert(ci, ins_abx('LOADK', 4, k_ok))      # R4 := 'label_ok'
f['lineinfo'].insert(ci, f['lineinfo'][ci])
f['code'][ci + 1] = ins_abc('CALL', 0, 5, 1)         # Popup(h, m, fn, 'label_ok')
f['maxstack'] = max(f['maxstack'], 5)
print('[2] popup function at proto %s lines %d-%d: restart popup -> rewind popup + Menu_Chapters_Replay()' % (path, f['line'], f['lastline']))

# ---- 3. nav-help label -------------------------------------------------------
def is_navhelp(f):
    return find_const(f, b'navhelp_restart') >= 0 and f['line'] == 1086
path, f = one(is_navhelp, 'navhelp')
i = find_const(f, b'navhelp_restart'); f['k'][i] = ('str', b'navhelp_rewind')
print('[3] nav-help function at proto %s lines %d-%d: navhelp_restart -> navhelp_rewind' % (path, f['line'], f['lastline']))

# ---- 4. load TWDRewind_S2.lua ------------------------------------------------
k = main['k']
i_req = find_const(main, b'require')
assert i_req >= 0, 'require constant'
i_pcall = find_const(main, b'pcall')
if i_pcall < 0:
    k.append(('str', b'pcall')); i_pcall = len(k) - 1
k.append(('str', b'TWDRewind_S2.lua')); i_file = len(k) - 1
assert i_pcall < 256 and i_req < 256, 'constants must fit an RK operand'
first = decode(main['code'][0])
assert first['op'] == 'GETTABUP' and first['B'] == 0 and first['C'] == 256 + i_req, first   # require(...)
guard = [ins_abc('GETTABUP', 0, 0, 256 + i_pcall),    # R0 := _ENV.pcall
         ins_abc('GETTABUP', 1, 0, 256 + i_req),      # R1 := _ENV.require
         ins_abx('LOADK', 2, i_file),                 # R2 := 'TWDRewind_S2.lua'
         ins_abc('CALL', 0, 3, 1)]                    # pcall(require, 'TWDRewind_S2.lua')
main['code'][0:0] = guard
if main['lineinfo']:
    main['lineinfo'][0:0] = [main['lineinfo'][0]] * len(guard)
main['maxstack'] = max(main['maxstack'], 3)
print('[4] main chunk: pcall(require, "TWDRewind_S2.lua") ahead of its requires')

out = dump(header, main)
open(dst, 'wb').write(out)
print('wrote %s (%d bytes, original %d bytes)' % (dst, len(out), len(data)))
# self-check: reload
load(out)
print('reparse OK')
