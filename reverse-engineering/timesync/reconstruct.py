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
        stubs[named['.plt.sec'][3] + i // 24 * 16] = symbols[info >> 32]
    mapped = [(s[4], s[5], s[3]) for s in sections if s[1] != 8]
    return mapped, imports, stubs


def pe_metadata(data):
    pe = struct.unpack_from('<I', data, 60)[0]
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional = pe + 24
    header_size = struct.unpack_from('<H', data, pe + 20)[0]
    base = struct.unpack_from('<Q', data, optional + 24)[0]
    section_offset = optional + header_size
    sections = [struct.unpack_from('<8sIIIIIIHHI', data, section_offset + i * 40) for i in range(count)]
    mapped = [(s[4], s[3], base + s[2]) for s in sections]
    def file_offset(rva):
        for s in sections:
            if s[2] <= rva < s[2] + s[3]:
                return s[4] + rva - s[2]
        raise ValueError(f'Unmapped RVA: {rva:x}')
    descriptor = file_offset(struct.unpack_from('<I', data, optional + 120)[0])
    imports = {}
    while True:
        lookup, _, _, dll, iat = struct.unpack_from('<IIIII', data, descriptor)
        if not dll:
            break
        i = 0
        while True:
            entry = struct.unpack_from('<Q', data, file_offset(lookup or iat) + i * 8)[0]
            if not entry:
                break
            if entry >> 63:
                name = f'ordinal {entry & 65535}'
            else:
                name = data[file_offset(entry) + 2:].split(b'\0')[0].decode()
            imports[base + iat + i * 8] = name
            i += 1
        descriptor += 20
    return mapped, imports, {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binaries', type=Path, default=Path(__file__).resolve().parents[3] / 'Lab599-TRX-TimeSync-EN')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    objdump = shutil.which('objdump')
    if not objdump:
        parser.error('objdump is required')
    hashes = []
    for platform, filename, metadata, start, end in [
        ('linux', 'TRX-TimeSync(x64)', elf_metadata, 0x406d30, 0x40741b),
        ('windows', 'TRX-TimeSync(x64).exe', pe_metadata, 0x140001050, 0x140001813),
    ]:
        binary = args.binaries / filename
        data = binary.read_bytes()
        hashes.append(f'{hashlib.sha256(data).hexdigest()}  {filename}')
        mappings, imports, stubs = metadata(data)
        disassembly = subprocess.check_output([objdump, '-d', '-M', 'intel', str(binary)], text=True)
        annotated, application = [], []
        for line in disassembly.splitlines():
            m = re.search(r'(?:call|jmp)\s+0x([0-9a-f]+)', line)
            if m and int(m[1], 16) in stubs:
                line += ' ; ' + stubs[int(m[1], 16)]
            m = re.search(r'# 0x([0-9a-f]+)', line)
            if m and int(m[1], 16) in imports:
                line += ' ; ' + imports[int(m[1], 16)]
            annotated.append(line)
            m = re.match(r'\s*([0-9a-f]+):', line)
            if m and start <= int(m[1], 16) < end:
                application.append(line)
        (args.output / f'{platform}-disassembly.txt').write_text('\n'.join(annotated) + '\n')
        (args.output / f'{platform}-application.txt').write_text('\n'.join(application) + '\n')
        (args.output / f'{platform}-import-map.txt').write_text('\n'.join(f'{a:016x} {name}' for a, name in imports.items()) + '\n')
        lines = []
        for encoding, pattern in [('ascii', rb'[\x20-\x7e]{4,}'), ('utf-16le', rb'(?:[\x20-\x7e]\x00){2,}')]:
            for match in re.finditer(pattern, data):
                address = next((base + match.start() - off for off, size, base in mappings
                                if off <= match.start() < off + size), 0)
                lines.append(f'file={match.start():08x} va={address:016x} {encoding}: {match.group().decode(encoding)}')
        (args.output / f'{platform}-strings.txt').write_text('\n'.join(lines) + '\n')
    (args.output / 'SHA256SUMS.txt').write_text('\n'.join(hashes) + '\n')
    print('Static evidence regenerated for Linux and Windows; neither binary was executed.')


if __name__ == '__main__':
    main()
