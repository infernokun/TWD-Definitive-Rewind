"""Disassembler for Telltale Lua 5.2 bytecode (as shipped in The Walking Dead: The Telltale Definitive Series).

Usage: python luadis.py <file.lua> [filter]
Prints every function with its constants resolved. The optional filter only prints functions whose
listing contains that text. The Lua 5.1 path exists for completeness but Telltale's 5.1 games use a
shuffled opcode table, so it will not decode original Season Two scripts correctly.
"""
import sys, struct
data=open(sys.argv[1],'rb').read()
filt=sys.argv[2] if len(sys.argv)>2 else None
pos=0
def rd(n):
    global pos; v=data[pos:pos+n]; pos+=n; return v
ver=data[4]
sig=rd(4); ver=rd(1)[0]; fmt=rd(1)[0]; endian=rd(1)[0]; isz=rd(1)[0]; tsz=rd(1)[0]; insz=rd(1)[0]; nsz=rd(1)[0]; integral=rd(1)[0]
if ver==0x52: rd(6)
def rint(): return struct.unpack('<i',rd(isz))[0]
def rsz(): return struct.unpack('<I' if tsz==4 else '<Q',rd(tsz))[0]
def rstr():
    n=rsz()
    if n==0: return None
    s=rd(n); return s[:-1].decode('latin1')
def rnum():
    if integral: return rint()
    return struct.unpack('<f' if nsz==4 else '<d',rd(nsz))[0]
OPS52="MOVE LOADK LOADKX LOADBOOL LOADNIL GETUPVAL GETTABUP GETTABLE SETTABUP SETUPVAL SETTABLE NEWTABLE SELF ADD SUB MUL DIV MOD POW UNM NOT LEN CONCAT JMP EQ LT LE TEST TESTSET CALL TAILCALL RETURN FORLOOP FORPREP TFORCALL TFORLOOP SETLIST CLOSURE VARARG EXTRAARG".split()
OPS51="MOVE LOADK LOADBOOL LOADNIL GETUPVAL GETGLOBAL GETTABLE SETGLOBAL SETUPVAL SETTABLE NEWTABLE SELF ADD SUB MUL DIV MOD POW UNM NOT LEN CONCAT JMP EQ LT LE TEST TESTSET CALL TAILCALL RETURN FORLOOP FORPREP TFORLOOP SETLIST CLOSE CLOSURE VARARG".split()
OPS=OPS52 if ver==0x52 else OPS51
funcs=[]
def readfunc(name):
    f={'name':name}
    if ver==0x51:
        f['src']=rstr(); f['line']=rint(); f['lastline']=rint(); rd(1); f['np']=rd(1)[0]; rd(1); rd(1)
    else:
        f['line']=rint(); f['lastline']=rint(); f['np']=rd(1)[0]; rd(1); rd(1)
    n=rint(); f['code']=[struct.unpack('<I',rd(4))[0] for _ in range(n)]
    n=rint(); k=[]
    for _ in range(n):
        t=rd(1)[0]
        if t==0: k.append(None)
        elif t==1: k.append(bool(rd(1)[0]))
        elif t==3: k.append(rnum())
        elif t==4: k.append(rstr())
        else: raise Exception('const type %d at %d'%(t,pos))
    f['k']=k
    # find child names from CLOSURE followed by SETTABUP/SETGLOBAL
    n=rint(); f['protos']=[]
    childnames={}
    for i,ins in enumerate(f['code']):
        op=ins&0x3f; A=(ins>>6)&0xff; Bx=ins>>14
        if OPS[op]=='CLOSURE':
            nm='<anon>'
            for j in range(i+1,min(i+3,len(f['code']))):
                ins2=f['code'][j]; op2=OPS[ins2&0x3f]; A2=(ins2>>6)&0xff
                if op2=='SETGLOBAL' and A2==A: nm=k[ins2>>14]; break
                if op2=='SETTABUP':
                    B2=(ins2>>23)&0x1ff; C2=(ins2>>14)&0x1ff
                    if C2==A and B2&256: nm=k[B2-256]; break
            childnames[Bx]=nm
    for i in range(n):
        f['protos'].append(readfunc(childnames.get(i,'<anon>')))
    if ver==0x52:
        n=rint(); f['upv']=[rd(2) for _ in range(n)]
        f['src']=rstr()
    n=rint(); rd(n*isz)  # lineinfo
    n=rint(); f['locs']=[(rstr(),rint(),rint()) for _ in range(n)]
    n=rint(); f['upnames']=[rstr() for _ in range(n)]
    funcs.append(f); return f
