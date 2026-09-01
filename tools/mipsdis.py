#!/usr/bin/env python3
"""Word-at-a-time MIPS-I + COP2/GTE disassembler (capstone stops at GTE ops)."""
import struct, sys
from capstone import Cs, CS_ARCH_MIPS, CS_MODE_MIPS32, CS_MODE_LITTLE_ENDIAN
md = Cs(CS_ARCH_MIPS, CS_MODE_MIPS32|CS_MODE_LITTLE_ENDIAN)
GTE = {0x01:'RTPS',0x06:'NCLIP',0x0C:'OP',0x10:'DPCS',0x11:'INTPL',0x12:'MVMVA',0x13:'NCDS',0x14:'CDP',0x16:'NCDT',
       0x1B:'NCCS',0x1C:'CC',0x1E:'NCS',0x20:'NCT',0x28:'SQR',0x29:'DCPL',0x2A:'DPCT',0x2D:'AVSZ3',0x2E:'AVSZ4',
       0x30:'RTPT',0x3D:'GPF',0x3E:'GPL',0x3F:'NCCT'}
def dis_word(addr, w):
    op = w >> 26
    if op == 0x12:  # COP2
        rs = (w>>21)&31; rt=(w>>16)&31; rd=(w>>11)&31
        if w & (1<<25): return f"gte {GTE.get(w&0x3F, 'op%02X'%(w&0x3F))}{' sf' if w&(1<<19) else ''}{' lm' if w&(1<<10) else ''}"
        return {0:f"mfc2 $r{rt}, gte{rd}",2:f"cfc2 $r{rt}, ctl{rd}",4:f"mtc2 $r{rt}, gte{rd}",6:f"ctc2 $r{rt}, ctl{rd}"}.get(rs,f"cop2 ?")
    if op == 0x32: return f"lwc2 gte{(w>>16)&31}, 0x{w&0xFFFF:X}($r{(w>>21)&31})"
    if op == 0x3A: return f"swc2 gte{(w>>16)&31}, 0x{w&0xFFFF:X}($r{(w>>21)&31})"
    for i in md.disasm(struct.pack('<I',w), addr): return f"{i.mnemonic} {i.op_str}"
    return f".word 0x{w:08X}"
def load_exe(p='disc/SCUS_944.88'):
    d=open(p,'rb').read(); t=struct.unpack_from('<I',d,0x18)[0]; return t, d[2048:]
if __name__=='__main__':
    t_addr, code = load_exe()
    start=int(sys.argv[1],16); end=int(sys.argv[2],16)
    marks={int(x,16) for x in sys.argv[3:]}
    for a in range(start,end,4):
        w=struct.unpack_from('<I',code,a-t_addr)[0]
        print(f"  {a:08X}  {w:08X}  {dis_word(a,w)}{'   <==' if a in marks else ''}")
