#!/usr/bin/env python3
"""Reproduce static evidence for the supplied Lab599 TimeSync executables.
Standard Python only; requires an objdump supporting ELF64 and PE32+.
Does not execute either binary or open a serial port.
"""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import struct
import subprocess


def elf_metadata(data):
    offset = struct.unpack_from('<Q', data, 40)[0]
    count, names_index = struct.unpack_from('<HH', data, 60)
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * 64) for i in range(count)]
    names = sections[names_index]
    table = data[names[4]:names[4] + names[5]]
    named = {table[s[0]:].split(b'\0')[0].decode(): s for s in sections}
    strings = named['.dynstr']
    strings = data[strings[4]:strings[4] + strings[5]]
    syms = named['.dynsym']
    symbols = [strings[struct.unpack_from('<I', data, syms[4] + i)[0]:].split(b'\0')[0].decode()
               for i in range(0, syms[5], 24)]
    relocations = named['.rela.plt']
    imports, stubs = {}, {}
    for i in range(0, relocations[5], 24):
        address, info, _ = struct.unpack_from('<QQq', data, relocations[4] + i)
        imports[address] = symbols[info >> 32]
        stubs[(named['.plt.sec'][3] if '.plt.sec' in named else named['.plt'][3] + 16) + i // 24 * 16] = symbols[info >> 32]
    mapped = [(s[4], s[5], s[3]) for s in sections if s[1] != 8]
    return mapped, imports, stubs


def pe_metadata(data):
    pe = struct.unpack_from('<I', data, 60)[0]
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional = pe + 24
    header_size = struct.unpack_from('<H', data, pe + 20)[0]
    wide = struct.unpack_from('<H', data, optional)[0] == 0x20b
    width = 8 if wide else 4
    base = struct.unpack_from('<Q' if wide else '<I', data, optional + (24 if wide else 28))[0]
    section_offset = optional + header_size
    sections = [struct.unpack_from('<8sIIIIIIHHI', data, section_offset + i * 40) for i in range(count)]
    mapped = [(s[4], s[3], base + s[2]) for s in sections]
    def file_offset(rva):
        for s in sections:
            if s[2] <= rva < s[2] + s[3]:
                return s[4] + rva - s[2]
        raise ValueError(f'Unmapped RVA: {rva:x}')
    descriptor = file_offset(struct.unpack_from('<I', data, optional + (120 if wide else 104))[0])
    imports = {}
    while True:
        lookup, _, _, dll, iat = struct.unpack_from('<IIIII', data, descriptor)
        if not dll:
            break
        i = 0
        while True:
            entry = struct.unpack_from('<Q' if wide else '<I', data, file_offset(lookup or iat) + i * width)[0]
            if not entry:
                break
            if entry >> (width * 8 - 1):
                name = f'ordinal {entry & 65535}'
            else:
                name = data[file_offset(entry) + 2:].split(b'\0')[0].decode()
            imports[base + iat + i * width] = name
            i += 1
        descriptor += 20
    return mapped, imports, {}


def main():
    root = Path(__file__).resolve().parents[2]
    for kind, directory in [('settings', 'Lab599-TRX-Settings-EN'), ('memory', 'Lab599-TRX-Mem-EN'), ('testcat', 'Lab599-TRX-TestCAT-1.1-EN')]:
        out = Path(__file__).parent / kind
        out.mkdir(exist_ok=True)
        hashes = []
        for binary in sorted((root / directory).iterdir()):
            data = binary.read_bytes() if binary.is_file() else b''
            if data[:2] != b'MZ' and data[:4] != b'\x7fELF': continue
            tag = 'linux' if data[:4] == b'\x7fELF' else ('x64' if 'x64' in binary.name else 'x86')
            maps, imports, stubs = (elf_metadata if tag == 'linux' else pe_metadata)(data)
            dis = subprocess.check_output(['objdump', '-d', '-M', 'intel', str(binary)], text=True)
            strings = {}
            for enc, pat in [('ascii', rb'[\x20-\x7e]{3,}'), ('utf-16le', rb'(?:[\x20-\x7e]\x00){1,}')]:
                for match in re.finditer(pat, data):
                    addr = next((base + match.start() - off for off, size, base in maps if off <= match.start() < off+size), 0)
                    if addr >= 0x400000: strings[addr] = (enc, match.group().decode(enc))
            lines = []
            for line in dis.splitlines():
                a = re.search(r'(?:call|jmp)\s+0x([0-9a-f]+)', line)
                b = re.search(r'# 0x([0-9a-f]+)', line)
                if a and int(a[1],16) in stubs: line += ' ; ' + stubs[int(a[1],16)]
                if b and int(b[1],16) in imports: line += ' ; ' + imports[int(b[1],16)]
                for addr in re.findall(r'0x([0-9a-f]+)', line):
                    if int(addr,16) >= 0x400000 and int(addr,16) in strings and strings[int(addr,16)][0] == 'utf-16le' and len(strings[int(addr,16)][1]) > 1:
                        line += ' ; literal ' + repr(strings[int(addr,16)][1])
                lines.append(line)
            (out / (tag+'-disassembly.txt')).write_text('\n'.join(lines)+'\n')
            (out / (tag+'-strings.txt')).write_text('\n'.join(f'{a:016x} {enc}: {v}' for a,(enc,v) in sorted(strings.items()))+'\n')
            hashes.append(hashlib.sha256(data).hexdigest()+'  '+binary.name)
        (out/'SHA256SUMS.txt').write_text('\n'.join(hashes)+'\n')
    print('Rebuilt static evidence without executing the supplied programs.')

if __name__ == '__main__': main()
