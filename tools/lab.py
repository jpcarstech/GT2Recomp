#!/usr/bin/env python3
"""Tiny lab client for the runtime's debug server (127.0.0.1:4370).

    from lab import Lab
    L = Lab(); L.read(0x800A9228, 4); L.write8(0x800F364E, 0x83); L.regs()
"""
import json, socket, time

class Lab:
    def __init__(self, host="127.0.0.1", port=4370, timeout=10):
        self.host, self.port, self.timeout = host, port, timeout
        self.id = 0
    def cmd(self, **kw):
        # One connection per command: the server does not reliably answer a
        # second request on the same socket after some commands.
        self.id += 1
        kw["id"] = self.id
        s = socket.create_connection((self.host, self.port), timeout=self.timeout)
        s.sendall((json.dumps(kw) + "\n").encode())
        f = s.makefile("r")
        try:
            for _ in range(50):
                line = f.readline()
                if not line: return None
                try: o = json.loads(line)
                except ValueError: continue
                if o.get("id") == self.id: return o
        finally:
            s.close()
        return None
    def read(self, addr, n):
        r = self.cmd(cmd="read_ram", addr=f"0x{addr:08X}", len=n)
        return bytes.fromhex(r["hex"])
    def r8(self, a):  return self.read(a, 1)[0]
    def r16(self, a): return int.from_bytes(self.read(a, 2), "little")
    def r32(self, a): return int.from_bytes(self.read(a, 4), "little")
    def write8(self, addr, val):
        return self.cmd(cmd="write_ram", addr=f"0x{addr:08X}", val=f"0x{val:02X}")
    def write16(self, addr, val):
        self.write8(addr, val & 0xFF); self.write8(addr + 1, (val >> 8) & 0xFF)
    def regs(self): return self.cmd(cmd="get_registers")
    def frame(self): return self.cmd(cmd="frame")
    def hexdump(self, addr, n, width=16):
        b = self.read(addr, n)
        for i in range(0, n, width):
            print(f"{addr+i:08X}  " + " ".join(f"{x:02X}" for x in b[i:i+width]))
