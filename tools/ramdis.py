#!/usr/bin/env python3
"""Disassemble a range of a 2 MB RAM dump: ramdis.py <dump.bin> <start_hex> <end_hex> [mark_hex...]"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mipsdis import dis_word
ram = open(sys.argv[1], 'rb').read()
start = int(sys.argv[2], 16); end = int(sys.argv[3], 16); marks = {int(x, 16) for x in sys.argv[4:]}
for a in range(start, end, 4):
    w = struct.unpack_from('<I', ram, a & 0x1FFFFF)[0]
    print(f"  {a:08X}  {w:08X}  {dis_word(a, w)}{'   <==' if a in marks else ''}")