root=readfunc('<main>')
def K(f,x):
    v=f['k'][x]; return repr(v) if isinstance(v,str) else str(v)
def RK(f,x): return K(f,x-256) if x&256 else 'R%d'%x
def dis(f):
    out=[]
    k=f['k']
    for pc,ins in enumerate(f['code']):
        op=OPS[ins&0x3f]; A=(ins>>6)&0xff; C=(ins>>14)&0x1ff; B=(ins>>23)&0x1ff; Bx=ins>>14; sBx=Bx-131071
        if op in('LOADK',): s='R%d := %s'%(A,K(f,Bx))
        elif op=='GETGLOBAL': s='R%d := G[%s]'%(A,K(f,Bx))
        elif op=='SETGLOBAL': s='G[%s] := R%d'%(K(f,Bx),A)
        elif op=='GETTABUP': s='R%d := U%d[%s]'%(A,B,RK(f,C))
        elif op=='SETTABUP': s='U%d[%s] := %s'%(A,RK(f,B),RK(f,C))
        elif op=='GETTABLE': s='R%d := R%d[%s]'%(A,B,RK(f,C))
        elif op=='SETTABLE': s='R%d[%s] := %s'%(A,RK(f,B),RK(f,C))
        elif op=='SELF': s='R%d := R%d; R%d := R%d[%s]'%(A+1,B,A,B,RK(f,C))
        elif op in('EQ','LT','LE'): s='if (%s %s %s) ~= %d then pc++'%(RK(f,B),op,RK(f,C),A)
        elif op=='TEST': s='if not R%d <=> %d then pc++'%(A,C)
        elif op=='TESTSET': s='if R%d <=> %d then R%d := R%d else pc++'%(B,C,A,B)
        elif op=='JMP': s='-> %d'%(pc+1+sBx)
        elif op in('CALL','TAILCALL'): s='R%d(%s args, %s results)'%(A,B-1 if B else 'var',C-1 if C else 'var')
        elif op=='RETURN': s='return R%d.. (%s)'%(A,B-1 if B else 'var')
        elif op=='CLOSURE': s='R%d := closure #%d (%s)'%(A,Bx,f['protos'][Bx]['name'])
        elif op=='LOADBOOL': s='R%d := %s%s'%(A,bool(B),'; pc++' if C else '')
        elif op=='MOVE': s='R%d := R%d'%(A,B)
        elif op=='GETUPVAL': s='R%d := U%d'%(A,B)
        elif op=='NOT': s='R%d := not R%d'%(A,B)
        elif op in('ADD','SUB','MUL','DIV','MOD','POW','CONCAT'): s='R%d := %s %s %s'%(A,RK(f,B),op,RK(f,C))
        elif op in('FORPREP','FORLOOP','TFORLOOP'): s='A=%d -> %d'%(A,pc+1+sBx)
        else: s='A=%d B=%d C=%d'%(A,B,C)
        out.append('  %4d %-9s %s'%(pc,op,s))
    return '\n'.join(out)
for f in funcs:
    txt=dis(f)
    hdr='==== %s  lines %d-%d  params=%d  locals=%s upnames=%s'%(f['name'],f['line'],f['lastline'],f['np'],[l[0] for l in f['locs']],f.get('upnames'))
    if filt and filt.lower() not in (hdr+txt).lower(): continue
    print(hdr); print(txt); print()
